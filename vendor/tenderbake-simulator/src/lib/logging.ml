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

module type Entry = sig
  type params

  val params_encoding : params Data_encoding.t

  type event

  val event_encoding : event Data_encoding.t

  type state

  val state_encoding : state Data_encoding.t

  type effect

  val effect_encoding : effect Data_encoding.t
end

module type Log = sig
  type params
  type event
  type state
  type effect

  module Entry : sig
    type t = {
      time : Time.t;
      iteration : int;
      event : event;
      init_state : state;
      new_state : state;
      effects : effect list;
    }

    val encoding : t Data_encoding.t
  end

  type t = { params : params; mutable entries : Entry.t Queue.t }

  val encoding : t Data_encoding.t
  val create : params -> t

  val log :
    formatter:Format.formatter option ->
    time:Time.t ->
    iteration:int ->
    event:event ->
    init_state:state ->
    new_state:state ->
    effects:effect list ->
    t ->
    unit

  val pp : Format.formatter -> t -> unit
  val pp_to_file : t -> string -> unit
  val save_to_file : t -> string -> unit
  val load_from_file : string -> t
end

let rec pp_json ppf json =
  let open Format in
  match json with
  | `Null -> pp_print_string ppf "null"
  | `String s -> fprintf ppf "\"%s\"" s
  | `Float f ->
      if Float.is_integer f then fprintf ppf "%.0f" f else fprintf ppf "%.4f" f
  | `Bool true -> pp_print_string ppf "true"
  | `Bool false -> pp_print_string ppf "false"
  | `A [] -> pp_print_string ppf "<empty list>"
  | `A xs ->
      pp_open_vbox ppf 0;
      pp_print_list ~pp_sep:pp_print_cut
        (fun ppf v -> fprintf ppf "@[<v 2>- %a@]" pp_json v)
        ppf xs;
      pp_close_box ppf ()
  | `O [] -> pp_print_string ppf "<empty object>"
  | `O xs ->
      pp_open_vbox ppf 0;
      let get_signer_opt = function
        | `O ps -> List.assoc_opt "signer" ps
        | _ -> None
      in
      pp_print_list ~pp_sep:pp_print_cut
        (fun ppf (s, v) ->
          match v with
          | `A (_ :: _) -> fprintf ppf "@[<v 2>%s:@,%a@]" s pp_json v
          | `O (_ :: _) -> fprintf ppf "@[<v 2>%s:@,%a@]" s pp_json v
          | _ -> fprintf ppf "@[<v 2>%s: %a@]" s pp_json v)
        ppf
        (List.map
           (fun (s, x) ->
             if String.equal "signature" s then
               match get_signer_opt x with
               | None -> (s, x)
               | Some signer -> ("signer", signer)
             else (s, x))
           xs);
      pp_close_box ppf ()

module MakeLog (E : Entry) = struct
  type params = E.params
  type event = E.event
  type state = E.state
  type effect = E.effect

  module Entry = struct
    type t = {
      time : Time.t;
      iteration : int;
      event : event;
      init_state : state;
      new_state : state;
      effects : effect list;
    }

    let encoding =
      let open Data_encoding in
      conv
        (fun { time; iteration; event; init_state; new_state; effects } ->
          (time, iteration, event, init_state, new_state, effects))
        (fun (time, iteration, event, init_state, new_state, effects) ->
          { time; iteration; event; init_state; new_state; effects })
      @@ obj6 (req "time" Time.encoding) (req "iteration" int31)
           (req "event" E.event_encoding)
           (req "init_state" E.state_encoding)
           (req "new_state" E.state_encoding)
           (req "effects" (list E.effect_encoding))
  end

  type t = { params : params; mutable entries : Entry.t Queue.t }

  let encoding =
    let open Data_encoding in
    conv
      (fun { params; entries } -> (params, Utils.Queue.to_list entries))
      (fun (params, entries) ->
        { params; entries = Utils.Queue.of_list entries })
      (obj2
         (req "params" E.params_encoding)
         (req "entries" (list Entry.encoding)))

  let create params = { params; entries = Queue.create () }

  let log ~formatter ~time ~iteration ~event ~init_state ~new_state ~effects log
      =
    let new_entry =
      { Entry.time; iteration; event; init_state; new_state; effects }
    in
    (match formatter with
    | Some ppf ->
        pp_json ppf (Data_encoding.Json.construct Entry.encoding new_entry);
        Format.pp_force_newline ppf ();
        Format.pp_force_newline ppf ()
    | None -> ());
    Queue.add new_entry log.entries

  let pp ppf log =
    let entries = ref (Utils.Queue.to_list log.entries) in
    let all_done = ref false in
    while not !all_done do
      match !entries with
      | [] -> all_done := true
      | entry :: rest ->
          pp_json ppf (Data_encoding.Json.construct Entry.encoding entry);
          Format.pp_force_newline ppf ();
          Format.pp_force_newline ppf ();
          entries := rest
    done;
    Format.pp_print_flush ppf ()

  let pp_to_file log path =
    let oc = open_out path in
    pp (Format.formatter_of_out_channel oc) log;
    close_out oc

  let save_to_file log path =
    let oc = open_out path in
    Ezjsonm.to_channel ~minify:false oc
      (match Data_encoding.Json.construct encoding log with
      | `O x -> `O x
      | _ -> failwith "JSON serialization of the log must be an object");
    close_out oc

  let load_from_file path =
    let ic = open_in path in
    let log = Data_encoding.Json.destruct encoding (Ezjsonm.from_channel ic) in
    close_in ic;
    log
end
