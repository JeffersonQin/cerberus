open List
open Pp
module Loc=Locations
module SymSet = Set.Make(Sym)


type tag = Tag of Sym.t
type member = Member of string

let pp_tag (Tag s) = 
  Sym.pp s


type t =
  | Unit 
  | Bool
  | Int
  | Loc
  | Array
  | List of t
  | Tuple of t list
  | Struct of tag
  | FunctionPointer of Sym.t


(* TODO *)
let type_equal t1 t2 = t1 = t2

let types_equal ts1 ts2 = 
  for_all (fun (t1,t2) -> type_equal t1 t2) (combine ts1 ts2)

let rec pp atomic = 
  let mparens pped = if atomic then parens pped else pped in
  function
  | Unit -> !^ "unit"
  | Bool -> !^ "bool"
  | Int -> !^ "integer"
  | Loc -> !^ "loc"
  | Array -> !^ "array"
  | List bt -> mparens ((!^ "list") ^^^ pp true bt)
  | Tuple nbts -> mparens (!^ "tuple" ^^^ flow_map (comma ^^ break 1) (pp false) (nbts))
  | Struct (Tag sym) -> 
     mparens (!^"struct" ^^^ Sym.pp sym)
  | FunctionPointer p ->
     parens (!^"function" ^^^ Sym.pp p)



