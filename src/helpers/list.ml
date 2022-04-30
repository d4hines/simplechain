include List

let unzip l =
  List.fold_left (fun (al, bl) (a, b) -> (a :: al, b :: bl)) ([], []) l
