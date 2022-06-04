open Tenderbatter
open Dolev_strong
open Crypto
(* module Test = Tenderbatter_test_helpers.Helpers.Make (Singleshot.Algorithm) *)
(*
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

   let predicates params =
     [("safety", Predicates.safety); ("liveness", Predicates.liveness ~params)]

   let message_delay = Some (Network.Delay.linear ~min:0.1 ~max:0.9)
   let seeds = List.init 5 (fun x -> x)

   let all_honest_test =
     Test.case
     @@
     let n = 3 in
     let f = 0 in
     let params = Algorithm.{ n; f; delta = 1. } in
     {
       params;
       message_delay;
       seeds;
       iterations = 100;
       test_name = "ds-all-honest";
       nodes = [(n - f, Predicates.good_node, Dolev_strong.good_node)];
       predicates = predicates params;
       final_state_check = Test.no_check;
       log_check = Test.no_check;
       debug = true;
     }

   let crash_fault_test =
     Test.case
     @@
     let n = 5 in
     let f = 2 in
     let params = Algorithm.{ n; f; delta = 1. } in
     {
       params;
       message_delay;
       seeds;
       test_name = "ds-crash-fault";
       iterations = 1000;
       nodes =
         [
           (n - f, Predicates.good_node, Dolev_strong.good_node);
           (f, "crash fault node", Dolev_strong.crash_fault_node);
         ];
       predicates = predicates params;
       final_state_check = Test.no_check;
       log_check = Test.no_check;
       debug = true;
     }

   let test_cases = [ (* hashing_test; all_honest_test; crash_fault_test *) ] *)
