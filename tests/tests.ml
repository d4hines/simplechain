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

(* module Consensus = Consensus.Make (Value) *)
(* module Side_effect = Consensus.Side_effect *)

(* let () =
   let open Alcotest in
   run "Test" [("Degenerate consensus", Test_degenerate_consensus.tests)] *)
