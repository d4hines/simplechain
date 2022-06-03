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

open Tenderbatter
open Emmy_plus
module List = Helpers.List

(** Emmy+ Safety and Liveness Predicates

Since Emmy+ uses probabilistic finality, encoding this especially with
[Alcotest] is quite difficult. Instead, the approach taken here is to use
constants based off of experimenting with runs.

Assume these conditions:

  * The default parameters are used with a delay function that requires
    half of the nodes to endorse
  * We have a synchronous network with a max delay of about 1
  * We are running 10 good nodes and no byzantine nodes

Experiments suggest going back 2 blocks almost always ensures safety
so the tests go back 4.

Experiments suggest a rate of one block per 120 iterations and the
tests here assume one block per 140 iterations.

 *)

let test_chains (chain0, acc) chain1 : Blockchain.block list * bool =
  (* Hard coded constant number to drop *)
  let final_c0 = List.rev @@ List.drop 4 chain0 in
  let final_c1 = List.rev @@ List.drop 4 chain1 in
  let eq_blocks (x, y) = Blockchain.eq_blocks x y in
  let test = List.for_all eq_blocks @@ List.zip final_c0 final_c1 in
  let acc' = acc && test in
  (chain1, acc')

let safety _ _ states =
  let chains : Blockchain.block list list =
    List.map (List.map Signed.(function T (a, _) -> a))
    @@ List.map Algorithm.(fun s -> s.chain)
    @@ List.map (fun (_, _, x) -> x)
    @@ List.filter_map (fun x -> x)
    @@ Array.to_list states
  in
  let sorted_chains = List.sort List.compare_lengths chains in
  match sorted_chains with
  | [] -> true
  | x :: xs -> snd @@ List.fold_left test_chains (x, true) xs

let liveness _ iteration states =
  (* Using hard coded constant from experimenting *)
  let min_chain_len = iteration / 140 in
  let is_min_len opt_state =
    match opt_state with
    | None -> true
    | Some (_, _, state) -> Algorithm.(List.length state.chain >= min_chain_len)
  in
  Array.for_all is_min_len states

(** Test transactions are unique in the blockchains *)

let get_txns node_state =
  let open Algorithm in
  let open Blockchain in
  let { chain; _ } = node_state in
  let get_txn { transactions; _ } = transactions in
  List.flatten @@ List.map (fun x -> get_txn (Signed.get_value x)) chain
