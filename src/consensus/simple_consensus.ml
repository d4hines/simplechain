(* open Node_interface

   module Make (Value : Value.VALUE) : NODE_INTERFACE = struct
     type config = { self : Participant.t; participants : Participant.t list }
     type level = int
     type t = { config : config; latest_commitment : level * Value.t }

     module Side_effect = struct
       type t =
         | Send_to_all of { sender : Participant.t; value : Value.t }
         | Commit of { level : level; value : Value.t }
     end

     (* let self t = t.config.self
        let latest_commitment t = t.latest_commitment

        let commit ~level ~value t =
          ( { t with latest_commitment = (level, value) },
            [ Side_effect.Commit { level; value } ] )

        let init ~config value =
          let t = { config; latest_commitment = (-1, value) } in
          (t, [ Side_effect.Send_to_all { sender = config.self; value } ])

        let receive_message ~sender ~value t =
          let _ = ignore (sender, value, t) in
          (t, []) *)
   end *)
(* let foo = "foo"
   let compose f g x = f x |> g
   let ( >> ) = compose

   type participant = int

   module type CONFIG = sig
     val self : participant
     val participants : participant list
   end

   module Consensus_internal (Config : CONFIG) (Value : Map.OrderedType) = struct
     type round = int

     module MessageCount = Multiset.Make (Value)

     type message = { sender : participant; value : Value.t; round : round }

     module Side_effects = struct
       include Preface.Make.Freer_monad.Over (struct
         type 'a t = Send_phase_1_message : message -> message t
       end)

       let print message = perform (Print message)
       let read = perform Read
     end

     module Messages = struct
       type t = message list

       let make l = l
       let empty = []

       let count x t =
         List.map fst t |> MessageCount.of_list |> MessageCount.count x

       let majority t =
         List.map fst t |> MessageCount.of_list |> MessageCount.majority

       let nth_value n (t : t) = (List.nth t n).value
       let add x t = x :: t
     end

     type locked
     type phase1
     type phase2

     type _ state =
       | Locked : { value : Value.t; round : round } -> locked state
       | Phase1 : {
           value : Value.t;
           round : round;
           phase1_messages : Messages.t;
         }
           -> phase1 state
       | Phase2 : {
           value : Value.t;
           round : round;
           phase1 : phase1 state;
           phase2_messages : Messages.t;
         }
           -> phase2 state

     type ('before, 'after) transition =
       | Start_new_round : message -> (locked, phase1) transition
       | Receive_phase_1 : message -> (phase1, phase1) transition
       | Receive_last_phase_1 : message -> (phase1, phase2) transition
       | Receive_phase_2 : message -> (phase2, phase2) transition
       | Receive_last_phase_2 : message -> (phase2, locked) transition

     let
         (*
            ****************
            note for myself
            ***********message
            maybe I can a GADT that goes straight from lock -> phase1 -> phase2 -> lock
            but use the continuation to specify "receive 5 messages before proceeding"
         *)
         x =
       note_for_myself

     let transition : type a b. a state -> (a, b) transition -> b state =
      fun state transition ->
       match (state, transition) with
       | Locked { value; round }, Start_new_round message ->
           Phase1
             {
               value;
               round;
               phase1_messages = Messages.add message Messages.empty;
             }
       | Phase1 { value; round; phase1_messages }, Receive_phase_1 message ->
           Phase1
             {
               value;
               round;
               phase1_messages = Messages.add message phase1_messages;
             }
       | Phase1 { value; round; phase1_messages }, Receive_last_phase_1 message ->
           Phase2
             {
               value;
               round;
               phase1_messages = Messages.add message phase1_messages;
               phase2_messages = Messages.empty;
             }
       | ( Phase2 { value; round; phase1_messages; phase2_messages },
           Receive_phase_2 message ) ->
           Phase2
             {
               value;
               round;
               phase1_messages;
               phase2_messages = Messages.add message phase2_messages;
             }
       | ( Phase2 { value = _; round = _; phase1_messages = _; phase2_messages = _ },
           Receive_last_phase_2 _message ) ->
           assert false
   end

   (* module Consensus (Value : Map.OrderedType) = struct






        (* let round = 0 in
           let message =
             Side_effects.Send_phase_1 { value; round; sender = Config.self }
           in
           let state = Phase1 { phase1_messages = Messages.empty; round } in
           (state, message) *)

        (* let receive_phase_1 t message =  *)

        (* let receive_phase_1 ({ round; value; phase_1_messages; phase_2_messages } : t)
             (message : message) =
           {
             round;
             value;
             phase_1_messages = Messages.add message phase_1_messages;
             phase_2_messages;
           } *)

        (* let send_phase_2 (state : t) = Messages.majority state.phase_1_messages *)

        (* let receive_phase_2 ({ round; value; phase_1_messages; phase_2_messages } : t)
             (message : message) =
           {
             round;
             value;
             phase_1_messages;
             phase_2_messages = Messages.add message phase_2_messages;
           } *)

        (* let decision { round; phase_2_messages; phase_1_messages } s =
           let majority_phase_1 = Messages.majority phase_1_messages in
           let count_phase_1 = Messages.count majority_phase_1 phase_1_messages in

           let value =
             if count_phase_1 >= s then majority_phase_1
             else Messages.nth_value round phase_2_messages
           in
           {
             round = round + 1;
             value;
             phase_1_messages = Messages.empty;
             phase_2_messages = Messages.empty;
           (* } *) *)

        (* let decision (messages : Messages.t) (k : round) =
             let majority_value = Messages.majority messages in
             let majority_count = Messages.count majority_value messages in
             let participants = Messages.participants messages in
             let s = List.length participants * 4 / 5 in
             if majority_count >= s then assert false

           let run s participants initial_value =
             let count x k = assert false in
             let rec majority_value x k =
               List.map (fun y -> received_value x y k) participants
               |> MessageCount.of_list |> MessageCount.majority
             and decision_value x k =
               if k = 0 then initial_value
               else if count x k >= s then (*  *)
                 majority_value x k
               else majority_value k k
             and received_value _x y k = decision_value y (k - 1) in
             assert false *)
      end *) *)
