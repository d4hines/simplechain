open Node_interface
open Mock_network

module Value = struct
  include Int

  let default = 0
  let random () = Random.int 230
end

module Make (Consensus : Node_interface.NODE_INTERFACE) = struct
  module Node = Byzantine_wrapper.Make (Consensus) (Value) (Perfect_network)

  let init_network ~honest_nodes ~byzantine_nodes init_fn =
    Node.init_network ~honest_nodes ~byzantine_nodes init_fn

  let all_honest_nodes_agree_on ~level ~value nodes =
    List.filter Node.is_honest nodes
    |> List.for_all (fun node ->
           let node_level, node_value = Node.latest_commitment node in
           Format.printf "Node level %d, node value %d\n%!" node_level
             node_value;
           (node_level, node_value) = (level, value))

  let propose_via_random ~value nodes =
    let random_i = Random.int @@ List.length nodes in
    List.iteri
      (fun i node -> if i = random_i then Node.propose_next_value ~value node)
      nodes

  let test_agreement ~init_fn ~honest_nodes ~byzantine_nodes =
    let nodes = init_network ~honest_nodes ~byzantine_nodes init_fn in
    let value = Value.random () in
    propose_via_random ~value nodes;
    let level, value =
      List.find Node.is_honest nodes |> Node.latest_commitment
    in
    Perfect_network.flush ();
    assert (all_honest_nodes_agree_on ~level ~value nodes)

  let test_validity ~honest_nodes ~byzantine_nodes =
    let init_value = Value.random () in
    let nodes =
      init_network ~honest_nodes ~byzantine_nodes (fun _ -> init_value)
    in
    let proposed_value = Value.random () in
    propose_via_random ~value:proposed_value nodes;
    let level, _ = List.hd nodes |> Node.latest_commitment in
    assert (all_honest_nodes_agree_on ~level ~value:proposed_value nodes)
end
