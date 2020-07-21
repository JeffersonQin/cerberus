(************************************************************************************)
(*  BSD 2-Clause License                                                            *)
(*                                                                                  *)
(*  Cerberus                                                                        *)
(*                                                                                  *)
(*  Copyright (c) 2011-2020                                                         *)
(*    Victor Gomes                                                                  *)
(*                                                                                  *)
(*  All rights reserved.                                                            *)
(*                                                                                  *)
(*  Redistribution and use in source and binary forms, with or without              *)
(*  modification, are permitted provided that the following conditions are met:     *)
(*                                                                                  *)
(*  1. Redistributions of source code must retain the above copyright notice, this  *)
(*     list of conditions and the following disclaimer.                             *)
(*                                                                                  *)
(*  2. Redistributions in binary form must reproduce the above copyright notice,    *)
(*     this list of conditions and the following disclaimer in the documentation    *)
(*     and/or other materials provided with the distribution.                       *)
(*                                                                                  *)
(*  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"     *)
(*  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE       *)
(*  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE  *)
(*  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE    *)
(*  FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL      *)
(*  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR      *)
(*  SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER      *)
(*  CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,   *)
(*  OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE   *)
(*  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.            *)
(************************************************************************************)

open Sibylfs

module N = Nat_big_num

type fs =
  | File of string * Bytes.t * int * Unix.file_perm
  | Dir of string * fs array * Unix.file_perm

let contents file size =
  let ic = open_in file in
  let buf = Bytes.create size in
  really_input ic buf 0 size;
  close_in ic;
  buf

let rec fs_read dir =
  let files = Sys.readdir dir in
  Unix.chdir dir;
  Array.map (fun file ->
     let stats = Unix.stat file in
     if stats.st_kind = S_DIR then
       let content = fs_read file in
       let () = Unix.chdir ".." in
       Dir (file, content, stats.st_perm)
     else
       File (file, contents file stats.st_size, stats.st_size, stats.st_perm)
    ) files

let force (st, res) =
  match res with
  | Either.Right x -> (st, N.of_int x)
  | Either.Left _ -> assert false

let explode bs =
  let rec exp a b =
    if a < 0 then b
    else exp (a - 1) (Bytes.get bs a :: b)
  in
  exp (Bytes.length bs - 1) []

let rec fs_write st =
  let open_flag = Nat_big_num.of_int 0O50 (* O_CREAT | O_RDWR *) in
  function
  | File (name, content, size, perm) ->
    let (st, fd) = force @@ run_open st name open_flag (Some (N.of_int perm)) in
    let (st, _) = run_write st fd (explode content) (N.of_int size) in
    let (st, _) = run_close st fd in
    st
  | Dir (name, contents, perm) ->
    let (st, _) = run_mkdir st name (N.of_int perm) in
    let (st, _) = run_chdir st name in
    let st = Array.fold_left fs_write st contents in
    let (st, _) = run_chdir st ".." in
    st

let initialise root =
  let cur = Unix.getcwd () in
  Unix.chdir root;
  let st = Array.fold_left fs_write fs_initial_state @@ fs_read root in
  Unix.chdir cur;
  st
