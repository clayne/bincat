(*
    This file is part of BinCAT.
    Copyright 2014-2020 - Airbus

    BinCAT is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published by
    the Free Software Foundation, either version 3 of the License, or (at your
    option) any later version.

    BinCAT is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with BinCAT.  If not, see <http://www.gnu.org/licenses/>.
*)


(* need to have OCaml 4.04 to have it in standard library :( *)
let split_on_char sep str =
  let l = String.length str in
  let rec split p1 p2 =
    if p2 = l then
      [ String.sub str p1 (p2-p1) ]
    else
      if str.[p2] = sep then
        let newsub = String.sub str p1 (p2-p1) in
        newsub :: (split (p2+1) (p2+1))
      else
        split p1 (p2+1) in
  split 0 0;;

(** Z address to hex string, padded using architecture address size *)
let zaddr_to_string zaddr = Z.format !Config.address_format zaddr

(** Z address to hex string, padded using architecture address size,
    starting with 0x *)
let zaddr_to_string0x zaddr = Z.format !Config.address_format0x zaddr


(** log facilities *)

(** fid of the log file *)
let logfid = ref stdout

(** open the given log file *)
let init fname =
  logfid := open_out fname

(** dump a message provided by the analysis step *)
let from_analysis msg = Printf.fprintf (!logfid) "[analysis] %s\n" msg; flush !logfid

(** dump a message produced by the decoding step *)
let from_decoder msg = Printf.fprintf (!logfid) "[decoding] %s\n" msg; flush !logfid

(** dump a message generated by then configuration parsing step *)
let from_config msg = Printf.fprintf !logfid "[config] %s\n" msg; flush !logfid

let stdout_remain = ref ""

(** store the latest analysed address *)
let current_address = ref None

(** store the latest analysed address *)
let latest_finished_address = ref None


module Make(Modname: sig val name : string end) = struct
  let modname = Modname.name

  let _loglvl = ref None

  let loglevel = fun () ->
    match !_loglvl with
    | Some lvl -> lvl
    | None -> let lvl =
        try Hashtbl.find Config.module_loglevel modname
        with Not_found -> !Config.loglevel in
          _loglvl := Some lvl;
          lvl

  let log_debug2 () = loglevel () >= 6
  let log_debug () = loglevel () >= 5
  let log_info2 () = loglevel () >= 4
  let log_info () = loglevel () >= 3
  let log_warn () = loglevel () >= 2
  let log_error () = loglevel () >= 1

  let debug2 fmsg =
    if log_debug2 () then
    let msg = fmsg Printf.sprintf in
    Printf.fprintf !logfid  "[DEBUG2] %s: %s\n" modname msg;
    flush !logfid

  let debug fmsg =
    if log_debug () then
    let msg = fmsg Printf.sprintf in
    Printf.fprintf !logfid  "[DEBUG] %s: %s\n" modname msg;
    flush !logfid

  let trace adrs fmsg =
    if log_info2 () then
      let pc = Data.Address.to_string adrs in
      let msg = fmsg Printf.sprintf in
      let rec log_trace strlist =
        match strlist with
        | [] -> ()
        | h::l ->
           Printf.fprintf !logfid  "[TRACE] %s: %s\n" pc h;
           log_trace l
      in
      log_trace (split_on_char '\n' msg);
    flush !logfid

  let info2 fmsg =
    if log_info2 () then
    let msg = fmsg Printf.sprintf in
    Printf.fprintf !logfid  "[INFO2] %s: %s\n" modname msg;
    flush !logfid

  let info fmsg =
    if log_info () then
    let msg = fmsg Printf.sprintf in
    Printf.fprintf !logfid  "[INFO]  %s: %s\n" modname msg;
    flush !logfid

  let stdout fmsg =
    if log_info() then
      let msg = !stdout_remain ^ (fmsg Printf.sprintf) in
      let rec log_stdout strlist =
        match strlist with
        | [] -> ""
        | [ remain ] -> remain
        | h::l ->
           Printf.fprintf !logfid  "[STDOUT] %s\n" h;
           log_stdout l
      in
      let remain = log_stdout (split_on_char '\n' msg) in
      stdout_remain := remain;
      if remain <> "" then info2 (fun p -> p "line buffered stdout=[%s]" remain);
    flush !logfid


  let warn fmsg =
    if log_warn () then
    let msg = fmsg Printf.sprintf in
    Printf.fprintf !logfid  "[WARN]  %s: %s\n" modname msg;
    flush !logfid

  let error fmsg =
    if log_error () then
      let msg = fmsg Printf.sprintf in
      Printf.fprintf !logfid  "[ERROR] %s: %s\n" modname msg;
      flush !logfid

  let exc e fmsg =
    let msg = fmsg Printf.sprintf in
    Printf.fprintf !logfid  "[EXCEPTION] %s: %s\n" modname msg;
    Printf.fprintf !logfid  "%s\n" (Printexc.to_string e);
    Printexc.print_backtrace !logfid;
    flush !logfid

  let abort fmsg =
    let msg = fmsg Printf.sprintf in
    Printf.fprintf !logfid  "[ABORT] %s: %s\n" modname msg;
    Printexc.print_raw_backtrace !logfid (Printexc.get_callstack 100);
    flush !logfid;

    flush Stdlib.stdout;
    raise (Exceptions.Error msg)

  let exc_and_abort e fmsg =
    let msg = fmsg Printf.sprintf in
    Printf.fprintf !logfid  "[ABORT] %s: %s\n" modname msg;
    Printf.fprintf !logfid  "%s\n" (Printexc.to_string e);
    Printexc.print_backtrace !logfid;
    flush !logfid;
    flush Stdlib.stdout;
    raise (Exceptions.Error msg)


  (* These functions are not submitted to the module specific log level *)
  let analysis fmsg =
    if !Config.loglevel >= 1 then
    let msg = fmsg Printf.sprintf in
    Printf.fprintf !logfid  "[ANALYSIS] %s: %s\n" modname msg;
    flush !logfid

  let decoder fmsg =
    if !Config.loglevel >= 1 then
    let msg = fmsg Printf.sprintf in
    Printf.fprintf !logfid  "[DECODER] %s: %s\n" modname msg;
    flush !logfid

end

module Stdout = Make(struct let name = "stdout" end)
module Trace = Make(struct let name = "trace" end)

(** close the log file *)
let close () =
  if !stdout_remain <> "" then begin Stdout.stdout (fun p -> p "\n") end;
  begin
    match !current_address with
    | None ->  Printf.fprintf !logfid "[STOP] nothing analyzed\n"
    | Some adrs ->
       if !current_address = !latest_finished_address then
         Printf.fprintf !logfid "[STOP] stopped after %s\n" (Data.Address.to_string adrs)
       else
         Printf.fprintf !logfid "[STOP] stopped on %s\n" (Data.Address.to_string adrs)
  end;
  close_out !logfid

(* message management *)
module History =
  struct 
    type t = int
    let compare_msg_id id1 id2 = id1 - id2
    let equal_msg_id id1 id2 = id1 = id2
    let msg_id_tbl: (t, t list * string) Hashtbl.t = Hashtbl.create 5 (* the t list is the list of its ancestors *)
    let msg_id = ref 0
    let compare_msg_id_list l1 l2 =
      let len1 = List.length l1 in
      let len2 = List.length l2 in
      let n = len1 - len2 in
      if n <> 0 then n
      else
        begin
          let n = ref 0 in
          try
            List.iter2 (fun id1 id2 ->
                let r = compare_msg_id id1 id2 in
                if r <> 0 then
                  begin
                    n := r;
                    raise Exit
                  end) l1 l2;
            !n
          with Exit -> !n
        end
      
    let new_ (prev: t list) (msg: string): t =
      let id = !msg_id in
      Hashtbl.add msg_id_tbl id (prev, msg);
      msg_id := !msg_id + 1;
      id

    let rec get_path id: t list list =
      let preds, _msg = Hashtbl.find msg_id_tbl id in
      if preds = [] then
        []
      else
        List.fold_left (fun acc pred ->
            let paths = List.map (fun p -> id::p) (get_path pred) in
            paths @ acc
          ) [] preds

          
      
    let get_msg id =
      let _preds, msg = Hashtbl.find msg_id_tbl id in
      msg
      
  end
