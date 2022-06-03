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

open Tenderbatter
module List = List

module Make (A : Simulator.Algorithm) = struct
  include Simulator.Make (A)

  type config = {
    test_name : string;
    params : A.params;
    iterations : int;
    nodes : (int * string * event_handler) list;
    message_delay : Network.Delay.t option;
    predicates : (string * predicate) list;
    seeds : int list;
    final_state_check :
      (Node.Id.t * Time.t option * A.node_state) option array -> bool;
    log_check : Log.t -> bool;
    debug : bool;
  }

  let no_check _ = true

  let ensure_log_dir test_name : string =
    let dir = Filename.concat Filename.current_dir_name (test_name ^ "-logs") in
    (match Sys.file_exists dir && Sys.is_directory dir with
    | true -> ()
    | false -> Unix.mkdir dir 0o700);
    dir

  let unique_txn get_txn_list _ _ node_pool =
    let get_txns x =
      Option.bind x (fun (_, _, state) -> Some (get_txn_list state))
    in
    let seq_txns = Seq.filter_map get_txns @@ Array.to_seq node_pool in
    let folder b txns = b && Transaction.are_unique txns in
    Seq.fold_left folder true seq_txns

  let case config =
    let message_delay = config.message_delay in
    let params = config.params in
    let iterations = config.iterations in
    let nodes = config.nodes in
    let test_name = config.test_name in
    let predicates = config.predicates in

    let test_with_seed seed =
      let log, final_state, pred_results =
        run_simulation ?message_delay ~seed ~predicates ~params ~iterations
          ~nodes ()
      in
      let save_log ~failed =
        let dir = ensure_log_dir test_name in
        let filename =
          Filename.concat dir
          @@ Format.sprintf "seed-%d%s" seed (if failed then "-failed" else "")
        in
        Log.save_to_file log (filename ^ ".json");
        Log.pp_to_file log (filename ^ ".txt")
      in
      if config.debug then save_log ~failed:false;
      let check_predicate (name, failed_at) =
        match failed_at with
        | None -> ()
        | Some i ->
            save_log ~failed:true;
            Alcotest.failf "predicate %s failed at iteration %d (seed %d)" name
              i seed
      in
      List.iter check_predicate pred_results;
      if not (config.final_state_check final_state) then (
        save_log ~failed:true;
        Alcotest.failf "the final state check failed (seed %d)" seed);
      if not (config.log_check log) then (
        save_log ~failed:true;
        Alcotest.failf "the log check failed (seed %d)" seed)
    in
    (test_name, `Slow, fun () -> List.iter test_with_seed config.seeds)
end
