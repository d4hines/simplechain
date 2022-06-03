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

(** [Event] module describes how to convert an [event] to JSON. *)
module type Entry = sig
  type params
  (** Algorithm parameters of a simulaton. *)

  val params_encoding : params Data_encoding.t
  (** Encoding of algorithm parameters. *)

  type event
  (** Event in a log. *)

  val event_encoding : event Data_encoding.t
  (** Encoding of [event]. *)

  type state
  (** State of an individual node. *)

  val state_encoding : state Data_encoding.t
  (** Encoding of [state]. *)

  type effect
  (** Effect output by a node. *)

  val effect_encoding : effect Data_encoding.t
  (** Encoding of [effect]. *)
end

val pp_json : Format.formatter -> Json_repr.ezjsonm -> unit
(** A human-friendly way of printing JSON. *)

module type Log = sig
  type params
  type event
  type state
  type effect

  module Entry : sig
    type t = {
      time : Time.t;
      iteration : int;
      event : event;
      init_state : state;
      new_state : state;
      effects : effect list;
    }

    val encoding : t Data_encoding.t
  end

  type t = { params : params; mutable entries : Entry.t Queue.t }

  val encoding : t Data_encoding.t
  (** Log encoding. *)

  val create : params -> t
  (** Start a new log. *)

  val log :
    formatter:Format.formatter option ->
    time:Time.t ->
    iteration:int ->
    event:event ->
    init_state:state ->
    new_state:state ->
    effects:effect list ->
    t ->
    unit
  (** Add an entry to a log. *)

  val pp : Format.formatter -> t -> unit
  (** Pretty print a log in human-friendly form. *)

  val pp_to_file : t -> string -> unit
  (** Pretty print a log in human-friendly form to a file. *)

  val save_to_file : t -> string -> unit
  (** Save a log to file. *)

  val load_from_file : string -> t
  (** Load a log from file. *)
end

module MakeLog (E : Entry) :
  Log
    with type params = E.params
     and type event = E.event
     and type state = E.state
     and type effect = E.effect
