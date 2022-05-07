module Degenerate_harness = Consensus_harness.Make (Degenerate_consensus)

let test_agreement () =
  Degenerate_harness.test_agreement
    ~init_fn:(fun _i -> Random.int 230)
    ~honest_nodes:5 (* We have officially solved blockchain  *)
    ~byzantine_nodes:9001

let test_validity () =
  try
    Degenerate_harness.test_validity ~honest_nodes:5 ~byzantine_nodes:0;
    (* Degenerate consensus lacks validity *)
    assert false
  with
  | _ -> ()

let tests =
  let open Alcotest in
  [
    test_case "Degenerate agreement" `Quick test_agreement;
    test_case "Degenerate validity (expectedly fails)" `Quick test_validity;
  ]
