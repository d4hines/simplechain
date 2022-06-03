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
module Test = Helpers.Make (Algorithm)

let stress_test_config : Test.config =
  let total_nodes = 10 in
  {
    test_name = "tenderbake-stress-test";
    params = default_params total_nodes;
    iterations = 3000;
    nodes = [ (total_nodes, "good node", good_node) ];
    message_delay = Some (Network.Delay.linear ~min:0.1 ~max:0.9);
    predicates =
      [
        ("safety", Predicates.safety);
        ("liveness", Predicates.liveness);
        ("unique_txns", Test.unique_txn Predicates.get_txns);
      ];
    seeds = List.init 100 (fun x -> x);
    final_state_check = Test.no_check;
    log_check = Test.no_check;
    debug = false;
  }

(** Return [true] if the fields of the given block have expected values. *)
let check_block ~level ~round ~transaction ~pp_round ~(block : Blockchain.block)
    =
  Int.equal block.contents.level level
  && Int.equal block.round round
  && (match block.contents.transactions with
     | [ n ] -> Int.equal (Transaction.to_int n) transaction
     | _ -> false)
  &&
  match (block.previously_proposed, pp_round) with
  | Some (r0, _), Some r1 -> Int.equal r0 r1
  | None, None -> true
  | _ -> false

(*

Scenario T1

1. Node A proposes at the round 0.
2. Both node A and node B preendorse.
3. Node A stops.
4. Node B endorses in the round 0 and locks. No decision is taken at the
   round 0 because A did not endorse.
5. We check that in round 1, B proposes the same value as A proposed in
   the round 0, not a new proposal.
*)

let final_log_check_t1 (log : Log.t) =
  let entries = Utils.Queue.to_array log.entries in
  let first_proposal_good =
    match entries.(1).effects with
    | [ _; _; Send_message m; _ ] -> (
        match (Signed.get_value m).payload with
        | Propose [ block ] ->
            check_block ~level:1 ~round:0 ~transaction:1 ~pp_round:None ~block
        | _ -> false)
    | _ -> false
  in
  let second_proposal_good =
    match entries.(4).effects with
    | [ _; Send_message m; _ ] -> (
        match (Signed.get_value m).payload with
        | Propose [ block ] ->
            check_block ~level:1 ~round:1 ~transaction:1 ~pp_round:(Some 0)
              ~block
        | _ -> false)
    | _ -> false
  in
  first_proposal_good && second_proposal_good

let scenario_t1_config : Test.config =
  let total_nodes = 2 in
  {
    test_name = "tenderbake-t1";
    params = { (default_params total_nodes) with quorum_size = 2 };
    iterations = 5;
    nodes =
      [
        (1, "B", Tenderbake.good_node);
        (1, "A", Tenderbake.with_lifetime Time.init Tenderbake.good_node);
      ];
    message_delay = Some (Network.Delay.const 0.2);
    predicates = [];
    seeds = [ 0 ];
    final_state_check = Test.no_check;
    log_check = final_log_check_t1;
    debug = false;
  }

(*

Scenario T2

1. A is the proposer at the round 0, however it is dead.
2. Nothing happens till the round 1, where B is the proposer. B proposes.

*)

let final_log_check_t2 (log : Log.t) =
  let entries = Utils.Queue.to_array log.entries in
  match entries.(2).effects with
  | [ _; Send_message m; _ ] -> (
      match (Signed.get_value m).payload with
      | Propose (block :: _) ->
          check_block ~level:1 ~round:1 ~transaction:1 ~pp_round:None ~block
      | _ -> false)
  | _ -> false

let shutdown_immediately _params _time _event _private_key state =
  ([ Effect.Shut_down ], state)

let scenario_t2_config : Test.config =
  let total_nodes = 2 in
  {
    test_name = "tenderbake-t2";
    params = { (default_params total_nodes) with quorum_size = 2 };
    iterations = 3;
    nodes = [ (1, "B", Tenderbake.good_node); (1, "A", shutdown_immediately) ];
    message_delay = Some (Network.Delay.const 0.2);
    predicates = [];
    seeds = [ 0 ];
    final_state_check = Test.no_check;
    log_check = final_log_check_t2;
    debug = false;
  }

(*

Scenario T3

1. There are four nodes: A, B, C, and D.
2. A is the proposer at the round 0. It sends the proposal.
3. Due to how the messages propagate, only C sees 3 preendorsements. It
   endorses and locks. Other nodes all see fewer than 3 preendorsements.
4. B proposes at the round 1. Its message reach 3 nodes, including C.
5. C does not preendorse because it is locked.
6. No decision is taken at the round 1.
7. C proposes at the round 2. There are no more problems with propagation of
   messages, so a decision is reached.
*)

let t3_delay_function ~now:_ ~iteration ~effect_index:_ ~sender ~receiver =
  let d = Some (Time.from_float 0.2) in
  match (iteration, Node.Id.get_label sender, Node.Id.get_label receiver) with
  | 1, "A", "C" -> d
  | 1, "A", "D" -> d
  | 4, "D", "C" -> d
  | 11, "B", "A" -> d
  | 11, "B", "C" -> d
  | _ -> if iteration >= 16 then d else None

