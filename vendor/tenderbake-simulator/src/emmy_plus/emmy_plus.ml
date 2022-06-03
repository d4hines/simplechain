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

(** Assumptions/Design Choices
 *
 * - Every node gets to be an endorser
 * - We have the priority queue of bakers as follows.
 *   Say we have [n] nodes numbered [0] to [n-1].
 *   At level [l], the baker at priority 0 is [l mod n]. The baker
 *   at priority 1 is [(l + 1) mod n] and so on, cycling through.
 * *)

open Tenderbatter

type algo_params = {
  total_nodes : int;
  refresh_time : float;
  base_delay : float;
  (* base delay *)
  priority_delay : float;
  (* priority delay, that is, delay per missed baking slot *)
  endorsement_delay : float;
  (* delay per missed endorsement slot *)
  initial_endorsements : int; (* initially required number of endorsements *)
}

(** Counting mod n, the distance to go from [a] to [b] *)
let mod_distance n a b = (b + n - a) mod n

(** Given a level and priority, return the integer of the current baker at that
 * priority. *)
let owner_fn total_nodes level priority = (level + priority) mod total_nodes

(** Given a level, determine the priority of a node at that level *)
let priority_fn total_nodes node_id_int level =
  mod_distance total_nodes (level mod total_nodes) node_id_int

(** Determine if a node is an endorser at a level *)
let endorsers_fn _total_nodes _level _node_id = true

(** Determine the minimum delay between blocks. *)
let delay params priority endorsement_count =
  params.base_delay
  +. (params.priority_delay *. float_of_int priority)
  +. params.endorsement_delay
     *. max 0. (float_of_int (params.initial_endorsements - endorsement_count))

module Blockchain = struct
  type block = {
    transactions : Transaction.t list;
    priority : int;
    endorsements : endorsement Signed.t list;
    timestamp : Time.t;
    level : int;
  }

  and endorsement = { block : block Hash.t; level : int }

  let eq_blocks b0 b1 =
    b0.transactions = b1.transactions
    && b0.priority = b1.priority
    && b0.timestamp = b1.timestamp
    && b0.level = b1.level

  let transaction_encoding = Data_encoding.int31

  let endorsement_encoding =
    let open Data_encoding in
    conv
      (fun { block; level } -> (block, level))
      (fun (block, level) -> { block; level })
      (obj2 (req "block" (Hash.encoding ())) (req "level" int31))

  let block_encoding =
    let open Data_encoding in
    conv
      (fun b ->
        (b.transactions, b.priority, b.endorsements, b.timestamp, b.level))
      (fun (transactions, priority, endorsements, timestamp, level) ->
        { transactions; priority; endorsements; timestamp; level })
      (obj5
         (req "transactions" (list Transaction.encoding))
         (req "priority" int31)
         (req "endorsements" (list (Signed.encoding endorsement_encoding)))
         (req "timestamp" Time.encoding)
         (req "level" int31))

  type t = block Signed.t list

  let encoding = Data_encoding.list (Signed.encoding block_encoding)

  let is_valid_endorsement params (Signed.T (endorsement, signature) as signed)
      =
    let endorser = Signature.signer signature in
    Signed.is_valid endorsement_encoding signed
    && endorsers_fn params.total_nodes endorsement.level endorser

  let is_valid_block params (Signed.T (block, _signature) as signed)
      previous_timestamp =
    let valid_endorsements =
      List.for_all (is_valid_endorsement params) block.endorsements
    in
    let valid_signature = Signed.is_valid block_encoding signed in
    let expected_delay =
      delay params block.priority (List.length block.endorsements)
    in
    let valid_time =
      Time.to_float block.timestamp
      > Time.to_float previous_timestamp +. expected_delay
    in
    valid_endorsements && valid_signature && valid_time

  let is_valid_chain params chain =
    let rec loop chain =
      match chain with
      | [] -> true
      | [ block ] -> is_valid_block params block Time.init
      | block :: (Signed.T (previous_block, _) as previous_signed) :: xs ->
          is_valid_block params block previous_block.timestamp
          && loop (previous_signed :: xs)
    in
    loop chain

  let genesis = []
end

module Algorithm = struct
  type message =
    | New_chain of Blockchain.t
    | New_endorsement of Blockchain.endorsement Signed.t

  let message_encoding =
    let open Data_encoding in
    union
      [
        case ~title:"new_chain" (Tag 0) Blockchain.encoding
          (function New_chain b -> Some b | _ -> None)
          (fun b -> New_chain b);
        case ~title:"new_endorsement" (Tag 1)
          (Signed.encoding Blockchain.endorsement_encoding)
          (function New_endorsement e -> Some e | _ -> None)
          (fun e -> New_endorsement e);
      ]

  type node_state = {
    id : Node.Id.t;
    priority : int;
    endorsements : Blockchain.endorsement Signed.t list;
    chain : Blockchain.t;
  }

  let init_node_state _ node_id =
    {
      id = node_id;
      priority = Node.Id.to_int node_id;
      endorsements = [];
      chain = [];
    }

  let node_state_encoding =
    let open Data_encoding in
    conv
      (fun { id; priority; endorsements; chain } ->
        (id, priority, endorsements, chain))
      (fun (id, priority, endorsements, chain) ->
        { id; priority; endorsements; chain })
      (obj4
         (req "id" Node.Id.encoding)
         (req "priority" int31)
         (req "endorsements"
         @@ list (Signed.encoding Blockchain.endorsement_encoding))
         (req "chain" Blockchain.encoding))

  type params = algo_params

  let params_encoding =
    let open Data_encoding in
    conv
      (fun {
             total_nodes;
             refresh_time;
             base_delay;
             priority_delay;
             endorsement_delay;
             initial_endorsements;
           } ->
        ( total_nodes,
          refresh_time,
          base_delay,
          priority_delay,
          endorsement_delay,
          initial_endorsements ))
      (fun ( total_nodes,
             refresh_time,
             base_delay,
             priority_delay,
             endorsement_delay,
             initial_endorsements ) ->
        {
          total_nodes;
          refresh_time;
          base_delay;
          priority_delay;
          endorsement_delay;
          initial_endorsements;
        })
      (obj6 (req "total_nodes" int31) (req "refresh_time" float)
         (req "base_delay" float)
         (req "priority_delay" float)
         (req "endorsement_delay" float)
         (req "initial_endorsements" int31))
