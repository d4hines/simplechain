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

open Crowbar
open Tenderbatter

type test_kit = Kit of int32 * Signature.public_key * Signature.private_key

let gen_kit : test_kit gen =
  let ( >>= ) g f = dynamic_bind g f in
  int32 >>= fun message ->
  int >>= fun n ->
  let node_id = Node.Id.make "foo" n in
  const
    (Kit
       ( message,
         Signature.node_public_key node_id,
         Signature.internal_node_private_key node_id ))

let checkTrue (Kit (message, public_key, private_key)) =
  check
  @@ Signature.check public_key Data_encoding.int32 message
       (Signature.make private_key Data_encoding.int32 message)

let checkFalseMsg (Kit (message, public_key, private_key)) =
  check @@ not
  @@ Signature.check public_key Data_encoding.int32
       (Int32.add message Int32.one)
       (Signature.make private_key Data_encoding.int32 message)

let checkFalseSender (Kit (message, _, private_key)) =
  let node_id = 0 in
  let fake_public_key =
    Signature.node_public_key (Node.Id.make "foo" node_id)
  in
  let signed = Signature.make private_key Data_encoding.int32 message in
  guard (not (Int.equal (Node.Id.to_int (Signature.signer signed)) node_id));
  check @@ not
  @@ Signature.check fake_public_key Data_encoding.int32 message signed

let test () =
  add_test ~name:"check true if truly signed" [ gen_kit ] checkTrue;
  add_test ~name:"check false if wrong message" [ gen_kit ] checkFalseMsg;
  add_test ~name:"check false if wrong sender" [ gen_kit ] checkFalseSender
