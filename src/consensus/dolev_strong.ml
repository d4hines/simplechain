open Crypto

module Consensus : Tenderbatter.Simulator.Algorithm = struct
  type message =
    | Block_and_signatures of {
        block : Block.t;
        signatures : Signature.t;
      }
  let message_encoding =
    let open Data_encoding in
    conv
      (fun (Block_and_signatures { block; signatures }) -> (block, signatures))
      (fun (block, signatures) -> Block_and_signatures { block; signatures })
    @@ obj2
         (req "block" Block.encoding)
         (req "signatures" (Signature.encoding list))

  type node_state = int
  type params = { partipants : Participant.t }

  let params_encoding = assert false
  let init_node_state _params _id = assert false
  let node_state_encoding = assert false
end
