(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021 Nomadic Labs, <contact@nomadic-labs.com>               *)
(*                                                                           *)
(* Permission is hereby granted, free of charge, to any person obtaining a   *)
(* copy of this software and associated documentation files (the "Software"),*)
(* to deal in the Software without restriction, including without limitation *)
(* the rights to use, copy, modify, merge, publish, distribute, sublicense,  *)
(* and/or sell copies of the Software, and to permit persons to whom the     *)
(* Software is furnished to do so, subject to the following conditions:      *)
(*                                                                           *)
(* The above copyright notice and this permission notice shall be included   *)
(* in all copies or substantial portions of the Software.                    *)
(*                                                                           *)
(* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR*)
(* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,  *)
(* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL   *)
(* THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER*)
(* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING   *)
(* FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER       *)
(* DEALINGS IN THE SOFTWARE.                                                 *)
(*                                                                           *)
(*****************************************************************************)

open Tenderbatter
open Ouroboros
module Test = Tenderbatter_test_helpers.Helpers.Make (Algorithm)

let stress_test_config : Test.config =
  let total_nodes = 10 in
  {
    test_name = "ouroboros-stress-test";
    params = default_params total_nodes;
    iterations = 2000;
    nodes = [ (total_nodes, "good node", Ouroboros.good_node) ];
    message_delay = Some (Network.Delay.linear ~min:0.1 ~max:0.9);
    predicates =
      [
        ("safety", Predicates.safety);
        ("liveness", Predicates.liveness total_nodes);
        ("unique_txn", Test.unique_txn Predicates.get_txns);
      ];
    seeds = List.init 100 (fun x -> x);
    final_state_check = Test.no_check;
    log_check = Test.no_check;
    debug = false;
  }

let test_cases = [ Test.case stress_test_config ]