end

(** Make a [params] value by taking [total_nodes] and initializing the
   remaining parameters with their default values. *)
let default_params total_nodes =
  {
    total_nodes;
    refresh_time = 1.;
    base_delay = 0.;
    priority_delay = 3.;
    endorsement_delay = 1.;
    initial_endorsements = total_nodes / 2;
  }

include Simulator.Make (Algorithm)

(** Build an endorsement for a block. *)
let build_endorsement private_key (head_block : Blockchain.block) =
  let open Blockchain in
  let level = head_block.level in
  let block_hash = Hash.make block_encoding head_block in
  let endorsement = { block = block_hash; level } in
  Signed.make private_key endorsement_encoding endorsement

let good_node params time event private_key state =
  let open Algorithm in
  match event with
  | Event.Message_received (New_endorsement (Signed.T (e, _) as signed)) ->
      (* Only store valid endorsements for head of current chain. *)
      if
        Blockchain.is_valid_endorsement params signed
        && (not @@ List.exists (fun x -> x = signed) state.endorsements)
      then
        match state.chain with
        | [] -> ([], state) (* No endorsements for blocks before genesis *)
        | Signed.T (head, _) :: _ -> (
            match Hash.check Blockchain.block_encoding head e.block with
            | true ->
                let new_endorsements = signed :: state.endorsements in
                ([], { state with endorsements = new_endorsements })
            | false -> ([], state))
      else ([], state)
  | Event.Message_received (New_chain chain) -> (
      let is_valid = Blockchain.is_valid_chain params chain in
      let is_more_fit = List.length state.chain < List.length chain in
      match is_valid && is_more_fit with
      | false -> ([], state)
      | true -> (
          (* If the chain is longer than the current one, it is non-empty *)
          let (Signed.T (head, _)) = List.hd chain in
          let level = head.level in
          let new_priority =
            priority_fn params.total_nodes (Node.Id.to_int state.id) level
          in
          let new_state =
            { state with chain; priority = new_priority; endorsements = [] }
          in
          match endorsers_fn params.total_nodes level state.id with
          | false -> ([], new_state)
          | true ->
              let signed_endorsement = build_endorsement private_key head in
              let open Effect in
              let endorse_msg =
                Send_message (New_endorsement signed_endorsement)
              in
              let new_state =
                { new_state with endorsements = [ signed_endorsement ] }
              in
              ([ endorse_msg ], new_state)))
  | Event.Wake_up -> (
      let curr_time = Time.to_float time in
      let next_wake =
        Effect.Set_wake_up_time
          (Time.from_float (curr_time +. params.refresh_time))
      in
      let valid_bake_time =
        match state.chain with
        | [] -> curr_time > delay params state.priority 0
        | Signed.T (curr_head, _) :: _ ->
            let head_ts = Time.to_float curr_head.timestamp in
            let num_endorsements = List.length state.endorsements in
            let min_delay =
              head_ts +. delay params state.priority num_endorsements
            in
            curr_time > min_delay
      in
      match valid_bake_time with
      | false -> ([ next_wake ], state)
      | true -> (
          let node_id = Node.Id.to_int state.id in
          let endorsements = state.endorsements in
          let open Blockchain in
          let next_level =
            match state.chain with
            | [] -> 1
            | Signed.T (head, _) :: _ -> head.level + 1
          in
          let unsigned_block =
            {
              transactions = [ Transaction.originate () ];
              priority = state.priority;
              endorsements;
              timestamp = time;
              level = next_level;
            }
          in
          let signed_block =
            Signed.make private_key Blockchain.block_encoding unsigned_block
          in
          let new_chain = signed_block :: state.chain in
          let new_priority =
            priority_fn params.total_nodes node_id next_level
          in
          let new_state =
            {
              state with
              priority = new_priority;
              endorsements = [];
              chain = new_chain;
            }
          in
          let broadcast_chain = Effect.Send_message (New_chain new_chain) in
          match endorsers_fn params.total_nodes next_level state.id with
          | false -> ([ next_wake; broadcast_chain ], new_state)
          | true ->
              let signed_endorsement =
                build_endorsement private_key unsigned_block
              in
              let endorse_msg =
                Effect.Send_message (New_endorsement signed_endorsement)
              in
              let new_state =
                { new_state with endorsements = [ signed_endorsement ] }
              in
              ([ next_wake; broadcast_chain; endorse_msg ], new_state)))
