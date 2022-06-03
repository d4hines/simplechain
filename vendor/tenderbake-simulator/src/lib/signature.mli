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

type public_key
(** Public key. *)

type private_key
(** Private key. *)

type 'a t
(** The type of a signature *)

val node_public_key : Node.Id.t -> public_key
(** Public key of any node is assumed to be known. *)

val internal_node_private_key : Node.Id.t -> private_key
(** This function should not be used in simulator code. *)

val make : private_key -> 'a Data_encoding.t -> 'a -> 'a t
(** Sign a piece of information. *)

val signer : 'a t -> Node.Id.t
(** Get node id of the signer. *)

val check : public_key -> 'a Data_encoding.t -> 'a -> 'a t -> bool
(** Check a signature. Arguments: public key, encoding, the value that has
   been signed, signature to check. *)

val encoding : unit -> 'a t Data_encoding.t
(** Encoding of a signature. *)

val equal : 'a t -> 'a t -> bool
(** Equality of signatures. *)
