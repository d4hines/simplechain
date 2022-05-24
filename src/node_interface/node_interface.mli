open Value
open Networking_interface

type config = {
  self : Participant.t;
  participants : Participant.t list;
}

type level = int

module type NODE_FUNCTOR = functor
  (Value : VALUE)
  (Networking : NETWORKING)
  -> sig
  type t

  val self : t -> Participant.t
  val latest_commitment : t -> level * Value.t
  val init : config:config -> Value.t -> t
  val propose_next_value : value:Value.t -> t -> unit

  (* Exact same interface as above
     TODO: figure out a way to properly abstract the interface of a node. *)
  module Byzantine : sig
    type t

    val self : t -> Participant.t
    val latest_commitment : t -> level * Value.t
    val init : config:config -> Value.t -> t
    val propose_next_value : value:Value.t -> t -> unit
  end
end

module type NODE_INTERFACE = sig
  module Make : NODE_FUNCTOR
end
