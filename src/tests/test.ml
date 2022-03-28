let test_foo () = Alcotest.(check string) "same string" "bar" Consensus.foo

(* Run it *)
let () =
  let open Alcotest in
  run "Test" [("Foo tests", [test_case "Test foo" `Quick test_foo])]
