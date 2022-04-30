open Node_interface

module Make (Value : Value.VALUE) (Networking : Networking.NETWORKING) = struct
  type t = { config : config }

  let self t = t.config.self
  let latest_commitment _ = (0, Value.default)
  let init ~config _ = { config }
  let propose_next_value ~value:_ t = t
end
