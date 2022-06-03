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

(** Network modeling

This models a network with a [Delay.t] function which returns [None] when a message
ought to be dropped or an amount of time after the current time at which the
message should be delivered.

For easy use of random probability distributions and so on, we provide
a sub-module [Delay] with a simple DSL.

To use the [Delay] module, create a [Delay.t] via the combinators provided.

*)

module Delay : sig
  type t =
    now:Time.t ->
    iteration:int ->
    effect_index:int ->
    sender:Node.Id.t ->
    receiver:Node.Id.t ->
    Time.t option
  (** A delay function determines if a message from a sender node will
  reach some receiver node, and if so, how long it will take.

  It should return [None] to mean that a message is lost. It takes the current
  time so one could implement, for example, periods of asynchrony for a few
  specific nodes between 2.0 and 4.0 seconds in global time. *)

  val const : float -> t
  val normal : mu:float -> sigma:float -> t
  val linear : min:float -> max:float -> t

  val add : t -> t -> t
  (** If one of the arguments returns None, return None. This allows us to
      mix in conditions for lost messages without affecting delay logic. *)

  val default : t
end
