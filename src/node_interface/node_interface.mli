type config = { self : Participant.t; participants : Participant.t list }
type level = int

module type NODE_INTERFACE = functor
  (Value : Value.VALUE)
  (Networking : Networking.NETWORKING)
  -> sig
  type t

  val self : t -> Participant.t
  val latest_commitment : t -> level * Value.t
  val init : config:config -> Value.t -> t
  val propose_next_value : value:Value.t -> t -> t
end
