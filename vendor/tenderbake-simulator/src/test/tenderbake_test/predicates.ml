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
open Tenderbake
module List = Helpers.List

(** Initial Predicate Design

 - We assume we have no byzantine nodes and a synchronous network with a max
   delay of 1

 - For safety we need to check for any two finalized chains, one is a prefix of
   another, where blocks are exactly equal except for predecessor EQCs or flags
   on if a block has been previously proposed. (We assume different nodes can
   finalize based on seeing different sets of endorsements.) The finalized parts
   of chains are the tails.

 - For liveness, note that with all well behaved nodes and a synchronous
   network, the chain grows linearly with the iteration count (for a fixed number
   of nodes).  So, one can experimentally determine a constant [c] such that the
   iteration number divided by [c] should be the minimal chain length.

 *)

let rec safety _ _ states =
  let chains : Blockchain.t Seq.t =
    Algorithm.(Seq.map (fun (_, _, state) -> state.chain))
    @@ Seq.filter_map (fun x -> x)
    @@ Array.to_seq states
  in
  match chains () with
  | Seq.Nil -> true
  | Seq.Cons (chain0, rest) -> snd @@ Seq.fold_left fold (chain0, true) rest

and fold (chain0, acc) chain1 =
  let final_chain0 = List.rev @@ List.tail chain0 in
  let final_chain1 = List.rev @@ List.tail chain1 in
  let chains_agree =
    List.for_all block_eq @@ List.zip final_chain0 final_chain1
  in
  let longer_chain =
    match List.length chain0 <= List.length chain1 with
    | true -> chain1
    | false -> chain0
  in
  (longer_chain, acc && chains_agree)

and block_eq (b0, b1) =
  let open Blockchain in
  let contents_eq =
    b0.contents.transactions == b1.contents.transactions
    && b0.contents.level == b1.contents.level
    && Option.equal Hash.equal b0.contents.predecessor_hash
         b1.contents.predecessor_hash
  in
  contents_eq && b0.round == b1.round && b0.timestamp == b1.timestamp

(* Remark: To check chain agreement of each pair of chains, it suffices to
   perform a fold [(bool * Blockchain.t) -> Blockchain.t -> (bool * Blockchain.t)]
   that [(&&)]s the chain agreement of the two input chains with the given bool
   and passes along the longest chain.

   This works because the passed along chain agrees with every chain before it
   in the fold. Since the final chain is the chain of maximum length, all chains
   agree with the longest chain and hence all chains agree.
*)

let liveness _ iteration states =
  let min_chain_len = iteration / 200 in
  let is_min_len chain = List.length chain >= min_chain_len in
  let fold test chain = test && is_min_len chain in
  Seq.fold_left fold true
  @@ Algorithm.(Seq.map (fun (_, _, state) -> state.chain))
  @@ Seq.filter_map (fun x -> x)
  @@ Array.to_seq states

(** Test transactions are unique in the blockchains *)
let get_txns node_state =
  let open Algorithm in
  let open Blockchain in
  let { chain; _ } = node_state in
  let get_txn { contents = { transactions; _ }; _ } = transactions in
  List.flatten @@ List.map get_txn chain
