open Helpers
open Node_interface
open Tenderbatter
open Value
module Try = Preface.Try

module type PARAMS = sig
  module Value : VALUE

  val is_valid_next_value : Value.t -> bool
  val is_proposer : Node.Id.t -> bool
  val get_next_value : unit -> Value.t
end

module Make (Params : PARAMS) = struct
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
      && Params.is_proposer actual_block_producer
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
      final_value : Value.t option;
    }

    let node_state_encoding =
      let open Data_encoding in
      conv
        (fun { self; round; convincing_values; final_value } ->
          (self, Int64.of_int round, convincing_values, final_value))
        (fun (self, round, convincing_values, final_value) ->
          { self; round = Int64.to_int round; convincing_values; final_value })
      @@ obj4
           (req "self" Tenderbatter.Node.Id.encoding)
           (req "round" int64)
           (req "convincing_blocks" Convincing_values.encoding)
           (req "final_value" @@ option Value.encoding)

    type params = consensus_params

    let params_encoding = consensus_params_encoding

    let init_node_state _params self =
      {
        self;
        round = 0;
        convincing_values = Convincing_values.empty;
        final_value = None;
      }
  end

  include Tenderbatter.Simulator.Make (Algorithm)

  let sign_block_and_broadcast ~private_key value_and_signatures =
    let%ok message =
      Value_and_signatures.add_signature value_and_signatures private_key
    in
    Ok (Effect.Send_message message)

  let propose_new_value ~private_key value =
    let message = Value_and_signatures.make ~private_key value in
    Effect.Send_message message

  let jitter = 0.1

  let exit a =
    Format.printf "\n%!";
    a

  let honest_node : event_handler =
   fun params time event private_key state ->
    if Option.is_some state.final_value then
      (* Early exit useful for debugging. *)
      ([], state)
    else (
      Format.printf "Node %s, " (Node.Id.to_int state.self |> string_of_int);
      Format.printf "Time %s, " (Time.to_float time |> Float.to_string);
      match event with
      | Event.Message_received value_and_signatures -> (
        match
          Convincing_values.add_value ~current_round:state.round
            ~value_and_signatures state.convincing_values
        with
        | Ok convincing_values ->
          Format.printf "got a convincing message ";
          let state = { state with convincing_values } in
          let broadcast =
            sign_block_and_broadcast ~private_key value_and_signatures
            (* TODO: I already checked that the signatures were valid. Refactor this away. *)
            |> Result.get_ok
          in
          exit ([broadcast], state)
        | Error _ ->
          Format.printf "Already got this message";
          exit ([], state))
      | Event.Wake_up ->
        let current_round = state.round in
        let state = { state with round = state.round + 1 } in
        if current_round < (2 * params.f) + 1 then
          let next_time = Time.add time (Time.from_float params.delta) in
          let wake_up = Effect.Set_wake_up_time next_time in
          if Params.is_proposer state.self then (
            Format.printf "proposing value";
            let value = Params.get_next_value () in
            let propose_new_value = propose_new_value ~private_key value in
            let state = { state with final_value = Some value } in
            exit ([wake_up; propose_new_value], state))
          else (
            Format.printf "not propser, doing nothing";
            exit ([wake_up], state))
        else
          (* Consensus is over. Terminate indefinitely with a final value *)
          let final_value =
            if Params.is_proposer state.self then
              (* If we are the proposer, we already know the final value *)
              state.final_value
            else Convincing_values.get_convincing_value state.convincing_values
          in
          let final_value_str =
            match final_value with
            | Some x ->
              Format.sprintf "Some %s" (x |> Obj.magic |> Int64.to_string)
            | None -> "None"
          in
          Format.printf "terminating with value: %s" final_value_str;
          let new_state = { state with final_value } in
          exit ([], new_state))

  let crash_fault_node : event_handler =
   fun params time event private_key state ->
    if Random.bool () then (
      Format.printf "Node %d crashing.\n%!" (Node.Id.to_int state.self);
      ([Effect.Shut_down], state))
    else honest_node params time event private_key state
end
