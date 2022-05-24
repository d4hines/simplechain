open Helpers
open Crypto
open Tenderbatter
module Try = Preface.Try

type t = {
  block : Block.t;
  signatures : BLAKE2B.t Signed.t list;
}

let get_signatures (_, signatures) : t = signatures

exception Invalid_signature

let make block private_key =
  let signature = Signed.make private_key BLAKE2B.encoding block.Block.hash in
  { block; signatures = [signature] }

let add_signature { block; signatures } private_key =
  let signature = Signed.make private_key BLAKE2B.encoding block.Block.hash in
  { block; signatures = signature :: signatures }

let is_valid { block; signatures } =
  List.for_all
    (fun signature ->
      BLAKE2B.equal block.hash (Signed.get_value signature)
      && Signed.is_valid BLAKE2B.encoding signature)
    signatures

let encoding =
  let open Data_encoding in
  conv
    (fun { block; signatures } -> (block, signatures))
    (fun (block, signatures) ->
      (* TODO: I think there's a better way to include validation in Data_encoding
         but I don't remember it. *)
      assert (is_valid { block; signatures });
      { block; signatures })
  @@ obj2
       (req "block" Block.encoding)
       (req "signatures" (list (Signed.encoding BLAKE2B.encoding)))

let compare a b = Block.compare a.block b.block
