open Node_interface
open Networking_interface

module Make
    (Value : Value.VALUE)
    (* Degenerate consensus completely ignores the network,
       but we keep it as part of the signature for compatibility *)
    (Networking : NETWORKING) =
struct
  type t = { config : config }

  let self t = t.config.self
  let latest_commitment _ = (0, Value.default)
  let init ~config _ = { config }
  let propose_next_value ~value:_ _ = ()

  module Byzantine = struct
    type t = { config : config }

    let self t = t.config.self

    (* This is the key place where we inject randomness.
       Not that it matters: even honest degenerate nodes don't care
       what anyone else says. *)
    let latest_commitment _ = (0, Value.random ())
    let init ~config _ = { config }
    let propose_next_value ~value:_ _ = ()
  end
end
