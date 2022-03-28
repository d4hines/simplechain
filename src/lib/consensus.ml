module Multiset (Ord : Map.OrderedType) = struct
  module M = Map.Make (Ord)

  type t = int M.t

  let empty = M.empty

  let add s =
    M.update s (function
      | Some count -> Some (count + 1)
      | None -> Some 1)

  let of_list = List.fold_left (fun m x -> add x m) empty
  let count s m =
    match M.find_opt s m with
    | Some count -> count
    | None -> 0

  let majority m =
    M.bindings m
    |> List.fold_left
         (fun (max, max_count) (x, count) ->
           if count > max_count then (x, count) else (max, max_count))
         (M.choose m)
    |> fst
end

let compose f g x = f x |> g
let ( >> ) = compose

module Consensus (Value : Map.OrderedType) = struct
  type round = int
  type participant = int
  module MessageCount = Multiset (Value)
  type message = Value.t * participant

  module Messages = struct
    type t = (Value.t * participant) list
    let make l = l
    let empty = []
    let participants = List.map snd >> List.sort Int.compare
    let count x t =
      List.map fst t |> MessageCount.of_list |> MessageCount.count x
    let majority = List.map fst >> MessageCount.of_list >> MessageCount.majority
    let nth_value n (t : t) = List.nth t n |> fst
    let add x t = x :: t
  end

  type phase_1
  type phase_2
  type locked


  type 'a state = 
  | Phase_1 : locked state -> int -> (phase_1 state)
  | Phase_2 : phase_1 -> 

  let foo (x : phase_1 state) = 
    match x with
    | Phase_1 x -> assert false



  type t = {
    round : int;
    value : Value.t;
    phase_1_messages : Messages.t;
    phase_2_messages : Messages.t;
  }

  let send_phase_1 (state : t) = state.value

  let receive_phase_1 ({ round; value; phase_1_messages; phase_2_messages } : t)
      (message : message) =
    {
      round;
      value;
      phase_1_messages = Messages.add message phase_1_messages;
      phase_2_messages;
    }

  let send_phase_2 (state : t) = Messages.majority state.phase_1_messages

  let receive_phase_2 ({ round; value; phase_1_messages; phase_2_messages } : t)
      (message : message) =
    {
      round;
      value;
      phase_1_messages;
      phase_2_messages = Messages.add message phase_2_messages;
    }

  let decision { round; phase_2_messages; phase_1_messages } s =
    let majority_phase_1 = Messages.majority phase_1_messages in
    let count_phase_1 = Messages.count majority_phase_1 phase_1_messages in

    let value =
      if count_phase_1 >= s then
        majority_phase_1
      else
        Messages.nth_value round phase_2_messages in
    {
      round = round + 1;
      value;
      phase_1_messages = Messages.empty;
      phase_2_messages = Messages.empty;
    }

  let decision (messages : Messages.t) (k : round) =
    let majority_value = Messages.majority messages in
    let majority_count = Messages.count majority_value messages in
    let participants = Messages.participants messages in
    let s = List.length participants * 4 / 5 in
    if majority_count >= s then
      assert false

  let run s participants initial_value =
    let count x k = assert false in
    let rec majority_value x k =
      List.map (fun y -> received_value x y k) participants
      |> MessageCount.of_list
      |> MessageCount.majority
    and decision_value x k =
      if k = 0 then
        initial_value
      else if count x k >= s then (*  *)
        majority_value x k
      else
        majority_value k k
    and received_value _x y k = decision_value y (k - 1) in
    assert false
end
