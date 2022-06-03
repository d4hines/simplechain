(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021 Nomadic Labs, <contact@nomadic-labs.com>               *)
(*                                                                           *)
(* Permission is hereby granted, free of charge, to any person obtaining a   *)
(* copy of this software and associated documentation files (the "Software"),*)
(* to deal in the Software without restriction, including without limitation *)
(* the rights to use, copy, modify, merge, publish, distribute, sublicense,  *)
(* and/or sell copies of the Software, and to permit persons to whom the     *)
(* Software is furnished to do so, subject to the following conditions:      *)
(*                                                                           *)
(* The above copyright notice and this permission notice shall be included   *)
(* in all copies or substantial portions of the Software.                    *)
(*                                                                           *)
(* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR*)
(* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,  *)
(* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL   *)
(* THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER*)
(* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING   *)
(* FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER       *)
(* DEALINGS IN THE SOFTWARE.                                                 *)
(*                                                                           *)
(*****************************************************************************)

type public_key = Public_key of Node.Id.t
type private_key = Private_key of Node.Id.t
type 'a t = Signature of 'a Hash.t * private_key

let node_public_key node_id = Public_key node_id
let internal_node_private_key node_id = Private_key node_id
let make private_key encoding x = Signature (Hash.make encoding x, private_key)
let signer (Signature (_, Private_key node_id)) = node_id

let check (Public_key k) encoding x (Signature (hash, Private_key k')) =
  Hash.equal (Hash.make encoding x) hash
  && Int.equal (Node.Id.to_int k) (Node.Id.to_int k')

let encoding () =
  let open Data_encoding in
  conv
    (fun (Signature (h, Private_key n)) -> (h, n))
    (fun (h, n) -> Signature (h, Private_key n))
    (obj2 (req "hash" (Hash.encoding ())) (req "signer" Node.Id.encoding))

let equal (Signature (xh, Private_key xk)) (Signature (yh, Private_key yk)) =
  Hash.equal xh yh && Node.Id.equal xk yk
