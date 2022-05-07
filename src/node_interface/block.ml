open Digestif
open Tenderbatter

type t = {
  proposer : Node.Id.t;
  transactions : bytes;
  hash : BLAKE2B.t;
  prev_block_hash : BLAKE2B.t;
}

module type M_type = sig
  val hash : string -> 'a
  (* etc. *)
end

let foo (module M : M_type) = 
  let open M in
  hash "hello"