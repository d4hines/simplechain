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

type 'a t = T of 'a * 'a Signature.t

let make private_key encoding x = T (x, Signature.make private_key encoding x)

let is_valid encoding (T (x, signature)) =
  let signer = Signature.signer signature in
  let public_key = Signature.node_public_key signer in
  Signature.check public_key encoding x signature

let encoding unsigned_encoding =
  let open Data_encoding in
  conv
    (fun (T (x, s)) -> (x, s))
    (fun (x, s) -> T (x, s))
    (obj2
       (req "signed_content" unsigned_encoding)
       (req "signature" (Signature.encoding ())))

let equal f (T (x, xsig)) (T (y, ysig)) = f x y && Signature.equal xsig ysig
let get_value (T (x, _)) = x
let get_signature (T (_, signature)) = signature
