include List

let unzip l =
  List.fold_left (fun (al, bl) (a, b) -> (a :: al, b :: bl)) ([], []) l

let shuffle l =
  List.map (fun c -> (Random.bits (), c)) l
  |> List.sort (fun (a, _) (b, _) -> Int.compare a b)
  |> List.map snd
