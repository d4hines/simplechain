module Make (Ord : Map.OrderedType) = struct
  module M = Map.Make (Ord)

  type t = int M.t

  let empty = M.empty

  let add s =
    M.update s (function Some count -> Some (count + 1) | None -> Some 1)

  let of_list = List.fold_left (fun m x -> add x m) empty
  let count s m = match M.find_opt s m with Some count -> count | None -> 0

  let majority m =
    M.bindings m
    |> List.fold_left
         (fun (max, max_count) (x, count) ->
           if count > max_count then (x, count) else (max, max_count))
         (M.choose m)
    |> fst
end
