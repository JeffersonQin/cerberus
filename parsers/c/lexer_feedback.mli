(* Created by Victor Gomes 2017-10-04 *)

(* Based on Jacques-Henri Jourdan and Francois Pottier TOPLAS 2017:
   "A simple, possibly correct LR parser for C11" *)

open Cerb_frontend

type context
val save_context: unit -> context
val restore_context: context -> unit

val declare_typedefname: string -> unit
val declare_varname: string -> unit
val is_typedefname: string -> bool

type declarator

val identifier: declarator -> string
val cabs_of_declarator: declarator -> Cabs.declarator

val pointer_decl: Cabs.pointer_declarator -> declarator -> declarator
val identifier_decl: Annot.attributes -> Symbol.identifier -> declarator
val declarator_decl: declarator -> declarator
val array_decl: Cabs.array_declarator -> declarator -> declarator
val fun_decl: Cabs.parameter_type_list -> context -> declarator -> declarator
val fun_ids_decl: Symbol.identifier list -> context -> declarator -> declarator

val reinstall_function_context: declarator -> unit
val create_function_definition: Location_ocaml.t -> ((((Symbol.identifier option * Symbol.identifier) * ((string list) option)) list) list) option -> Cabs.specifiers ->
  declarator -> Cabs.cabs_statement -> Cabs.declaration list option ->
  Cabs.function_definition
