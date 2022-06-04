open Helpers
open Crypto
open Tenderbatter
module Try = Preface.Try

module type VALUE = sig
  include Map.OrderedType

  val encoding : t Data_encoding.t
  val sign : private_key:Signature.private_key -> t -> BLAKE2B.t Signed.t
  val hash : t -> BLAKE2B.t
end

module Value_and_signatures (Value : VALUE) = struct
  type t = {
    value : Value.t;
    signatures : BLAKE2B.t Signed.t list;
  }

  let verify_signature ~signature value =
    BLAKE2B.equal (Value.hash value) (Signed.get_value signature)
    && Signed.is_valid BLAKE2B.encoding signature

  let get_signatures (_, signatures) : t = signatures

  exception Invalid_signature

  let make ~private_key value =
    let signature = Value.sign ~private_key value in
    { value; signatures = [signature] }

  let is_valid { value; signatures } =
    List.for_all (fun signature -> verify_signature ~signature value) signatures

  let add_signature { value; signatures } private_key =
    if is_valid { value; signatures } then
      let signature = Value.sign ~private_key value in
      Ok { value; signatures = signature :: signatures }
    else
      Try.error
        (Invalid_argument "Refusing to add signature to invalid signature set.")

  let encoding =
    let open Data_encoding in
    conv
      (fun { value; signatures } -> (value, signatures))
      (fun (value, signatures) ->
        (* TODO: I think there's a better way to include validation in Data_encoding
           but I don't remember it. *)
        assert (is_valid { value; signatures });
        { value; signatures })
    @@ obj2
         (req "value" Value.encoding)
         (req "signatures" (list (Signed.encoding BLAKE2B.encoding)))
end
