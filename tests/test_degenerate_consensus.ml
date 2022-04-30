(*
  for all s,t where s > t * 3 /\ s % 2 = 1,
  for all participant sets P,
  run the consensus
  assert
    (agreement) all honest nodes have the same value (validity)
    (validity) if the honest nodes all started with the same
      value, they all still have the same value
*)
module Value = struct
  include Int

  let default = 0
end

module Consensus =
  Degenerate_consensus.Make
    (Value)
    (* Networking doesn't matter because we don't
       actually send any messages in Degenerate_consensus.
       But we still want to comply with the interface. *)
    (Mock_network.Perfect_network)

let make_network s init_f =
  let participants = List.init s Fun.id in
  List.map
    (fun id ->
      let config = Node_interface.{ self = id; participants } in
      let init_value = init_f id in
      Consensus.init ~config init_value)
    participants

(* (nodes, List.concat side_effects) *)
(*
   let step :
       Side_effect.t -> Consensus.t list -> Consensus.t list * Side_effect.t list =
    fun side_effect nodes ->
     let open Side_effect in
     match side_effect with
     | Send_to_all { sender; value } ->
         List.fold_left
           (fun (nodes, all_effects) node ->
             let node, node_effects =
               Consensus.receive_message ~sender ~value node
             in
             (node :: nodes, node_effects @ all_effects))
           ([], []) nodes
     | Commit _ -> (nodes, [])

   let rec run_consensus nodes = function
     | [] -> nodes
     | hd :: tl ->
         let nodes, side_effects = step hd nodes in
         run_consensus nodes (side_effects @ tl)

   let all_nodes_agree_on value nodes =
     List.for_all (fun node -> Consensus.latest_commitment node = value) nodes

   let test_agreement s =
     let nodes, init_side_effects =
       make_nodes s (fun i ->
           (* Make 1/2 the nodes start at 0 and half at 1 *)
           i mod 2)
     in
     let nodes = run_consensus nodes init_side_effects in
     let commitment = Consensus.latest_commitment (List.hd nodes) in
     assert (all_nodes_agree_on commitment nodes)

   let test_agreement_alcotest () = test_agreement 5

   let test_validity s =
     let nodes, init_side_effects = make_nodes s (fun _ -> 1) in
     let nodes = run_consensus nodes init_side_effects in
     let agreed_on_round_and_value = (0, 1) in
     assert (all_nodes_agree_on agreed_on_round_and_value nodes)

   let test_validity_alcotest () = test_validity 5

   (* Run it *)
   let () =
     let open Alcotest in
     run "Test"
       [
         ( "Consensus unit tests",
           [
             test_case "Test agreement" `Quick test_agreement_alcotest;
             test_case "Test validity" `Quick test_validity_alcotest;
           ] );
       ] *)