let final_log_check_t3 (log : Log.t) =
  let entries = Utils.Queue.to_array log.entries in
  let first_proposal_good =
    match entries.(1).effects with
    | [ _; Send_message m; _ ] -> (
        match (Signed.get_value m).payload with
        | Propose [ block ] ->
            check_block ~level:1 ~round:0 ~transaction:1 ~pp_round:None ~block
        | _ -> false)
    | _ -> false
  in
  let reproposal_good =
    match entries.(20).effects with
    | [ _; Send_message m; _ ] -> (
        match (Signed.get_value m).payload with
        | Propose [ block ] ->
            check_block ~level:1 ~round:2 ~transaction:1 ~pp_round:(Some 0)
              ~block
        | _ -> false)
    | _ -> false
  in
  first_proposal_good && reproposal_good

let scenario_t3_config : Test.config =
  let total_nodes = 4 in
  {
    test_name = "tenderbake-t3";
    params = default_params total_nodes;
    iterations = 21;
    nodes =
      [
        (1, "D", Tenderbake.good_node);
        (1, "A", Tenderbake.good_node);
        (1, "B", Tenderbake.good_node);
        (1, "C", Tenderbake.good_node);
      ];
    message_delay = Some t3_delay_function;
    predicates = [];
    seeds = [ 0 ];
    final_state_check = Test.no_check;
    log_check = final_log_check_t3;
    debug = false;
  }

(*

Scenario T4

1. C is the proposer for level 1, round 0.
2. A, B, C communicate normally and decide on level 1.
3. A proposes for the level 2, round 0.
4. A's endorsement doesn't reach B and C. B's endorsement doesn't reach C
   but reaches A. A observes EQC, however it doesn't go to the next level
   immediately because it is not its time to propose yet.
5. B is now the proposer, at level 2, round 1. No messages reach A, however
   B and C exchange messages and decide.
6. C is now the proposer, it proposes at level 3, round 0.
7. In the meantime, A is still at the level 2. It passed from round 0 to
   round 1 and then to 2. Finally, the proposal of B reaches it and it
   switches to B's and C's branch where level 2 is was decided at the round 1.
*)

let t4_delay_function ~now ~iteration ~effect_index:_ ~sender ~receiver =
  let d = Some (Time.from_float 0.2) in
  let s3 = Time.from_float 3.0 in
  let s6 = Time.from_float 6.0 in
  let s12 = Time.from_float 12.0 in
  match (iteration, Node.Id.get_label sender, Node.Id.get_label receiver) with
  | 22, "A", _ ->
      (* We prevent A's endorsement from reaching B and C. *)
      None
  | _, _, "C" ->
      (* We prevent A's and B's endorsements from reaching C. *)
      if now >= s3 && now < s6 then None else d
  | _, _, "A" ->
      (* A is disconnected from 6th to 12th second. *)
      if now >= s6 && now < s12 then None else d
  | _ -> d

let final_log_check_t4 (log : Log.t) =
  let entries = Utils.Queue.to_array log.entries in
  let a_switches_to_round_2 =
    match entries.(33).new_state.chain with
    | [ level_2; level_1 ] ->
        check_block ~level:2 ~round:2 ~transaction:5 ~pp_round:(Some 0)
          ~block:level_2
        && check_block ~level:1 ~round:0 ~transaction:1 ~pp_round:None
             ~block:level_1
    | _ -> false
  in
  let a_switches_to_b_chain =
    match entries.(35).new_state.chain with
    | [ level_3; level_2; level_1 ] ->
        check_block ~level:3 ~round:0 ~transaction:7 ~pp_round:None
          ~block:level_3
        && check_block ~level:2 ~round:1 ~transaction:5 ~pp_round:(Some 0)
             ~block:level_2
        && check_block ~level:1 ~round:0 ~transaction:1 ~pp_round:None
             ~block:level_1
    | _ -> false
  in
  a_switches_to_round_2 && a_switches_to_b_chain

let scenario_t4_config : Test.config =
  let total_nodes = 3 in
  {
    test_name = "tenderbake-t4";
    params = { (default_params total_nodes) with quorum_size = 2 };
    iterations = 38;
    nodes =
      [
        (1, "B", Tenderbake.good_node);
        (1, "C", Tenderbake.good_node);
        (1, "A", Tenderbake.good_node);
      ];
    message_delay = Some t4_delay_function;
    predicates = [];
    seeds = [ 0 ];
    final_state_check = Test.no_check;
    log_check = final_log_check_t4;
    debug = false;
  }

let test_cases =
  [
    Test.case stress_test_config;
    Test.case scenario_t1_config;
    Test.case scenario_t2_config;
    Test.case scenario_t3_config;
    Test.case scenario_t4_config;
  ]
