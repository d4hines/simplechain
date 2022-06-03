(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021 Nomadic Labs, <contact@nomadic-labs.com>               *)
(*                                                                           *)
(* Permission is hereby granted, free of charge, to any person obtaining a   *)
(* copy of this software and associated documentation files (the "Software"),*)
(* to deal in the Software without restriction, including without limitation *)
(* the rights to use, copy, modify, merge, publish, distribute, sublicense,  *)
(* and/or sell copies of the Software, and to permit persons to whom the     *)
(* Software is furnished to do so, subject to the following conditions:      *)
(*                                                                           *)
(* The above copyright notice and this permission notice shall be included   *)
(* in all copies or substantial portions of the Software.                    *)
(*                                                                           *)
(* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR*)
(* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,  *)
(* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL   *)
(* THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER*)
(* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING   *)
(* FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER       *)
(* DEALINGS IN THE SOFTWARE.                                                 *)
(*                                                                           *)
(*****************************************************************************)

module Delay = struct
  type t =
    now:Time.t ->
    iteration:int ->
    effect_index:int ->
    sender:Node.Id.t ->
    receiver:Node.Id.t ->
    Time.t option

  (* This helps to avoid writing out arguments in each constructor. *)
  let hoist f ~now:_ ~iteration:_ ~effect_index:_ ~sender:_ ~receiver:_ =
    Some (Time.from_float (f ()))

  let const x = hoist (fun () -> x)

  let normal ~mu ~sigma =
    hoist (fun () -> Owl_base.Stats.gaussian_rvs ~mu ~sigma)

  let linear ~min ~max =
    hoist (fun () -> Owl_base.Stats.uniform_rvs ~a:min ~b:max)

  let add f1 f2 ~now ~iteration ~effect_index ~sender ~receiver =
    (fun t ->
      Option.map (Time.add t)
        (f2 ~now ~iteration ~effect_index ~sender ~receiver))
    |> Option.bind (f1 ~now ~iteration ~effect_index ~sender ~receiver)

  let default = add (const 0.1) (normal ~mu:0.5 ~sigma:0.15)
end
