open Tenderbatter
open Node_interface
open Value
open Dolev_strong
open Tenderbatter_test_helpers

module V = struct
  open Crypto

  type t = int64

  let encoding = Data_encoding.int64
  let hash t = Int64.to_string t |> BLAKE2B.hash
  let sign ~private_key t = Signed.make private_key BLAKE2B.encoding (hash t)
  let compare = Int64.compare
end

let all_honest_test seed =
  Random.init seed;
  let n = 10 in
  let f = 0 in
  let expected_value = Random.int64 Int64.max_int in
  Format.printf "\nStaring new round. ";
  Format.printf "Expected value: %Ld " expected_value;
  let module Params : Singleshot.PARAMS = struct
    module Value = V

    let is_valid_next_value _value = true

    let is_proposer =
      let proposer = Random.int n in
      Format.printf "Proposer: %d\n%!" proposer;
      fun node -> Node.Id.to_int node = proposer

    let get_next_value () = expected_value
  end in
  let open Singleshot.Make (Params) in
  let module Test = Tenderbatter_test_helpers.Helpers.Make (Algorithm) in
  let module Predicates = Singleshot_predicates.Make (Params) in
  Test.case
  @@
  let params = Algorithm.{ n; f; delta = 1. } in
  {
    params;
    message_delay = Some (Network.Delay.linear ~min:0.1 ~max:0.9);
    seed;
    iterations = 100;
    test_name = "ds-singleshot-all-honest";
    nodes = [(n - f, Singleshot_predicates.honest_node, honest_node)];
    predicates = [];
    final_state_check =
      Predicates.validity
        ~expected_value:
          ((* TODO: why do I need Obj.magic here? *)
           Obj.magic expected_value);
    log_check = Test.no_check;
    debug = true;
  }

let all_honest_alcotest =
  ( "all_honest",
    `Slow,
    fun () -> List.iter all_honest_test (List.init 100 Fun.id) )

let crash_fault_test seed =
  Random.init seed;
  let n = 1 in
  let f = 1 in
  let expected_value = Random.int64 Int64.max_int in
  Format.printf "\nStaring new round. ";
  Format.printf "Expected value: %Ld " expected_value;
  let module Params : Singleshot.PARAMS = struct
    module Value = V

    let is_valid_next_value _value = true

    let is_proposer =
      let proposer = Random.int n in
      Format.printf "Proposer: %d\n%!" proposer;
      fun node -> Node.Id.to_int node = proposer

    let get_next_value () = expected_value
  end in
  let open Singleshot.Make (Params) in
  let module Test = Tenderbatter_test_helpers.Helpers.Make (Algorithm) in
  let module Predicates = Singleshot_predicates.Make (Params) in
  Test.case
  @@
  let params = Algorithm.{ n; f; delta = 1. } in
  {
    params;
    message_delay = Some (Network.Delay.linear ~min:0.1 ~max:0.9);
    seed;
    iterations = 100;
    test_name = "ds-singleshot-all-honest";
    nodes = [(n - f, Singleshot_predicates.honest_node, honest_node)];
    predicates = [];
    final_state_check =
      Predicates.validity
        ~expected_value:
          ((* TODO: why do I need Obj.magic here? *)
           Obj.magic expected_value);
    log_check = Test.no_check;
    debug = true;
  }

let test_cases = [all_honest_alcotest]
