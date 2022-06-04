let () =
  let open Alcotest in
  run "Test"
    [("Dolev-Strong Protocol", Dolev_strong_test.Singleshot_test.test_cases)]
