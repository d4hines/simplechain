open Tenderbatter
open Node_interface
open Value
open Dolev_strong
open Tenderbatter_test_helpers

module Value = struct
  open Crypto

  type t = int64

  let encoding = Data_encoding.int64
  let hash t = Int64.to_string t |> BLAKE2B.hash
  let sign ~private_key t = Signed.make private_key BLAKE2B.encoding (hash t)
  let compare = Int64.compare
end

let message_delay = Some (Network.Delay.linear ~min:0.1 ~max:0.9)
let delta = 1.

let all_honest_test seed =
  Random.init seed;
  let n = 2 in
  let f = 0 in
  let expected_value =
    Random.int64 Int64.max_int
    (* TODO: why do I need Obj.magic here? *)
    |> Obj.magic
  in
  Format.printf "\nStaring new round. ";
  Format.printf "Expected value: %Ld " expected_value;
  let module Params : Singleshot.PARAMS = struct
    module Value = Value

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
  let params = Algorithm.{ n; f; delta } in
  {
    params;
    message_delay;
    seed;
    iterations = 100;
    test_name = "ds-singleshot-all-honest";
    nodes = [(n - f, Singleshot_predicates.honest_node, honest_node)];
    predicates = [];
    final_state_check =
      (* Validity check. Subsumes agreement. *)
      Predicates.all_honest_nodes_agree ~expected_value:(Some expected_value);
    log_check = Test.no_check;
    debug = true;
  }

let all_honest_alcotest =
  ( "all_honest",
    `Slow,
    fun () -> List.iter all_honest_test (List.init 100 Fun.id) )

let crash_fault_proposer_test seed =
  Random.init seed;
  let n = 12 in
  let f = 10 in
  Format.printf "\nStaring new round. ";
  let module Params : Singleshot.PARAMS = struct
    module Value = Value

    let is_valid_next_value _value = true

    let is_proposer =
      (* Guarantee a dishonest proposer *)
      let proposer = n - Random.int f in
      Format.printf "Proposer: %d\n%!" proposer;
      fun node -> Node.Id.to_int node = proposer

    let get_next_value () = assert false
  end in
  let open Singleshot.Make (Params) in
  let module Test = Tenderbatter_test_helpers.Helpers.Make (Algorithm) in
  let module Predicates = Singleshot_predicates.Make (Params) in
  Test.case
  @@
  let params = Algorithm.{ n; f; delta } in
  {
    params;
    message_delay;
    seed;
    iterations = 100;
    test_name = "ds-singleshot-crash-fault-proposer";
    nodes =
      [
        (n - f, Singleshot_predicates.honest_node, honest_node);
        (f, "crash fault node", crash_fault_immediately);
      ];
    predicates = [];
    final_state_check =
      (* Agreement check. Validity is vacuously satisfied because
         the proposer is dishonest. *)
      Predicates.all_honest_nodes_agree ~expected_value:None;
    log_check = Test.no_check;
    debug = true;
  }

let crash_fault_proposer_alcotest =
  ( "crash_fault_proposer",
    `Slow,
    fun () -> List.iter crash_fault_proposer_test (List.init 100 Fun.id) )

let crash_fault_non_proposer_test seed =
  Random.init seed;
  let n = 10 in
  let f = 6 in
  let expected_value =
    Random.int64 Int64.max_int
    (* TODO: why do I need Obj.magic here? *)
    |> Obj.magic
  in
  Format.printf "\nStaring new round. ";
  Format.printf "Expected value: %Ld " expected_value;
  let module Params : Singleshot.PARAMS = struct
    module Value = Value

    let is_valid_next_value _value = true

    let is_proposer =
      (* Guarantee an honest proposer *)
      let proposer = Random.int (n - f) in
      Format.printf "Proposer: %d\n%!" proposer;
      fun node -> Node.Id.to_int node = proposer

    let get_next_value () = expected_value
  end in
  let open Singleshot.Make (Params) in
  let module Test = Tenderbatter_test_helpers.Helpers.Make (Algorithm) in
  let module Predicates = Singleshot_predicates.Make (Params) in
  Test.case
  @@
  let params = Algorithm.{ n; f; delta } in
  {
    params;
    message_delay;
    seed;
    iterations = 1000;
    test_name = "ds-singleshot-crash-fault-proposer";
    nodes =
      [
        (n - f, Singleshot_predicates.honest_node, honest_node);
        (f, "crash fault node", crash_fault_node);
      ];
    predicates = [];
    final_state_check = Test.no_check;
    (* Agreement check. Validity is vacuously satisfied because
       the proposer is dishonest. *)
    (* Predicates.all_honest_nodes_agree ~expected_value; *)
    log_check = Test.no_check;
    debug = true;
  }

let crash_fault_non_proposer_alcotest =
  ( "crash_fault_non_proposer",
    `Slow,
    fun () -> List.iter crash_fault_non_proposer_test (List.init 100 Fun.id) )

(* Debug only *)
let skip (name, speed, _) = (name, speed, fun () -> ())

let test_cases =
  [
    all_honest_alcotest;
    crash_fault_proposer_alcotest;
    crash_fault_non_proposer_alcotest;
  ]
