open Helpers
open Tenderbatter
open Dolev_strong
open Crypto

let good_node = "good node"
(*
   (* Checks that every block in the list is
      either equal or the next block about to be produced.
   *)
   let blocks_ok blocks =
     let module Block_set = Set.Make (Block) in
     let block_set = Block_set.of_list blocks in
     match Block_set.elements block_set |> List.sort Block.compare_level with
     | [] | [_] ->
       (* Vacuously true case, only used in debugging *)
       true
     | [a; b] ->
       (* If there are exactly two blocks locked, it must be the case
          that the second is a valid next block relative to the first. *)
       Block.is_next_block ~current:a ~next:b
     | _ ->
       (* If there are more than 2 different blocks locked,
          safety is violated. *)
       false

   let get_locked_blocks states =
     Array.to_list states
     |> List.filter_map Fun.id
     |> List.map (fun (_, _, x) -> x)
     |> List.map (fun x -> x.Algorithm.locked_block)

   let safety _ _ states = get_locked_blocks states |> blocks_ok

   (*
      The right formulation of liveness is something like:
        if the block producer is honest, then there is eventually consensus
        on his block.
      But Tenderbatter doesn't let us iterate over every state, just the current
      one (this is a bit lame - iterating over every state is exactly what we want
      for temporal properties like liveness. TODO: fix this).

      So instead we'll use block level as proxy for liveness.
      Because we're in a synchronous setting, we now that
      by a certain time, we will have reached at least a certain
      block level.
      Specifically, assume block 0 is locked at at time 0.
      Let r be the number of rounds that occured. We know
      We know that by time t, r = t / delta.
      It takes f + 1 rounds to increment the block level, giving the level
      an upper bound of r / (f + 1).
      From this, we must account for the fact that when a dishonest
      node is the block producer, he may fail to produce a block at all.
      We can do this by multiplying by the proportion of honest nodes to all nodes,
      (n - f / n).

      Thus, the expected level is
      (r / (f + 1)) * ((n - f) / n)
      = (r * (n - f)) / (n * (f + 1))
   *)
   let liveness ~params:{ n; f; delta } time _ states = assert false
   (* let time = Time.to_float time in
      let r = time /. delta |> Float.to_int in
      let max_proposals =
      let expected_level = r * (n - f) / (n * (f + 1)) in
      get_locked_blocks states
      |> List.for_all (fun Block.{ level; _ } ->
             let level = Int64.to_int level in
             level >= expected_level) *) *)
