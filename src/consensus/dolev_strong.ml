open Helpers
open Tenderbatter

type consensus_params = {
  n : int;
  f : int;
  delta : float;
}

module Convincing_blocks : sig
  type t

  val empty : t

  val add_block :
    params:consensus_params ->
    current_round:int ->
    block_and_signatures:Block_and_signatures.t ->
    t ->
    t * bool

  val get_convincing_block : locked_block:Block.t -> t -> Block.t
end = struct
  module Block_set = Set.Make (Block)

  type t = Block_set.t

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

  let get_convincing_block ~locked_block t =
    if Block_set.cardinal t = 1 then Block_set.choose t
    else
      let level = Int64.add locked_block.Block.level 1L in
      Block.empty ~level ~prev_block_hash:locked_block.hash
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

  let node_state_encoding = assert false

  type params = consensus_params

  let params_encoding = assert false

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

let is_proposer_for_level ~params ~level proposer =
  Int64.to_int level mod params.n = Tenderbatter.Node.Id.to_int proposer

let is_next_block ~state block =
  block.Block.prev_block_hash = state.Algorithm.locked_block.hash
  && block.level = Int64.add state.locked_block.level 1L

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
    if is_next_block ~state block_and_signatures.block then
      let convincing_blocks, added_block =
        Convincing_blocks.add_block ~params ~current_round:state.round
          ~block_and_signatures state.convincing_blocks
      in
      let state = { state with convincing_blocks } in
      if added_block then
        ([sign_block_and_broadcast ~private_key block_and_signatures], state)
      else ([], state)
    else ([], state)
  | Event.Wake_up ->
    let state = { state with round = state.round + 1 } in
    let next_time = Time.add time (Time.from_float params.delta) in
    let wake_up = Effect.Set_wake_up_time next_time in
    if state.round > params.f + 1 then
      let next_block_level = state.locked_block.level |> Int64.add 1L in
      let should_propose_new_block =
        is_proposer_for_level ~params ~level:next_block_level state.self
      in
      if should_propose_new_block then
        (* Mock mempool *)
        let transactions = [Transaction.originate ()] in
        let next_block =
          Block.make ~transactions ~level:next_block_level
            ~prev_block_hash:state.locked_block.hash
        in
        let state =
          Algorithm.
            {
              self = state.self;
              round = 1;
              convincing_blocks = Convincing_blocks.empty;
              locked_block =
                Convincing_blocks.get_convincing_block
                  ~locked_block:state.locked_block state.convincing_blocks;
            }
        in
        ([propose_new_block ~private_key next_block], state)
      else ([wake_up], state)
    else ([wake_up], state)
