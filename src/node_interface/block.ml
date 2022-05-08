open Crypto
open Tenderbatter

type t = {
  proposer : Node.Id.t;
  transactions : bytes;
  hash : BLAKE2B.t;
  prev_block_hash : BLAKE2B.t;
}

let encoding =
  let open Data_encoding in
  conv
    (fun { proposer; transactions; hash; prev_block_hash } ->
      (proposer, transactions, hash, prev_block_hash))
    (fun (proposer, transactions, hash, prev_block_hash) ->
      { proposer; transactions; hash; prev_block_hash })
  @@ obj4
       (req "proposer" Node.Id.encoding)
       (req "transactions" bytes)
       (req "hash" BLAKE2B.encoding)
       (req "prev_block_hash" BLAKE2B.encoding)
