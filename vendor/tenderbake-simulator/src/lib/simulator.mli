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

(** [Algorithm] defines types that are specific to a consensus algorithm. *)
module type Algorithm = sig
  type message
  (** The type of messages that are exchanged over the network. *)

  val message_encoding : message Data_encoding.t
  (** [message] JSON encoding. *)

  type node_state
  (** Node state. *)

  type params
  (** Algorithm parameters. *)

  val params_encoding : params Data_encoding.t
  (** Algorithm parameters. *)

  val init_node_state : params -> Node.Id.t -> node_state
  (** The state in which every node starts in. *)

  val node_state_encoding : node_state Data_encoding.t
  (** [node_state] JSON encoding. *)
end

(** Given an [Algorithm] module, produce a simulator for that algorithm. *)
module Make (A : Algorithm) : sig
  module Event : sig
    type t = Wake_up | Message_received of A.message

    val encoding : t Data_encoding.t
  end

  module Effect : sig
    type t =
      | Set_wake_up_time of Time.t
      | Send_message of A.message
      | Shut_down

    val encoding : t Data_encoding.t
  end

  type event_handler =
    A.params ->
    Time.t ->
    Event.t ->
    Signature.private_key ->
    A.node_state ->
    Effect.t list * A.node_state

  val with_lifetime : Time.t -> event_handler -> event_handler
  (** Modify the given event handler to make the node shut down after its
     lifetime expires. *)

  type predicate =
    Time.t ->
    int ->
    (Node.Id.t * Time.t option * A.node_state) option array ->
    bool
  (** Given the current time, iteration that just occurred, and the state
     of the nodes, return a [bool]. *)

  module Log :
    Logging.Log
      with type params = A.params
       and type event = Event.t
       and type state = A.node_state
       and type effect = Effect.t

  val run_simulation :
    ?formatter:Format.formatter ->
    ?message_delay:Network.Delay.t ->
    ?seed:int ->
    ?predicates:(string * predicate) list ->
    params:A.params ->
    iterations:int ->
    nodes:(int * string * event_handler) list ->
    unit ->
    Log.t
    * (Node.Id.t * Time.t option * A.node_state) option array
    * (string * int option) list
  (** Perform a single simulation run. *)
end
