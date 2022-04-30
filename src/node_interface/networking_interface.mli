type handler = sender:Participant.t -> message:bytes -> unit
type send = recipient:Participant.t -> message:bytes -> unit

module type NETWORKING = sig
  val register : self:Participant.t -> handler:handler -> send
end
