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

(** [is_committee_member total_nodes node_id level] returns [true] when a
   node is a committee member, that is, when it can preendorse and endorse
   proposals. For now, all nodes are always committee members. *)
let is_committee_member _total_nodes _node_id _level = true

(** [is_proposer total_nodes node_id level round] returns [true] when the
    given [node_id] is the proposer at the given [level] and [round]. *)
let is_proposer total_nodes node_id level round =
  Int.equal (Node.Id.to_int node_id) ((level + round) mod total_nodes)

module Blockchain = struct
  type block_contents = {
    transactions : Transaction.t list;  (** Transactions in the block *)
    level : int;  (** The block's level *)
    predecessor_hash : block Hash.t option;  (** Predecessor block hash *)
  }
  (** The block contents. This is the part of a block that gets (pre)endorsed. *)

  and block = {
    contents : block_contents;  (** Block payload *)
    round : int;  (** The round at which the block was created *)
    timestamp : Time.t;  (** Time when the block was created *)
    predecessor_eqc : endorsement list;
        (** Endorsement quorum certificate of the predecessor block. *)
    previously_proposed : (int * preendorsement list) option;
        (** Whether this block has been previously proposed. *)
  }
  (** A block in the blockchain. *)

  and endorsement = Endorsement of block_contents Hash.t Signed.t
  and preendorsement = Preendorsement of block_contents Hash.t Signed.t

  let endorsement_encoding =
    let open Data_encoding in
    conv
      (fun (Endorsement x) -> x)
      (fun x -> Endorsement x)
      (Signed.encoding (Hash.encoding ()))

  let preendorsement_encoding =
    let open Data_encoding in
    conv
      (fun (Preendorsement x) -> x)
      (fun x -> Preendorsement x)
      (Signed.encoding (Hash.encoding ()))

  let block_contents_encoding =
    let open Data_encoding in
    conv
      (fun p -> (p.transactions, p.level, p.predecessor_hash))
      (fun (transactions, level, predecessor_hash) ->
        { transactions; level; predecessor_hash })
      (obj3
         (req "transactions" (list Transaction.encoding))
         (req "level" int31)
         (req "predecessor_hash" (option (Hash.encoding ()))))

  let block_encoding =
    let open Data_encoding in
    conv
      (fun b ->
        ( b.contents,
          b.round,
          b.timestamp,
          b.predecessor_eqc,
          b.previously_proposed ))
      (fun (contents, round, timestamp, predecessor_eqc, previously_proposed) ->
        { contents; round; timestamp; predecessor_eqc; previously_proposed })
      (obj5
         (req "block_contents" block_contents_encoding)
         (req "round" int31)
         (req "timestamp" Time.encoding)
         (req "predecessor_eqc" (list endorsement_encoding))
         (req "previously_proposed"
            (option
               (obj2 (req "round" int31)
                  (req "pqc" (list preendorsement_encoding))))))

  type t = block list
  (** The blockchain is a list of blocks. *)

  let encoding : t Data_encoding.t = Data_encoding.list block_encoding

  (** The initial state of the blockchain—effectively it is an empty list. *)
  let genesis : t = []
end

module Algorithm = struct
  (** Payload of a message. We attempt to avoid magical values and instead
      use OCaml ADTs to their full potential. *)
  type payload =
    | Propose of Blockchain.t
    | Preendorse of Blockchain.preendorsement
    | Endorse of (Blockchain.endorsement * Blockchain.preendorsement list)
    | Preendorsements of (Blockchain.block * Blockchain.preendorsement list)

  let payload_encoding =
    let open Data_encoding in
    union
      [
        case ~title:"propose" (Tag 0)
          (obj2
             (req "tag" (constant "propose"))
             (req "chain" Blockchain.encoding))
          (function Propose chain -> Some ((), chain) | _ -> None)
          (function (), chain -> Propose chain);
        case ~title:"preendorse" (Tag 1)
          (obj2
             (req "tag" (constant "preendorse"))
             (req "preendorsement" Blockchain.preendorsement_encoding))
          (function Preendorse p -> Some ((), p) | _ -> None)
          (function (), p -> Preendorse p);
        case ~title:"endorse" (Tag 2)
          (obj3
             (req "tag" (constant "endorse"))
             (req "endorsement" Blockchain.endorsement_encoding)
             (req "pqc" (list Blockchain.preendorsement_encoding)))
          (function Endorse (e, pqc) -> Some ((), e, pqc) | _ -> None)
          (function (), e, pqc -> Endorse (e, pqc));
        case ~title:"preendorsements" (Tag 3)
          (obj3
             (req "tag" (constant "preendorsements"))
             (req "block" Blockchain.block_encoding)
             (req "pqc" (list Blockchain.preendorsement_encoding)))
          (function Preendorsements (b, pqc) -> Some ((), b, pqc) | _ -> None)
          (function (), b, pqc -> Preendorsements (b, pqc));
      ]

  type unsigned_message = {
    level : int;
    round : int;
    previous_block_hash : Blockchain.block Hash.t option;
    payload : payload;
  }
  (** Every message in the model is signed; this data type represents
     contents of a message before signing. *)

  type message = unsigned_message Signed.t

  let unsigned_message_encoding : unsigned_message Data_encoding.t =
    let open Data_encoding in
    conv
      (fun m -> (m.level, m.round, m.previous_block_hash, m.payload))
      (fun (level, round, previous_block_hash, payload) ->
        { level; round; previous_block_hash; payload })
      (obj4 (req "level" int31) (req "round" int31)
         (req "previous_block_hash" (option (Hash.encoding ())))
         (req "payload" payload_encoding))

  let message_encoding = Signed.encoding unsigned_message_encoding

  type node_state = {
    id : Node.Id.t;  (** The node's id. *)
    chain : Blockchain.t;  (** The blockchain. *)
    proposal_state : proposal_state;  (** State of the current round. *)
    endorsable :
      (int * Blockchain.block_contents * Blockchain.preendorsement list) option;
        (** Endorsable round, block contents, preendorsement quorum certificate. *)
    locked :
      (int * Blockchain.block_contents * Blockchain.preendorsement list) option;
        (** Locked round, block content, preendorsement quorum certificate. *)
  }
  (** Local state of a node. *)

  and proposal_state =
    | No_proposal  (** No proposal received in this round. *)
    | Collecting_preendorsements of { acc : Blockchain.preendorsement list }
        (** A proposal has been received. The node is collecting
       preendorsements. *)
    | Collecting_endorsements of {
        pqc : Blockchain.preendorsement list;
        acc : Blockchain.endorsement list;
      }
        (** A preendorsement quorum certificate has been observed. The node
            is collecting endorsements. *)

  let proposal_state_encoding =
    let open Data_encoding in
    union
      [
        case ~title:"no_proposal" (Tag 0)
          (obj1 (req "tag" (constant "no_proposal")))
          (function No_proposal -> Some () | _ -> None)
          (function () -> No_proposal);
        case ~title:"collecting_preendorsements" (Tag 1)
          (obj2
             (req "tag" (constant "collecting_preendorsements"))
             (req "acc" (list Blockchain.preendorsement_encoding)))
          (function
            | Collecting_preendorsements m -> Some ((), m.acc) | _ -> None)
          (function (), acc -> Collecting_preendorsements { acc });
        case ~title:"collecting_endorsements" (Tag 2)
          (obj3
             (req "tag" (constant "collecting_endorsements"))
             (req "pqc" (list Blockchain.preendorsement_encoding))
             (req "acc" (list Blockchain.endorsement_encoding)))
          (function
            | Collecting_endorsements m -> Some ((), m.pqc, m.acc) | _ -> None)
          (function (), pqc, acc -> Collecting_endorsements { pqc; acc });
      ]

  type params = {
    total_nodes : int;
    quorum_size : int;
    round0_duration : float;
  }
  (** The algorithm parameters. *)

  let params_encoding =
    let open Data_encoding in
    conv
      (fun p -> (p.total_nodes, p.quorum_size, p.round0_duration))
      (fun (total_nodes, quorum_size, round0_duration) ->
        { total_nodes; quorum_size; round0_duration })
      (obj3 (req "total_nodes" int31) (req "quorum_size" int31)
         (req "round0_duration" float))

  (** Return duration of a round by its number. *)
  let round_duration params round =
    match round with
    | 0 -> params.round0_duration
    | 1 -> params.round0_duration *. 2.
    | _ -> params.round0_duration *. 4.

  (** Return absolute time when to wake up again given time of beginning of
     the current round and the round number. *)
  let synchronize params t_time round =
    let t = Time.to_float t_time in
    let next_round_time = t +. round_duration params round in
    Time.from_float next_round_time

  let init_node_state _params node_id =
    {
      id = node_id;
      chain = Blockchain.genesis;
      proposal_state = No_proposal;
      endorsable = None;
      locked = None;
    }

  let node_state_encoding =
    let open Data_encoding in
    conv
      (fun s -> (s.id, s.chain, s.proposal_state, s.endorsable, s.locked))
      (fun (id, chain, proposal_state, endorsable, locked) ->
        { id; chain; proposal_state; endorsable; locked })
      (obj5
         (req "id" Node.Id.encoding)
         (req "chain" Blockchain.encoding)
         (req "proposal_state" proposal_state_encoding)
         (req "endorsable"
            (option
               (obj3 (req "round" int31)
                  (req "block_contents" Blockchain.block_contents_encoding)
                  (req "pqc" (list Blockchain.preendorsement_encoding)))))
         (req "locked"
            (option
               (obj3 (req "round" int31)
                  (req "block_contents" Blockchain.block_contents_encoding)
                  (req "pqc" (list Blockchain.preendorsement_encoding))))))
end

include Simulator.Make (Algorithm)

(** Make a [params] value by taking [total_nodes] and initializing the
   remaining parameters with their default values. *)
let default_params total_nodes : Algorithm.params =
  (* If the total number of nodes is n has 3f < n for f byzantine nodes
     and we need the quorum size to be greater than 2f, then it suffices
     to use 2n/3 + 1 for the quorum size. *)
  let quorum_size = (2 * total_nodes / 3) + 1 in
  { total_nodes; quorum_size; round0_duration = 3. }

(** Check if a given quorum certificate has enough (pre)endorsements. This
   doesn't check if the individual (pre)endorsements are valid. *)
let is_qc_complete (params : Algorithm.params) qc =
  List.length qc >= params.quorum_size

(** Check whether given quorum certificate is valid for given block
   contents. *)
let is_qc_valid (params : Algorithm.params)
    (block_contents : Blockchain.block_contents) qc =
  let block_contents_hash =
    Hash.make Blockchain.block_contents_encoding block_contents
  in
  let check_endorsement (Signed.T (hash, signature) as signed) =
    let signer = Signature.signer signature in
    let has_endorsing_power =
      is_committee_member params.total_nodes signer block_contents.level
    in
    Signed.is_valid (Hash.encoding ()) signed
    && Hash.equal hash block_contents_hash
    && has_endorsing_power
  in
  List.for_all check_endorsement qc && is_qc_complete params qc

(** Check whether given EQC is valid for a given block. *)
let is_eqc_valid (params : Algorithm.params) block_contents eqc =
  is_qc_valid params block_contents
    (List.map (fun (Blockchain.Endorsement x) -> x) eqc)

(** Check whether given PQC is valid for a given block. *)
let is_pqc_valid (params : Algorithm.params) block_contents pqc =
  is_qc_valid params block_contents
    (List.map (fun (Blockchain.Preendorsement x) -> x) pqc)

(** Determine the decided level of the given chain. *)
let decided_level (chain : Blockchain.t) =
  match chain with _ :: block :: _ -> block.contents.level | _ -> 0

(** Determine the level of the head. *)
let head_level (chain : Blockchain.t) =
  match chain with block :: _ -> block.contents.level | _ -> 0

(** Determine the current round. *)
let current_round (chain : Blockchain.t) =
  match chain with block :: _ -> block.round | _ -> 0

(** Return hash of the head of the chain. [None] if the chain has 0 or 1 blocks. *)
let last_decided_block_hash (chain : Blockchain.t) =
  match chain with block :: _ -> block.contents.predecessor_hash | _ -> None

(** Return endorsement quorum certificate of the last decided block of the
   given chain. [None] if the chain has no blocks. *)
let last_decided_block_eqc (chain : Blockchain.t) =
  match chain with block :: _ -> Some block.predecessor_eqc | _ -> None

(** Check that the given message has correct level, round, and the hash of
   the last decided block for given node state. *)
let check_message_lrh (message : Algorithm.unsigned_message)
    (state : Algorithm.node_state) =
  let level_of_proposal = message.level in
  let round_of_proposal = message.round in
  let level_is_right = Int.equal (head_level state.chain) level_of_proposal in
  let round_is_right =
    Int.equal (current_round state.chain) round_of_proposal
  in
  let last_decided_block_hash_is_right =
    match
      (last_decided_block_hash state.chain, message.previous_block_hash)
    with
    | None, None -> true
    | Some hash0, Some hash1 -> Hash.equal hash0 hash1
    | _ -> false
  in
  level_is_right && round_is_right && last_decided_block_hash_is_right

(** Add endorsement to the node state. *)
let handle_endorsement params (state : Algorithm.node_state)
    (Blockchain.Endorsement signed as endorsement) =
  let open Algorithm in
  match state.chain with
  | [] -> state
  | block :: _ -> (
      let block_contents_hash =
        Hash.make Blockchain.block_contents_encoding block.contents
      in
      let state_with proposal_state = { state with proposal_state } in
      let add_to_acc (Blockchain.Endorsement he as e) acc =
        e
        :: List.filter
             (fun (Blockchain.Endorsement h) ->
               not (Signed.equal Hash.equal h he))
             acc
      in
      match state.proposal_state with
      | No_proposal -> state
      | Collecting_preendorsements _ -> state
      | Collecting_endorsements m ->
          (* If we already have a complete EQC, we can just ignore the
             endorsement. *)
          if
            Hash.equal (Signed.get_value signed) block_contents_hash
            && not (is_qc_complete params m.acc)
          then
            let new_acc = add_to_acc endorsement m.acc in
            let new_proposal_state =
              Collecting_endorsements { m with acc = new_acc }
            in
            state_with new_proposal_state
          else state)

(** Prepare an effect that sends endorse message, also update the node
   state. *)
let prepare_endorse params private_key (state : Algorithm.node_state) pqc =
  let open Algorithm in
  match state.chain with
  | [] -> ([], state)
  | block :: _ ->
      let previous_block_hash = block.contents.predecessor_hash in
      let block_contents_hash =
        Hash.make Blockchain.block_contents_encoding block.contents
      in
      let endorsement =
        Blockchain.Endorsement
          (Signed.make private_key (Hash.encoding ()) block_contents_hash)
      in
      let unsigned_message : Algorithm.unsigned_message =
        {
          level = block.contents.level;
          round = current_round state.chain;
          previous_block_hash;
          payload = Endorse (endorsement, pqc);
        }
      in
      let signed_message =
        Signed.make private_key Algorithm.unsigned_message_encoding
          unsigned_message
      in
      let new_state = handle_endorsement params state endorsement in
      ([ Effect.Send_message signed_message ], new_state)

(** Set endorsable component of the node state. *)
let set_endorsable (state : Algorithm.node_state) round block_contents pqc =
  let state0 = { state with endorsable = Some (round, block_contents, pqc) } in
  match state.endorsable with
  | None -> state0
  | Some (old_round, _, _) -> if round > old_round then state0 else state

(** Set locked component of the node state. *)
let set_locked (state : Algorithm.node_state) round block_contents pqc =
  { state with locked = Some (round, block_contents, pqc) }

(** Add preendorsement to the node state. *)
let handle_preendorsement params private_key (state : Algorithm.node_state)
    (Blockchain.Preendorsement signed as preendorsement) =
  let open Algorithm in
  match state.chain with
  | [] -> ([], state)
  | block :: _ -> (
      let block_contents_hash =
        Hash.make Blockchain.block_contents_encoding block.contents
      in
      let state_with proposal_state = { state with proposal_state } in
      let add_to_acc (Blockchain.Preendorsement ph as p) acc =
        p
        :: List.filter
             (fun (Blockchain.Preendorsement h) ->
               not (Signed.equal Hash.equal h ph))
             acc
      in
      let check_pqc state0 =
        match state0.proposal_state with
        | No_proposal -> ([], state0)
        | Collecting_preendorsements m ->
            if is_qc_complete params m.acc then
              let state1 =
                {
                  state0 with
                  proposal_state =
                    Collecting_endorsements { pqc = m.acc; acc = [] };
                }
              in
              let state2 =
                set_endorsable state1
                  (current_round state1.chain)
                  block.contents m.acc
              in
              let state3 =
                set_locked state2
                  (current_round state2.chain)
                  block.contents m.acc
              in
              prepare_endorse params private_key state3 m.acc
            else ([], state0)
        | Collecting_endorsements _ -> ([], state0)
      in
      match state.proposal_state with
      | No_proposal ->
          let new_proposal_state =
            Collecting_preendorsements { acc = [ preendorsement ] }
          in
          check_pqc (state_with new_proposal_state)
      | Collecting_preendorsements m ->
          if Hash.equal (Signed.get_value signed) block_contents_hash then
            let new_acc = add_to_acc preendorsement m.acc in
            let new_proposal_state =
              Collecting_preendorsements { acc = new_acc }
            in
            check_pqc (state_with new_proposal_state)
          else ([], state)
      | Collecting_endorsements _ -> ([], state))

(** Prepare an effect that sends endorse message, also update the node
   state. *)
let prepare_preendorse params private_key (state : Algorithm.node_state) =
  let open Algorithm in
  match state.chain with
  | [] -> ([], state)
  | block :: _ ->
      let previous_block_hash = block.contents.predecessor_hash in
      let block_contents_hash =
        Hash.make Blockchain.block_contents_encoding block.contents
      in
      let preendorsement =
        Blockchain.Preendorsement
          (Signed.make private_key (Hash.encoding ()) block_contents_hash)
      in
      let unsigned_message : Algorithm.unsigned_message =
        {
          level = block.contents.level;
          round = current_round state.chain;
          previous_block_hash;
          payload = Preendorse preendorsement;
        }
      in
      let signed_message =
        Signed.make private_key Algorithm.unsigned_message_encoding
          unsigned_message
      in
      let state0 =
        match block.previously_proposed with
        | None -> state
        | Some (round, pqc) -> set_endorsable state round block.contents pqc
      in
      let effects, state1 =
        handle_preendorsement params private_key state0 preendorsement
      in
      (Effect.Send_message signed_message :: effects, state1)

(** Prepare an effect that sends preendorsements message. *)
let prepare_preendorsements _params private_key (state : Algorithm.node_state)
    pqc =
  let open Algorithm in
  match state.chain with
  | [] -> ([], state)
  | block :: _ ->
      let previous_block_hash = block.contents.predecessor_hash in
      let unsigned_message : Algorithm.unsigned_message =
        {
          level = block.contents.level;
          round = current_round state.chain;
          previous_block_hash;
          payload = Preendorsements (block, pqc);
        }
      in
      let signed_message =
        Signed.make private_key Algorithm.unsigned_message_encoding
          unsigned_message
      in
      ([ Effect.Send_message signed_message ], state)

(** Prepare an effect that sends the head of current chain as a new proposal. *)
let prepare_proposal (params : Algorithm.params) private_key
    (state : Algorithm.node_state) =
  let open Algorithm in
  let proposed_level = decided_level state.chain + 1 in
  let previous_block_hash = last_decided_block_hash state.chain in
  let unsigned_message : Algorithm.unsigned_message =
    {
      level = proposed_level;
      round = current_round state.chain;
      previous_block_hash;
      payload = Propose state.chain;
    }
  in
  let signed_message =
    Signed.make private_key Algorithm.unsigned_message_encoding unsigned_message
  in
  let proposal_state = Collecting_preendorsements { acc = [] } in
  let state0 = { state with proposal_state } in
  let extra_effects, state1 = prepare_preendorse params private_key state0 in
  (Effect.Send_message signed_message :: extra_effects, state1)

(** Update the given node state by incrementing the round number. Skip for
   empty chain. *)
let increment_round params time (state : Algorithm.node_state) =
  let open Algorithm in
  let state0 =
    match state.chain with
    | [] -> state
    | old_block :: rest ->
        let new_block : Blockchain.block =
          match state.endorsable with
          | None ->
              let transactions = [ Transaction.originate () ] in
              {
                contents =
                  {
                    transactions;
                    level = old_block.contents.level;
                    predecessor_hash = old_block.contents.predecessor_hash;
                  };
                round = old_block.round + 1;
                timestamp = time;
                predecessor_eqc = old_block.predecessor_eqc;
                previously_proposed = None;
              }
          | Some (round, block_contents, pqc) ->
              {
                contents = block_contents;
                round = old_block.round + 1;
                timestamp = time;
                predecessor_eqc = old_block.predecessor_eqc;
                previously_proposed = Some (round, pqc);
              }
        in
        { state with chain = new_block :: rest }
  in
  let proposal_state = No_proposal in
  let next_wake = synchronize params time (current_round state0.chain) in
  ({ state0 with proposal_state }, next_wake)

(** Attempt to decide head and update the state accordingly. If it is not
   possible to decide the head yet, increment round. *)
let attempt_to_decide_head params time (state : Algorithm.node_state) =
  let open Algorithm in
  match state.chain with
  | [] ->
      (* Proposing the first block in the blockchain. *)
      let contents : Blockchain.block_contents =
        {
          transactions = [ Transaction.originate () ];
          level = 1;
          predecessor_hash = None;
        }
      in
      let block : Blockchain.block =
        {
          contents;
          (* The blockchain can remain empty for more than one round. In
             that case, we should use time to determine the round number. *)
          round = int_of_float (Time.to_float time /. params.round0_duration);
          timestamp = time;
          predecessor_eqc = [];
          previously_proposed = None;
        }
      in
      let chain = [ block ] in
      let next_wake = synchronize params time 0 in
      ( {
          state with
          chain;
          proposal_state = No_proposal;
          endorsable = None;
          locked = None;
        },
        next_wake )
  | _ -> (
      match state.proposal_state with
      | No_proposal | Collecting_preendorsements _ ->
          increment_round params time state
      | Collecting_endorsements m ->
          if is_qc_complete params m.acc then
            let predecessor_hash =
              match state.chain with
              | [] -> failwith "empty chain"
              | block :: _ -> Hash.make Blockchain.block_encoding block
            in
            let contents : Blockchain.block_contents =
              {
                transactions = [ Transaction.originate () ];
                level = head_level state.chain + 1;
                predecessor_hash = Some predecessor_hash;
              }
            in
            let block : Blockchain.block =
              {
                contents;
                round = 0;
                timestamp = time;
                predecessor_eqc = m.acc;
                previously_proposed = None;
              }
            in
            let chain = block :: state.chain in
            let next_wake = synchronize params time 0 in
            ( {
                state with
                chain;
                proposal_state = No_proposal;
                endorsable = None;
                locked = None;
              },
              next_wake )
          else increment_round params time state)

(** Return [true] if the given chain is valid. *)
let valid_chain params (chain : Blockchain.t) =
  let rec go eqc_opt hash_opt (blocks : Blockchain.t) =
    match blocks with
    | [] -> true
    | block :: rest ->
        let is_eqc_correct =
          match eqc_opt with
          | None -> true
          | Some eqc -> is_eqc_valid params block.contents eqc
        in
        let is_hash_correct =
          match hash_opt with
          | None ->
              (* [block] is the head, so there is no block that includes its
                 hash yet, nothing to check. *)
              true
          | Some None ->
              (* [predecessor_hash] is [None], this is only acceptible for
                 the very first block. *)
              Int.equal block.contents.level 1
          | Some (Some hash) ->
              (* Otherwise the [predecessor_hash] from the newer block must
                 match the hash of the previous block. *)
              Hash.equal hash (Hash.make Blockchain.block_encoding block)
        in
        let is_rest_correct =
          go (Some block.predecessor_eqc) (Some block.contents.predecessor_hash)
            rest
        in
        is_eqc_correct && is_hash_correct && is_rest_correct
  in
  go None None chain

(** [better_chain candidate state] returns [true] if the chain [candidate]
   is better than or as good as the chain in the node state [state]. *)
let better_chain (candidate : Blockchain.t) (state : Algorithm.node_state) =
  let candidate_level = head_level candidate in
  let current_level = head_level state.chain in
  if candidate_level == current_level then
    match (candidate, state.chain) with
    | candidate_head :: candidate_rest, _ :: node_rest -> (
        let node_predecessor_round_is_higher =
          match (candidate_rest, node_rest) with
          | candidate_predecessor :: _, node_predecessor :: _ ->
              node_predecessor.round >= candidate_predecessor.round
          | [], [] -> true
          | _ -> false
        in
        match (candidate_head.previously_proposed, state.endorsable) with
        | None, None -> node_predecessor_round_is_higher
        | ( Some (candidate_endorsable_round, _),
            Some (node_endorsable_round, _, _) ) ->
            if candidate_endorsable_round == node_endorsable_round then
              node_predecessor_round_is_higher
            else candidate_endorsable_round > node_endorsable_round
        | Some _, None -> true
        | None, Some _ -> false)
    | _ -> false
  else candidate_level > current_level

(** Logic of a correct Tenderbake participant. *)
let good_node params time event private_key state =
  let open Algorithm in
  match event with
  | Event.Message_received (Signed.T (message, message_signature) as signed) ->
      if Signed.is_valid unsigned_message_encoding signed then
        match message.payload with
        | Propose candidate_chain ->
            let is_proposer_valid =
              is_proposer params.total_nodes
                (Signature.signer message_signature)
                message.level message.round
            in
            let previously_proposed_pqc_is_correct =
              match candidate_chain with
              | [] -> true
              | block :: _ -> (
                  match block.previously_proposed with
                  | None -> true
                  | Some (_, pqc) -> is_pqc_valid params block.contents pqc)
            in
            if
              is_proposer_valid && previously_proposed_pqc_is_correct
              && valid_chain params candidate_chain
              && better_chain candidate_chain state
            then
              (* The received chain is better than ours. For all we know
                 we might be quite out of sync with incorrect round number
                 set, etc. Here we try to update things and set them
                 right. *)
              let candidate_timestamp =
                match candidate_chain with
                | [] ->
                    (* This branch is impossible because only a non-empty
                       candidate chain can be better than our current
                       chain. *)
                    assert false
                | block :: _ -> block.timestamp
              in
              let next_wake_time =
                synchronize params candidate_timestamp
                  (current_round candidate_chain)
              in
              let effects0 = [ Effect.Set_wake_up_time next_wake_time ] in
              let chain_has_grown =
                head_level candidate_chain > head_level state.chain
              in
              let state0 =
                {
                  state with
                  chain = candidate_chain;
                  proposal_state = No_proposal;
                  endorsable =
                    (if chain_has_grown then None else state.endorsable);
                  locked = (if chain_has_grown then None else state.locked);
                }
              in
              match state0.chain with
              | [] -> ([], state0)
              | proposed_block :: _ ->
                  let proposed_block_contents_hash =
                    Hash.make Blockchain.block_contents_encoding
                      proposed_block.contents
                  in
                  let effects1, state1 =
                    match state0.locked with
                    | None -> prepare_preendorse params private_key state0
                    | Some (locked_round, locked_block_contents, pqc) -> (
                        let locked_block_contents_hash =
                          Hash.make Blockchain.block_contents_encoding
                            locked_block_contents
                        in
                        if
                          Hash.equal locked_block_contents_hash
                            proposed_block_contents_hash
                        then prepare_preendorse params private_key state0
                        else
                          match proposed_block.previously_proposed with
                          | None ->
                              prepare_preendorsements params private_key state0
                                pqc
                          | Some (endorsable_round, _) ->
                              if locked_round < endorsable_round then
                                prepare_preendorse params private_key state0
                              else
                                prepare_preendorsements params private_key
                                  state0 pqc)
                  in
                  (effects0 @ effects1, state1)
            else ([], state)
        | Preendorse (Blockchain.Preendorsement p as preendorsement) -> (
            let is_preendorser_valid =
              is_committee_member params.total_nodes
                (Signature.signer (Signed.get_signature p))
                message.level
            in
            match state.proposal_state with
            | Collecting_preendorsements _ ->
                let message_valid = check_message_lrh message state in
                if is_preendorser_valid && message_valid then
                  handle_preendorsement params private_key state preendorsement
                else ([], state)
            | _ -> ([], state))
        | Endorse ((Blockchain.Endorsement e as endorsement), pqc) -> (
            let is_endorser_valid =
              is_committee_member params.total_nodes
                (Signature.signer (Signed.get_signature e))
                message.level
            in
            match (state.proposal_state, state.chain) with
            | Collecting_endorsements _, block :: _ ->
                let message_valid = check_message_lrh message state in
                let is_pqc_valid = is_pqc_valid params block.contents pqc in
                if is_endorser_valid && message_valid && is_pqc_valid then
                  ([], handle_endorsement params state endorsement)
                else ([], state)
            | Collecting_preendorsements _, block :: _ ->
                let message_valid = check_message_lrh message state in
                let is_pqc_valid = is_pqc_valid params block.contents pqc in
                if is_endorser_valid && message_valid && is_pqc_valid then
                  (* Optimization: the node received a valid endorsement message while the
                     proposal state is collecting preendorsements. In this
                     case, it  (1) fast forwards as if it had seen a pqc itself and
                     then (2) handles the endorsement as before. Fast forwarding
                     as if it was collecting preendorsements and saw a pqc
                     entails the following: set the proposal state to collecting endorsements,
                     set the current head as endorsable and locked,
                     self-endorse and send an endorsement.
                  *)
                  let state0 =
                    {
                      state with
                      proposal_state = Collecting_endorsements { pqc; acc = [] };
                    }
                  in
                  let state1 =
                    set_endorsable state0
                      (current_round state0.chain)
                      block.contents pqc
                  in
                  let state2 =
                    set_locked state1
                      (current_round state1.chain)
                      block.contents pqc
                  in
                  let effects0, state3 =
                    prepare_endorse params private_key state2 pqc
                  in
                  (effects0, handle_endorsement params state3 endorsement)
                else ([], state)
            | _ -> ([], state))
        | Preendorsements (block, pqc) ->
            let message_valid = check_message_lrh message state in
            let is_pqc_valid = is_pqc_valid params block.contents pqc in
            if is_pqc_valid && message_valid then
              let new_state =
                set_endorsable state message.round block.contents pqc
              in
              ([], new_state)
            else ([], state)
      else ([], state)
  | Event.Wake_up ->
      let state0, next_wake_time0 = attempt_to_decide_head params time state in
      if
        is_proposer params.total_nodes state0.id (head_level state0.chain)
          (current_round state0.chain)
      then
        let effects, state1 = prepare_proposal params private_key state0 in
        let next_wake = Effect.Set_wake_up_time next_wake_time0 in
        (next_wake :: effects, state1)
      else
        let state1, next_wake_time1 = increment_round params time state in
        let next_wake = Effect.Set_wake_up_time next_wake_time1 in
        ([ next_wake ], state1)
