open Crypto
open Tenderbatter

type t = {
  transactions : Transaction.t list;
  (* FIXME: in dolov-strong implementation, I only use level
     as an implementation detail to figure out next block proposer.
     We could get around this and omit - prev_block_hash is "enough" I think. *)
  level : int64;
  hash : BLAKE2B.t;
  prev_block_hash : BLAKE2B.t;
}

let hash ~transactions ~level ~prev_block_hash =
  let bytes =
    (* MY FAVORITE MODULE *)
    Marshal.to_bytes (transactions, level, prev_block_hash) []
  in
  BLAKE2B.hash (Bytes.to_string bytes)

let make ~transactions ~level ~prev_block_hash =
  let hash = hash ~transactions ~level ~prev_block_hash in
  { transactions; level; hash; prev_block_hash }

let empty ~level ~prev_block_hash =
  make ~transactions:[] ~level ~prev_block_hash

let genesis =
  {
    transactions = [];
    level = 0L;
    hash = BLAKE2B.hash "Shikamaru";
    prev_block_hash = BLAKE2B.hash "Nara Clan";
  }

let encoding =
  let open Data_encoding in
  conv
    (fun { transactions; level; hash; prev_block_hash } ->
      (transactions, level, hash, prev_block_hash))
    (fun (transactions, level, actual_hash, prev_block_hash) ->
      let expected_hash = hash ~transactions ~level ~prev_block_hash in
      (* TODO: I think there's a better way to include validation in Data_encoding
         but I don't remember it. *)
      assert (BLAKE2B.equal actual_hash expected_hash);
      { transactions; level; hash = actual_hash; prev_block_hash })
  @@ obj4
       (req "transactions" (list Transaction.encoding))
       (req "level" int64)
       (req "hash" BLAKE2B.encoding)
       (req "prev_block_hash" BLAKE2B.encoding)

let compare a b = BLAKE2B.compare a.hash b.hash
let sign block private_key = Signed.make private_key BLAKE2B.encoding block.hash

let is_next_block ~current ~next =
  BLAKE2B.equal next.prev_block_hash current.hash
  && next.level = Int64.add current.level 1L
