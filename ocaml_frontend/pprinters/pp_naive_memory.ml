(************************************************************************************)
(*  BSD 2-Clause License                                                            *)
(*                                                                                  *)
(*  Cerberus                                                                        *)
(*                                                                                  *)
(*  Copyright (c) 2011-2020                                                         *)
(*    Kayvan Memarian                                                               *)
(*    Victor Gomes                                                                  *)
(*    Justus Matthiesen                                                             *)
(*    Peter Sewell                                                                  *)
(*    Kyndylan Nienhuis                                                             *)
(*    Stella Lau                                                                    *)
(*    Jean Pichon-Pharabod                                                          *)
(*    Christopher Pulte                                                             *)
(*    Rodolphe Lepigre                                                              *)
(*    James Lingard                                                                 *)
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

open Naive_memory
open Pp_prelude

(* Use this to pprint things not yet recognised by the Core parser *)
let nonvalid =
  P.enclose (!^ "{#") (!^ "#}")



let pp_pointer_shift ptr_sh =
  let rec aux = function
    | [] ->
        P.empty
    | (ty, n) :: ptr_sh' ->
        Pp_core_ctype.pp_ctype ty ^^^ !^ "x" ^^^ !^ (Nat_big_num.to_string n) ^^ P.comma ^^^
        aux ptr_sh'
  in
  P.brackets (aux ptr_sh)


let pp_pointer_value_aux is_nonvalid ptr_val =
  (if is_nonvalid then (fun z -> z) else nonvalid)
  (match ptr_val with
    | PVnull0 ty ->
        !^ "nullptr" ^^ P.parens (Pp_core_ctype.pp_ctype ty)
    | PVobject ((n, pref), ptr_sh) ->
        !^ ("@" ^ string_of_int n) ^^ pp_pointer_shift ptr_sh ^^ P.braces (Pp_symbol.pp_prefix pref)
    | PVfunction0 sym ->
        !^ "funptr" ^^ P.parens (!^ (Pp_symbol.to_string_pretty sym)))

let pp_pointer_value =
  pp_pointer_value_aux false


let string_of_integer_operator = function
  | Mem_common.IntAdd ->
      "+"
  | Mem_common.IntSub ->
      "-"
  | Mem_common.IntMul ->
      "*"
  | Mem_common.IntDiv ->
      "/"
  | Mem_common.IntMod ->
      "mod"
  | Mem_common.IntExp ->
      "^"

let pp_integer_value =
  let rec aux is_nonvalid ival =
    let nonvalid = if is_nonvalid then fun z -> z else nonvalid in
    match ival with
      | IVinteger n ->
          !^ (Nat_big_num.to_string n)
      | IVsymbolic symb ->
          nonvalid (Pp_symbolic.pp_symbolic symb)
      | IVptrdiff0 (ptr_val1, ptr_val2) ->
          nonvalid (
            !^ "ptrdiff" ^^ P.parens (
              pp_pointer_value ptr_val1 ^^ P.comma ^^^ pp_pointer_value ptr_val2
            )
          )
      | IVintptr ptr_val ->
          nonvalid (
            !^ "intptr" ^^ P.parens (
              pp_pointer_value ptr_val
            )
          )
      | IVop0 (iop, ival1, ival2) ->
        aux is_nonvalid ival1 ^^^ !^ (string_of_integer_operator iop) ^^^ aux is_nonvalid ival2
  in aux false


(*





  Mem.case_mem_value mval
    (fun ty ->
      
    (fun ival ->
      Mem.case_integer_value ival
        (fun n ->
          
        ( fun _ ->
          !^ "TODO(MVinteger SYMB_integer_value)")
        (fun () ->
          !^ "TODO(complex ival)")
    )
    (fun str ->
      !^ ("TODO(MVfloation " ^ str ^ ")"))
    (fun ptr_val ->
(*
  | Mem.MVpointer (Mem.PVobject ((n, pref), ptr_sh)) ->
      !^ ("@" ^ string_of_int n) ^^ pp_pointer_shift ptr_sh ^^ P.braces (pp_prefix pref)
  | Mem.MVpointer ptr_val ->
      !^ "TODO(MVpointer)" 
*)
      failwith "WIP"
      )
    (fun mvals ->
      
    (fun tag ident_mvals ->
      
   (fun _ _ _ ->
     !^ "TODO(MVunion)")
*)



let rec pp_mem_value = function
  | MVunspecified0 ty ->
      !^ "unspec" ^^ P.parens (Pp_core_ctype.pp_ctype ty)
  | MVinteger0 ival ->
      pp_integer_value ival
  | MVfloating0 str ->
      !^ str
  | MVpointer0 ptr_val ->
      pp_pointer_value ptr_val
  | MVarray0 mvals ->
      !^ "array" ^^ P.parens (comma_list pp_mem_value mvals)
  | MVstruct0 (tag_sym, xs) ->
      P.parens (
        !^ "struct" ^^^ !^ (Pp_symbol.to_string_pretty tag_sym)
     ) ^^^
     P.braces (
      comma_list (fun (mb_ident, mval) ->
        P.dot ^^ Pp_cabs.pp_cabs_identifier mb_ident ^^ P.equals ^^^ pp_mem_value mval
      ) xs
     )
  | MVunion0 (tag_sym, mb_ident, mval) ->
      P.parens (
        !^ "union" ^^^ !^ (Pp_symbol.to_string_pretty tag_sym)
      ) ^^^
      P.braces (
        P.dot ^^ Pp_cabs.pp_cabs_identifier mb_ident ^^ P.equals ^^^ pp_mem_value mval
      )
