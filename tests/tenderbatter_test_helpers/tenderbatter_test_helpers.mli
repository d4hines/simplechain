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
module List = List

module Make (A : Simulator.Algorithm) : sig
  include module type of Simulator.Make (A)

  type config = {
    test_name : string;
    params : A.params;
    iterations : int;
    nodes : (int * string * event_handler) list;
    message_delay : Network.Delay.t option;
    predicates : (string * predicate) list;
    seeds : int list;
    final_state_check :
      (Node.Id.t * Time.t option * A.node_state) option array -> bool;
    log_check : Log.t -> bool;
    debug : bool;
  }

  val no_check : 'a -> bool
  (** Always return [true]. This is a trivial placeholder function that can
     be passed as [final_state_check] and/or [log_check]. *)

  val unique_txn : (A.node_state -> Transaction.t list) -> predicate
  (** Given an access function, create a predicate to test that all
      transactions in a node's blockchain are unique. *)

  val case : config -> unit Alcotest.test_case
end
