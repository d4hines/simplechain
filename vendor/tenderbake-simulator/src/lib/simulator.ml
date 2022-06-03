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

module type Algorithm = sig
  type message

  val message_encoding : message Data_encoding.t

  type node_state
  type params

  val params_encoding : params Data_encoding.t
  val init_node_state : params -> Node.Id.t -> node_state
  val node_state_encoding : node_state Data_encoding.t
end

module Make (A : Algorithm) = struct
  module Event = struct
    type t = Wake_up | Message_received of A.message

    let encoding =
      let open Data_encoding in
      union
        [
          case ~title:"wake_up" (Tag 0)
            (obj1 (req "tag" (constant "wake_up")))
            (function Wake_up -> Some () | _ -> None)
            (function () -> Wake_up);
          case ~title:"message_received" (Tag 1)
            (obj2
               (req "tag" (constant "message_received"))
               (req "message" A.message_encoding))
            (function Message_received m -> Some ((), m) | _ -> None)
            (function (), m -> Message_received m);
        ]
  end

  module Effect = struct
    type t =
      | Set_wake_up_time of Time.t
      | Send_message of A.message
      | Shut_down

    let encoding =
      let open Data_encoding in
      union
        [
          case ~title:"set_wake_up_time" (Tag 0)
            (obj2
               (req "tag" (constant "set_wake_up_time"))
               (req "time" Time.encoding))
            (function Set_wake_up_time t -> Some ((), t) | _ -> None)
            (function (), t -> Set_wake_up_time t);
          case ~title:"send_message" (Tag 1)
            (obj2
               (req "tag" (constant "send_message"))
               (req "message" A.message_encoding))
            (function Send_message m -> Some ((), m) | _ -> None)
            (function (), m -> Send_message m);
          case ~title:"shut_down_at" (Tag 2)
            (obj1 (req "tag" (constant "shut_down")))
            (function Shut_down -> Some () | _ -> None)
            (function () -> Shut_down);
        ]
  end

  type event_handler =
    A.params ->
    Time.t ->
    Event.t ->
    Signature.private_key ->
    A.node_state ->
    Effect.t list * A.node_state

  let with_lifetime lifetime handler params time event private_key node_state =
    let effects, new_state = handler params time event private_key node_state in
    let shutdown_effect =
      if time >= lifetime then [ Effect.Shut_down ] else []
    in
    (shutdown_effect @ effects, new_state)

  type predicate =
    Time.t ->
    int ->
    (Node.Id.t * Time.t option * A.node_state) option array ->
    bool

  module Log = Logging.MakeLog (struct
    type params = A.params

    let params_encoding = A.params_encoding

    type event = Event.t

    let event_encoding = Event.encoding

    type state = A.node_state

    let state_encoding = A.node_state_encoding

    type effect = Effect.t

    let effect_encoding = Effect.encoding
  end)

  (** A map from [string] to ['a] *)
  module LabelMap = Map.Make (struct
    type t = string

    let compare = String.compare
  end)

  (** A min heap of [Time.t * int * int * Node.Id.t * Event.t] 5-tuples
     sorted by time and (if time is equal) by the originating iteration and
     if that is also equal by the effect index. *)
  module EventHeap = Binary_heap.Make (struct
    type t = Time.t * int * int * Node.Id.t * Event.t

    let compare (t, i, ei, _, _) (t', i', ei', _, _) =
      match Time.compare t t' with
      | 0 -> ( match Int.compare i i' with 0 -> Int.compare ei ei' | y -> y)
      | x -> x
  end)

  type system_state = {
    node_pool : (Node.Id.t * Time.t option * A.node_state) option array;
        (** An array [arr] s.t. node with id [i] is at [arr.(to_int i)] *)
    event_heap : EventHeap.t;  (** A min heap of [(Time.t, Node.Id.t, Event)] *)
  }
  (** The state of the transition system. *)

  type system_param = {
    handlers : event_handler LabelMap.t;
        (** A map from string label to handler *)
    iteration : int ref;  (** An increasing counter of iteration *)
    log : Log.t;  (** The log *)
    formatter : Format.formatter option;  (** The formatter *)
    message_delay : Network.Delay.t;
        (** The delay function which models the network *)
    predicates : (string, predicate) Hashtbl.t;
        (** A list of predicates which have held to the current iteration *)
    predicate_fails : (string, int option) Hashtbl.t;
    params : A.params;  (** Algorithm parameters *)
    seed : int;  (** Seed to initialize [Random] for the [delay] function *)
  }
  [@@warning "-69"]
  (** Parameters that determine how the simulator executes. *)

  let set_wake_up_time system_state node_id wake_up_time =
    let node_id_int = Node.Id.to_int node_id in
    match system_state.node_pool.(node_id_int) with
    | None -> ()
    | Some (old_node_id, _, old_state) ->
        system_state.node_pool.(node_id_int) <-
          Some (old_node_id, wake_up_time, old_state)

  (** Run a single effect at a certain time. *)
  let run_effect system_params system_state node_id time effect_index effect =
    let open Effect in
    let node_id_int = Node.Id.to_int node_id in
    let iteration = !(system_params.iteration) in
    match effect with
    | Shut_down -> system_state.node_pool.(node_id_int) <- None
    | Set_wake_up_time t -> set_wake_up_time system_state node_id (Some t)
    | Send_message message ->
        let for_reciever opt_recipient =
          match opt_recipient with
          | None -> ()
          | Some (recip_node_id, _, _) -> (
              match Node.Id.compare recip_node_id node_id with
              | 0 -> ()
              | _ -> (
                  let message_event = Event.Message_received message in
                  let message_delay =
                    system_params.message_delay ~now:time ~iteration
                      ~effect_index ~sender:node_id ~receiver:recip_node_id
                  in
                  match message_delay with
                  | None -> ()
                  | Some delta ->
                      let arrival_time = Time.add time delta in
                      let new_event =
                        ( arrival_time,
                          iteration,
                          effect_index,
                          recip_node_id,
                          message_event )
                      in
                      EventHeap.add system_state.event_heap new_event))
        in
        Array.iter for_reciever system_state.node_pool

  (** Step one iteration and log the result.
   A step is an update to the [system_params] and [system_state].*)
  let step_iteration ~system_params ~system_state (time, _, _, node_id, event) =
    let node_id_int = Node.Id.to_int node_id in
    match system_state.node_pool.(node_id_int) with
    | None -> () (* Node was shut down *)
    | Some (_, next_wake, node_state) ->
        (* 1. Get event_handler parameters and run it. *)
        let private_key = Signature.internal_node_private_key node_id in
        let node_label = Node.Id.get_label node_id in
        let handler = LabelMap.find node_label system_params.handlers in
        let params = system_params.params in
        let effects, new_state =
          handler params time event private_key node_state
        in
        (* 2. Update state and run effects *)
        system_state.node_pool.(node_id_int) <-
          Some (node_id, next_wake, new_state);
        List.iteri (run_effect system_params system_state node_id time) effects;
        (* 3. Check predicates, update ones which hold *)
        let iteration = !(system_params.iteration) in
        let failed_predicates =
          let accum name pred xs =
            match pred time iteration system_state.node_pool with
            | true -> xs
            | false -> name :: xs
          in
          Hashtbl.fold accum system_params.predicates []
        in
        let mark_failed name =
          Hashtbl.replace system_params.predicate_fails name (Some iteration)
        in
        List.iter (Hashtbl.remove system_params.predicates) failed_predicates;
        List.iter mark_failed failed_predicates;
        (* 4. Log what happened *)
        let formatter = system_params.formatter in
        let log = system_params.log in
        let init_state = node_state in
        Log.log ~formatter ~time ~iteration ~event ~init_state ~new_state
          ~effects log;
        (* 5. Increment the iteration counter *)
        system_params.iteration := !(system_params.iteration) + 1

  (** Given [nodes: int * string * event_handler list]
     output the initial state of the system of type [system_state] *)
  let initial_state ~params ~nodes : system_state =
    let node_count = List.fold_left (fun n (i, _, _) -> n + i) 0 nodes in
    let node_pool = Array.make node_count None in
    let iteri_range arr ~start_ix ~end_ix ~f : unit =
      for i = start_ix to end_ix do
        arr.(i) <- f i arr.(i)
      done
    in
    (* Write a group of nodes in the node_pool, taking and returning an
       offset for * where to start writing. To be used in a [fold_left]. *)
    let write_group offset (count, label, _) =
      let write_cell ix _ =
        let id = Node.Id.make label ix in
        Some (id, Some Time.init, A.init_node_state params id)
      in
      let start_ix = offset in
      let end_ix = offset + count - 1 in
      iteri_range node_pool ~start_ix ~end_ix ~f:write_cell;
      offset + count
    in
    let event_heap =
      let dummy_id = Node.Id.make "" (-1) in
      let dummy = (Time.init, 0, 0, dummy_id, Event.Wake_up) in
      EventHeap.create ~dummy 0
    in
    (* Write all nodes with initial states *)
    ignore (List.fold_left write_group 0 nodes);
    { node_pool; event_heap }

  (** Determine the parameters of the system *)
  let initial_param ~formatter ~message_delay ~seed ~predicates ~params ~nodes =
    let log = Log.create params in
    let handlers =
      let add_handler lmap (_, label, handler) =
        LabelMap.add label handler lmap
      in
      List.fold_left add_handler LabelMap.empty nodes
    in
    let iter_ref = ref 0 in
    let num_predicates = List.length predicates in
    let all_predicates = Hashtbl.create num_predicates in
    let pred_names = List.map fst predicates in
    let predicate_fails = Hashtbl.create num_predicates in
    let no_fail name = Hashtbl.add predicate_fails name None in
    let add_predicate (name, pred) = Hashtbl.add all_predicates name pred in
    List.iter no_fail pred_names;
    List.iter add_predicate predicates;
    let system_param =
      {
        handlers;
        iteration = iter_ref;
        log;
        formatter;
        message_delay;
        params;
        seed;
        predicates = all_predicates;
        predicate_fails;
      }
    in
    Random.init seed;
    system_param

  (** Determine the initial [system_param] and [system_state] *)
  let initial_setup ~formatter ~message_delay ~seed ~predicates ~params ~nodes :
      system_param * system_state =
    let system_param =
      initial_param ~formatter ~message_delay ~seed ~predicates ~params ~nodes
    in
    let system_state = initial_state ~params ~nodes in
    (system_param, system_state)

  (** Run a simulation *)
  let run_simulation ?formatter ?(message_delay = Network.Delay.default)
      ?(seed = 0) ?(predicates = []) ~params ~iterations ~nodes () =
    Transaction.reset ();
    let system_params, system_state =
      initial_setup ~formatter ~message_delay ~seed ~predicates ~params ~nodes
    in
    let pop_valid_event sys_state =
      let no_more_iterations = !(system_params.iteration) = iterations in
      let next_event_time =
        if EventHeap.is_empty sys_state.event_heap then None
        else
          let time, _, _, _, _ = EventHeap.minimum sys_state.event_heap in
          Some time
      in
      let find_min_wake acc = function
        | None -> acc
        | Some (_, None, _) -> acc
        | Some (node_id, Some next_wake, _) -> (
            match acc with
            | None -> Some (node_id, next_wake)
            | Some (_, old_wake) ->
                if old_wake > next_wake then Some (node_id, next_wake) else acc)
      in
      let min_wake_up =
        Array.fold_left find_min_wake None sys_state.node_pool
      in
      let do_wake_up_for node_id time =
        set_wake_up_time sys_state node_id None;
        (time, 0, 0, node_id, Event.Wake_up)
      in
      match (no_more_iterations, next_event_time, min_wake_up) with
      | true, _, _ -> None
      | false, None, None -> None
      | false, Some _, None -> Some (EventHeap.pop_minimum sys_state.event_heap)
      | false, None, Some (node_id, wake_up_time) ->
          Some (do_wake_up_for node_id wake_up_time)
      | false, Some event_time, Some (node_id, wake_up_time) ->
          Some
            (if event_time < wake_up_time then
             EventHeap.pop_minimum sys_state.event_heap
            else do_wake_up_for node_id wake_up_time)
    in
    let rec loop () =
      match pop_valid_event system_state with
      | None -> ()
      | Some scheduled_event ->
          step_iteration ~system_params ~system_state scheduled_event;
          loop ()
    in
    loop ();
    let failed_predicates =
      Hashtbl.fold (fun k v xs -> (k, v) :: xs) system_params.predicate_fails []
    in
    (system_params.log, system_state.node_pool, failed_predicates)
end
