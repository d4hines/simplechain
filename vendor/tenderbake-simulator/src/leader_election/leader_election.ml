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

(**

To write a consensus algorithm, we need to

1. Make an [Algorithm] struct with the signature defined in [Tenderbatter.Simulator]
2. Call [include Simulator.Make (Algorithm)]
3. Write an event handler and any auxiliary things like predicates or network delay
   functions

*)

module Algorithm = struct
  type message = Node.Id.t

  (* The message we send it just a node id, defined in [Node.Id]. *)

  let message_encoding = Node.Id.encoding

  (* For each of our types, we need a json encoding for logging and so on.
     See https://gitlab.com/nomadic-labs/data-encoding for the documentation
     on how to write these encodings. *)

  type node_state =
    | Alive of (Node.Id.t * Node.Id.t list)
    | Decided of Node.Id.t

  (*
    A node is either alive or decided.
    - If it is alive, it holds a pair of its own node id and
      a list of ids it has seen.
    - If it is decided, it just holds the id of the leader.
  *)

  let init_node_state _ i = Alive (i, [ i ])

  (* A node is initially alive having seen its own id. *)

  let node_state_encoding =
    let open Data_encoding in
    let alive_encoding = tup2 Node.Id.encoding (list Node.Id.encoding) in
    let decided_encoding = Node.Id.encoding in
    union
      [
        case ~title:"Alive" Json_only alive_encoding
          (function Alive a -> Some a | _ -> None)
          (fun a -> Alive a);
        case ~title:"Decided" Json_only decided_encoding
          (function Decided a -> Some a | _ -> None)
          (fun a -> Decided a);
      ]

  type params = { num_nodes : int }

  (* The [params] type is given to the simulator and passed as an argument
     to the event handler. It represents the parameters of the algorithm itself. *)

  let params_encoding =
    let open Data_encoding in
    conv
      (fun x -> x.num_nodes)
      (fun num_nodes -> { num_nodes })
      (obj1 (req "num_nodes" int31))
end

include Simulator.Make (Algorithm)

(* This call above defines the run_simulation function, the type
   of the event handler and predicates, among other things needed to write
   and run a distributed algorithm.

   For instance, the types needed to pattern match or create effects and events
   are in the included [Event] and [Effect] modules.
*)

(* Now we write an event handler, assuming that each node is given a
   "wake up" event at time 0 and is in the initial state determined by
   [Algorithm.init_node_state]. *)

module A = Algorithm

let node_handler ({ num_nodes } : A.params) (_time : Time.t) (event : Event.t)
    (_private_key : Signature.private_key) (state : A.node_state) :
    Effect.t list * A.node_state =
  let open Algorithm in
  (* The handler is fairly simple. If we are decided, we ignore messages.
     If we are alive, we match on the event.
     Note that the return type is
     the pair of effects and the next state. *)
  match state with
  | Decided _ -> ([], state)
  | Alive (node_id, seen_ids) -> (
      match event with
      | Event.Wake_up ->
          (* If we are given a "wake up", we broadcast the node's id.
             Because in each returned branch, we never create another "wake up" effect,
             we can reason that there is only one "wake up", the one given by the
             simulator at time 0. Hence, each node broadcasts its id only once. *)
          let broadcast_id = Effect.Send_message node_id in
          (* To create an effect, we use the constructors for [Effect.t] *)
          ([ broadcast_id ], state)
      | Event.Message_received some_id -> (
          (* If we get some id, we can assume it's unique since each node only broadcasts
             its id once and messages are delivered exactly once with (unless specified
             otherwise) some max delay. *)
          let seen_ids = some_id :: seen_ids in
          match List.length seen_ids = num_nodes with
          | false ->
              ([], Alive (node_id, seen_ids))
              (* If we haven't seen all ids, we just stay in the alive state
                 accumulating ids as they come in. *)
          | true ->
              (* If we have seen all ids, we get the maximum with a fold and
                 change the state to it. *)
              let max_id i j =
                match Node.Id.to_int i <= Node.Id.to_int j with
                | true -> j
                | false -> i
              in
              let maximum = List.fold_left max_id node_id seen_ids in
              ([], Decided maximum)))

(** Predicate to check same value is decided *)
let same_decision_pred _ _ arr =
  (* Using a fold, accumulate decided ids *)
  let accum_decideds xs opt_state =
    match opt_state with
    | None -> xs
    | Some (_, _, state) -> (
        match state with
        | Algorithm.Alive _ -> xs
        | Algorithm.Decided x -> x :: xs)
  in
  let decideds = Array.fold_left accum_decideds [] arr in
  (* Match on the decided ids and if there are some, check
     they are all the same *)
  match decideds with
  | [] -> true
  | x :: xs -> List.fold_left (fun b d -> b && d = x) true xs

(** A simple run of the algorithm *)
let run_leader_election () =
  let log, _, failed_predicates =
    run_simulation
      ~predicates:[ ("same decision", same_decision_pred) ]
      ~formatter:Format.std_formatter ~params:{ num_nodes = 20 }
      ~iterations:2000
      ~nodes:[ (20, "good node", node_handler) ]
      ()
  in
  Log.save_to_file log "log.json";
  match failed_predicates with
  | [ (_, None) ] -> Stdlib.print_endline "Same value decided!"
  | [ (_, Some _) ] -> Stdlib.print_endline "Fail! Different values decided."
  | _ -> assert false
