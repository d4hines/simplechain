open Helpers
open Tenderbatter

type consensus_params = {
  n : int;
  f : int;
  delta : float;
}
(*
   let consensus_params_encoding =
     let open Data_encoding in
     conv
       (fun { n; f; delta } -> (Int64.of_int n, Int64.of_int f, delta))
       (fun (n, f, delta) -> { n = Int64.to_int n; f = Int64.to_int f; delta })
     @@ obj3 (req "n" int64) (req "f" int64) (req "delta" float)

   module Convincing_blocks : sig
     type t

     val encoding : t Data_encoding.t
     val empty : t

     val add_block :
       params:consensus_params ->
       current_round:int ->
       block_and_signatures:Block_and_signatures.t ->
       t ->
       t * bool

     val get_convincing_block : t -> Block.t option
   end = struct
     module Block_set = Set.Make (Block)

     type t = Block_set.t

     let encoding =
       let open Data_encoding in
       conv Block_set.elements Block_set.of_list (list Block.encoding)

     let empty = Block_set.empty

     let is_convincing ~params ~current_round
         Block_and_signatures.{ block; signatures } =
       let expected_block_producer = Int64.to_int block.level mod params.n in
       (* by convention, ORDER MATTERS for the signatures *)
       let first_signature =
         signatures |> List.rev |> List.hd |> Signed.get_signature
       in
       let actual_block_producer =
         Signature.signer first_signature |> Node.Id.to_int
       in
       actual_block_producer = expected_block_producer
       && Block_and_signatures.is_valid { block; signatures }
       && List.length signatures >= current_round

     let add_block ~params ~current_round
         ~block_and_signatures:Block_and_signatures.{ block; signatures } t =
       if
         is_convincing ~params ~current_round { block; signatures }
         && (not @@ Block_set.mem block t)
       then (Block_set.add block t, true)
       else (t, false)

     let get_convincing_block t =
       if Block_set.cardinal t = 1 then Some (Block_set.choose t) else None
   end

   module Singleshot_consensus = struct
     module Algorithm : Tenderbatter.Simulator.Algorithm = struct
       type message = Block_and_signatures.t

       let message_encoding = Block_and_signatures.encoding

       type node_state = {
         self : Tenderbatter.Node.Id.t;
         round : int;
         convincing_blocks : Convincing_blocks.t;
       }

       let node_state_encoding =
         let open Data_encoding in
         conv
           (fun { self; round; convincing_blocks } ->
             (self, Int64.of_int round, convincing_blocks))
           (fun (self, round, convincing_blocks) ->
             { self; round = Int64.to_int round; convincing_blocks })
         @@ obj3
              (req "self" Tenderbatter.Node.Id.encoding)
              (req "round" int64)
              (req "convincing_blocks" Convincing_blocks.encoding)

       type params = consensus_params

       let params_encoding = consensus_params_encoding

       let init_node_state _params self =
         {
           self;
           (* 1-indexed so we can say that we terminate on round f + 1 *)
           round = 1;
           convincing_blocks = Convincing_blocks.empty;
         }
     end

     include Tenderbatter.Simulator.Make (Algorithm)
   end

   module Algorithm = struct
     type message = Block_and_signatures.t

     let message_encoding = Block_and_signatures.encoding

     type node_state = {
       self : Tenderbatter.Node.Id.t;
       round : int;
       convincing_blocks : Convincing_blocks.t;
       locked_block : Block.t;
     }

     let node_state_encoding =
       let open Data_encoding in
       conv
         (fun { self; round; convincing_blocks; locked_block } ->
           (self, Int64.of_int round, convincing_blocks, locked_block))
         (fun (self, round, convincing_blocks, locked_block) ->
           { self; round = Int64.to_int round; convincing_blocks; locked_block })
       @@ obj4
            (req "self" Tenderbatter.Node.Id.encoding)
            (req "round" int64)
            (req "convincing_blocks" Convincing_blocks.encoding)
            (req "locked_block" Block.encoding)

     type params = consensus_params

     let params_encoding = consensus_params_encoding

     let init_node_state _params self =
       {
         self;
         (* 1-indexed so we can say that we terminate on round f + 1 *)
         round = 1;
         convincing_blocks = Convincing_blocks.empty;
         locked_block = Block.genesis;
       }
   end

   include Tenderbatter.Simulator.Make (Algorithm)

   let is_proposer_for_time ~params:{ n; f; delta } ~time proposer =
     let r = Time.to_float time /. delta |> Float.floor |> Float.to_int in
     r mod (n * (f + 1)) = Tenderbatter.Node.Id.to_int proposer

   let sign_block_and_broadcast ~private_key block_and_signatures =
     let message =
       Block_and_signatures.add_signature block_and_signatures private_key
     in
     Effect.Send_message message

   let propose_new_block ~private_key block =
     let message = Block_and_signatures.make block private_key in
     Effect.Send_message message

   let good_node : event_handler =
    fun params time event private_key state ->
     let open Tenderbatter in
     match event with
     | Event.Message_received block_and_signatures ->
       let Block_and_signatures.{ block; _ } = block_and_signatures in
       let state = { state with locked_block = block } in
       ([], state)
     | Event.Wake_up ->
       let state = { state with round = state.round + 1 } in
       let next_time = Time.add time (Time.from_float params.delta) in
       let wake_up = Effect.Set_wake_up_time next_time in
       if is_proposer_for_time ~params ~time state.self then (
         (* Mock mempool *)
         let transactions = [Transaction.originate ()] in
         let next_block_level = state.locked_block.level |> Int64.add 1L in
         let next_block =
           Block.make ~transactions ~level:next_block_level
             ~prev_block_hash:state.locked_block.hash
         in
         let propose_new_block = propose_new_block ~private_key next_block in
         let state =
           Algorithm.
             {
               self = state.self;
               round = 1;
               convincing_blocks = Convincing_blocks.empty;
               locked_block = next_block;
             }
         in
         Format.printf "Node %d proposing block level %d\n%!"
           (Node.Id.to_int state.self)
           (next_block_level |> Int64.to_int);
         ([wake_up; propose_new_block], state))
       else ([wake_up], state)

   let crash_fault_node : event_handler =
     let open Tenderbatter in
     fun params time event private_key state ->
       if Random.bool () then (
         Format.printf "Node %d crashing.\n%!" (Node.Id.to_int state.self);
         ([Effect.Shut_down], state))
       else good_node params time event private_key state *)
