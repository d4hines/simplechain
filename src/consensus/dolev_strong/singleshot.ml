open Helpers
open Node_interface
open Tenderbatter
open Value
module Try = Preface.Try

module type PARAMS = sig
  module Value : VALUE

  val is_valid_next_value : Value.t -> bool
  val proposer : Node.Id.t
end

module Singleshot (Params : PARAMS) = struct
  module Value = Params.Value
  module Value_and_signatures = Value_and_signatures (Value)

  type consensus_params = {
    n : int;
    f : int;
    delta : float;
  }

  let consensus_params_encoding =
    let open Data_encoding in
    conv
      (fun { n; f; delta } -> (Int64.of_int n, Int64.of_int f, delta))
      (fun (n, f, delta) -> { n = Int64.to_int n; f = Int64.to_int f; delta })
    @@ obj3 (req "n" int64) (req "f" int64) (req "delta" float)

  module Convincing_values : sig
    type t

    val encoding : t Data_encoding.t
    val empty : t

    val add_value :
      current_round:int ->
      value_and_signatures:Value_and_signatures.t ->
      t ->
      t Try.t

    val get_convincing_value : t -> Value.t option
  end = struct
    module Value_set = Set.Make (Value)

    type t = Value_set.t

    let encoding =
      let open Data_encoding in
      conv Value_set.elements Value_set.of_list (list Value.encoding)

    let empty = Value_set.empty

    let is_convincing ~current_round Value_and_signatures.{ value; signatures }
        =
      (* by convention, ORDER MATTERS for the signatures *)
      let first_signature =
        signatures |> List.rev |> List.hd |> Signed.get_signature
      in
      let actual_block_producer = Signature.signer first_signature in
      Params.is_valid_next_value value
      && actual_block_producer = Params.proposer
      && List.length signatures >= current_round

    let add_value ~current_round
        ~value_and_signatures:Value_and_signatures.{ value; signatures } t =
      match
        ( is_convincing ~current_round { value; signatures },
          Value_set.mem value t )
      with
      | true, false -> Try.ok @@ Value_set.add value t
      | false, _ -> Try.error @@ Invalid_argument "unconvincing value"
      | _, true -> Try.error @@ Invalid_argument "Value already added"

    let get_convincing_value t =
      if Value_set.cardinal t = 1 then Some (Value_set.choose t) else None
  end

  module Algorithm = struct
    type message = Value_and_signatures.t

    let message_encoding = Value_and_signatures.encoding

    type node_state = {
      self : Tenderbatter.Node.Id.t;
      round : int;
      convincing_values : Convincing_values.t;
    }

    let node_state_encoding =
      let open Data_encoding in
      conv
        (fun { self; round; convincing_values } ->
          (self, Int64.of_int round, convincing_values))
        (fun (self, round, convincing_values) ->
          { self; round = Int64.to_int round; convincing_values })
      @@ obj3
           (req "self" Tenderbatter.Node.Id.encoding)
           (req "round" int64)
           (req "convincing_blocks" Convincing_values.encoding)

    type params = consensus_params

    let params_encoding = consensus_params_encoding

    let init_node_state _params self =
      {
        self;
        (* 1-indexed so we can say that we terminate on round f + 1 *)
        round = 1;
        convincing_values = Convincing_values.empty;
      }
  end

  include Tenderbatter.Simulator.Make (Algorithm)

  let sign_block_and_broadcast ~private_key value_and_signatures =
    let%ok message =
      Value_and_signatures.add_signature value_and_signatures private_key
    in
    Ok (Effect.Send_message message)

  let propose_new_block ~private_key value =
    let message = Value_and_signatures.make ~private_key value in
    Effect.Send_message message

  let honest_node : event_handler =
   fun params time event private_key state ->
    match event with
    | Event.Message_received value_and_signatures -> (
      match
        Convincing_values.add_value ~current_round:state.round
          ~value_and_signatures state.convincing_values
      with
      | Ok convincing_values -> assert false
      | Error _ -> ([], state))
    | Event.Wake_up -> assert false
end

(*
     let honest_node : event_handler =
      fun params time event private_key state ->
       let open Tenderbatter in
       match event with
       | Event.Message_received block_and_signatures ->
         if Block.is_next_block
         let Block_and_signatures.{ block; _ } = block_and_signatures in
         let state = { state with locked_block = block } in
         if Block.is_next_block ~state block_and_signatures.block then
           let convincing_blocks, added_block =
             Convincing_blocks.add_block ~params ~current_round:state.round
               ~block_and_signatures state.convincing_blocks
           in
           let state = { state with convincing_blocks } in
           if added_block then
             ([sign_block_and_broadcast ~private_key block_and_signatures], state)
           else ([], state)
         else ([], state)
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
