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

let is_baker total_nodes node_id slot = Int.equal (slot mod total_nodes) node_id

module Blockchain = struct
  type block = { slot : int; transactions : Transaction.t list }

  let block_encoding =
    let open Data_encoding in
    conv
      (fun b -> (b.slot, b.transactions))
      (fun (slot, transactions) -> { slot; transactions })
      (obj2 (req "slot" int31)
         (req "transactions" @@ list Transaction.encoding))

  let is_valid_block total_nodes (Signed.T (block, signature) as signed) =
    let block_producer = Signature.signer signature in
    Signed.is_valid block_encoding signed
    && is_baker total_nodes (Node.Id.to_int block_producer) block.slot

  let is_valid total_nodes node_slot chain =
    match chain with
    | [] -> true
    | Signed.T (x, s) :: xs ->
        x.slot <= node_slot
        && List.for_all (is_valid_block total_nodes) (Signed.T (x, s) :: xs)

  type t = block Signed.t list

  let encoding = Data_encoding.list (Signed.encoding block_encoding)
  let genesis = []
end

module Algorithm = struct
  type message = New_chain of Blockchain.t

  let message_encoding =
    let open Data_encoding in
    conv (fun (New_chain b) -> b) (fun b -> New_chain b) Blockchain.encoding

  type node_state = { id : Node.Id.t; slot : int; chain : Blockchain.t }

  let init_node_state _ node_id =
    { id = node_id; slot = 0; chain = Blockchain.genesis }

  let node_state_encoding =
    let open Data_encoding in
    conv
      (fun st -> (st.id, st.slot, st.chain))
      (fun (id, slot, chain) -> { id; slot; chain })
      (obj3
         (req "id" Node.Id.encoding)
         (req "slot" int31)
         (req "chain" Blockchain.encoding))

  type params = { total_nodes : int; slot_duration : float }

  let params_encoding =
    let open Data_encoding in
    conv
      (fun { total_nodes; slot_duration } -> (total_nodes, slot_duration))
      (fun (total_nodes, slot_duration) -> { total_nodes; slot_duration })
      (obj2 (req "total_nodes" int31) (req "slot_duration" float))
end

(** Make a [params] value by taking [total_nodes] and initializing the
    remaining parameters with their default values. *)
let default_params total_nodes = { Algorithm.total_nodes; slot_duration = 1. }

include Simulator.Make (Algorithm)

(** Duration of a slot is fixed to be 1 second for now. *)
let good_node params time event private_key state =
  let open Algorithm in
  let current_slot =
    int_of_float (Time.to_float time /. params.slot_duration)
  in
  match event with
  | Event.Message_received (New_chain chain) ->
      let is_valid =
        Blockchain.is_valid params.total_nodes current_slot chain
      in
      let is_longer = List.length state.chain < List.length chain in
      let next_chain = if is_valid && is_longer then chain else state.chain in
      let next_state = { state with chain = next_chain } in
      ([], next_state)
  | Event.Wake_up -> (
      let next_time =
        Time.from_float (float_of_int (current_slot + 1) *. params.slot_duration)
      in
      let wake_again = Effect.Set_wake_up_time next_time in
      match
        is_baker params.total_nodes (Node.Id.to_int state.id) current_slot
      with
      | false ->
          let nxt_state = { state with slot = current_slot } in
          ([ wake_again ], nxt_state)
      | true ->
          let open Blockchain in
          let unsigned_block =
            { slot = current_slot; transactions = [ Transaction.originate () ] }
          in
          let signed_block =
            Signed.make private_key block_encoding unsigned_block
          in
          let new_chain = signed_block :: state.chain in
          let broadcast = Effect.Send_message (New_chain new_chain) in
          let nxt_state =
            { state with slot = current_slot; chain = new_chain }
          in
          ([ broadcast; wake_again ], nxt_state))
