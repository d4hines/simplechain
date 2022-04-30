open Node_interface
open Networking_interface

module Make
    (Consensus : NODE_INTERFACE)
    (Value : Value.VALUE)
    (Networking : NETWORKING) =
struct
  module Honest = Consensus.Make (Value) (Networking)
  module Byzantine = Honest.Byzantine

  type t = Honest of Honest.t | Byzantine of Byzantine.t

  let self = function
    | Honest t -> Honest.self t
    | Byzantine t -> Byzantine.self t

  let is_honest = function Honest _ -> true | Byzantine _ -> false

  let latest_commitment = function
    | Honest t -> Honest.latest_commitment t
    | Byzantine t -> Byzantine.latest_commitment t

  let propose_next_value ~value = function
    | Honest t -> Honest.propose_next_value ~value t
    | Byzantine t -> Byzantine.propose_next_value ~value t

  let init_network ~honest_nodes ~byzantine_nodes init_fn =
    let participants = List.init (honest_nodes + byzantine_nodes) Fun.id in
    List.init honest_nodes (fun _ -> true)
    @ List.init byzantine_nodes (fun _ -> false)
    |> List.shuffle
    |> List.mapi (fun id honest ->
           let config = Node_interface.{ self = id; participants } in
           let init_value = init_fn id in
           if honest then Honest (Honest.init ~config init_value)
           else Byzantine (Byzantine.init ~config init_value))
end
