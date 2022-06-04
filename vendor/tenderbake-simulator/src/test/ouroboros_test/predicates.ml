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
open Ouroboros
module List = Tenderbatter_test_helpers.Helpers.List

(** A generic safety predicate

Effectively, going back [3t+1] slots in the past is sufficient
where [t] is the number of bad nodes. For our tests, we don't have
any byzantine nodes, so we just go back one time stamp.

We check that all pairs of chains are prefixes except for the head of the
longest one.

 *)

(** Going 3t+1 slots backward, this checks [chain0] is a prefix of [chain1]
    and passes along [chain1] *)
let test_chains (chain0, acc) chain1 : Blockchain.block list * bool =
  let final_c0 = List.rev @@ List.tail chain0 in
  let final_c1 = List.rev @@ List.tail chain1 in
  let eq_blocks (x, y) =
    Blockchain.(x.slot = y.slot && x.transactions = y.transactions)
  in
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
  (* Now that we have an length-ascending list of all blockchains,
     to check pairwise prefixes it suffices to check prefixes of all
     adjacent pairs with a fold.
  *)
  match sorted_chains with
  | [] -> true
  | x :: xs -> snd @@ List.fold_left test_chains (x, true) xs

(** A generic liveness predicate

Assume the following

- synchrony and no byzantine nodes
- each slot is long enough that we have [n] wake up calls (for [n] nodes) and
  [n-1] messages of a new chain.

Then, at iteration [k*(2*n - 1)], each node must have at least [k] blocks.

Hence, to check liveness, we simply divide the iteration count by [2*n - 1] and
check that we have that many blocks in each live node.
 *)

let liveness total_nodes _ iter_num states =
  let min_chain_len = iter_num / ((2 * total_nodes) - 1) in
  let is_min_len opt_state =
    match opt_state with
    | None -> true
    | Some (_, _, state) -> Algorithm.(List.length state.chain >= min_chain_len)
  in
  Array.for_all is_min_len states

(** Test transactions are unique in the blockchains *)
let get_txns state =
  let open Algorithm in
  let open Blockchain in
  let { chain; _ } = state in
  let get_txn { transactions; _ } = transactions in
  List.flatten @@ List.map (fun x -> get_txn (Signed.get_value x)) chain
