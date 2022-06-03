open Tenderbatter
open Dolev_strong
open Crypto
module Test = Tenderbatter_test_helpers.Make (Algorithm)

let hashing_test =
  Alcotest.test_case "block hashing" `Quick (fun () ->
      let Block.{ transactions; level; prev_block_hash; _ } = Block.genesis in
      let expected_hash =
        "a54f9f072eb9467ef6eec3aa532483d57ad3d293736085dac903abf18a932def"
      in
      let hash =
        Block.hash ~transactions ~level ~prev_block_hash |> BLAKE2B.to_string
      in

      Alcotest.check Alcotest.string "hashes is expected" expected_hash hash)

let stress_test_config : Test.config =
  let n = 2 in
  let f = 0 in
  let total_nodes = n + f in
  let params = Algorithm.{ n; f; delta = 1. } in
  {
    test_name = "dolev-strong-stress-test";
    params;
    iterations = 10;
    nodes = [(total_nodes, "good node 1", Dolev_strong.good_node)];
    message_delay = Some (Network.Delay.linear ~min:0.1 ~max:0.9);
    predicates =
      [("safety", Predicates.safety); ("liveness", Predicates.liveness ~params)];
    seeds = List.init 1 (fun x -> x);
    final_state_check = Test.no_check;
    log_check = Test.no_check;
    debug = true;
  }

let test_cases = [hashing_test; Test.case stress_test_config]
