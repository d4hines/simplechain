open Networking
module Participant_map = Map.Make (Int)

(** A perfect network: all messages are delivered faithfully
    and in order. *)
module Perfect_network : NETWORKING = struct
  let handlers = ref Participant_map.empty
  let message_queue = ref []

  let register ~self ~handler =
    handlers := Participant_map.add self handler !handlers;
    fun ~recipient ~message ->
      let task () =
        let recipient_handler = Participant_map.find recipient !handlers in
        recipient_handler ~sender:self ~message
      in
      message_queue := task :: !message_queue

  let flush () = List.rev !message_queue |> List.iter (fun task -> task ())
end
