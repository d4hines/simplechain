(* module Make (Value : Value.VALUE) : sig
     type config = { self : Participant.t; participants : Participant.t list }
     type level = int
     type t = { config : config; latest_commitment : level * Value.t }

     module Side_effect : sig
       type t =
         | Send_to_all of { sender : Participant.t; value : Value.t }
         | Commit of { level : level; value : Value.t }
     end

     val self : t -> Participant.t
     val latest_commitment : t -> level * Value.t
     val init : config:config -> Value.t -> t * Side_effect.t list
     val commit : level:level -> value:Value.t -> t -> t * Side_effect.t list

     val receive_message :
       sender:Participant.t -> value:Value.t -> t -> t * Side_effect.t list
   end *)
