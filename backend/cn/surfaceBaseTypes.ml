(* copy of baseTypes.ml, adjusted *)

open Pp

type basetype =
  | Unit 
  | Bool
  | Integer
  | Real
  | CType
  | Loc of Sctypes.t option
  | Struct of Sym.t
  | Datatype of Sym.t
  | Record of member_types
  | Map of basetype * basetype
  | List of basetype
  | Tuple of basetype list
  | Set of basetype
  (* | Option of basetype *)
[@@deriving eq, ord]

and member_types =
  (Id.t * basetype) list


type t = basetype


let equal = equal_basetype
let compare = compare_basetype


type datatype_info = {
  dt_constrs: Sym.t list;
  dt_all_params: member_types;
}
type constr_info = {
  c_params: member_types;
  c_datatype_tag: Sym.t
}

let cons_dom_rng info =
  (Record info.c_params, Datatype info.c_datatype_tag)


let rec pp = function
  | Unit -> !^"void"
  | Bool -> !^"bool"
  | Integer -> !^"integer"
  | Real -> !^"real"
  | CType -> !^"ctype"
  | Loc (Some ct) -> !^"pointer" ^^ angles (Sctypes.pp ct)
  | Loc None -> !^"pointer"
  | Struct sym -> !^"struct" ^^^ Sym.pp sym
  | Datatype sym -> !^"datatype" ^^^ Sym.pp sym
  | Record members -> braces (flow_map comma (fun (s, bt) -> pp bt ^^^ Id.pp s) members)
  | Map (abt, rbt) -> !^"map" ^^ angles (pp abt ^^ comma ^^^ pp rbt)
  | List bt -> !^"list" ^^ angles (pp bt)
  | Tuple nbts -> !^"tuple" ^^ angles (flow_map comma pp nbts)
  | Set t -> !^"set" ^^ angles (pp t)
  (* | Option t -> !^"option" ^^ angles (pp t) *)



let json bt : Yojson.Safe.t =
  `String (Pp.plain (pp bt))




let struct_bt = function
  | Struct tag -> tag 
  | bt -> Debug_ocaml.error 
           ("illtyped index term: not a struct type: " ^ Pp.plain (pp bt))

let record_bt = function
  | Record members -> members
  | bt -> Debug_ocaml.error 
           ("illtyped index term: not a member type: " ^ Pp.plain (pp bt))

let is_map_bt = function
  | Map (abt, rbt) -> Some (abt, rbt)
  | _ -> None

let map_bt = function
  | Map (abt, rbt) -> (abt, rbt) 
  | bt -> Debug_ocaml.error 
           ("illtyped index term: not a map type: " ^ Pp.plain (pp bt))

let is_datatype_bt = function
  | Datatype sym -> Some sym
  | _ -> None


let make_map_bt abt rbt = Map (abt, rbt)




let rec of_sct = function
  | Sctypes.Void -> Unit
  | Integer _ -> Integer
  | Array (sct, _) -> Map (Integer, of_sct sct)
  | Pointer ct -> Loc (Some ct)
  | Struct tag -> Struct tag
  | Function _ -> Debug_ocaml.error "todo: function types"


module BT = BaseTypes

let rec of_basetype = function
  | BT.Unit -> Unit
  | BT.Bool -> Bool
  | BT.Integer -> Integer
  | BT.Real -> Real
  | BT.CType -> CType
  | BT.Loc -> Loc None
  | BT.Struct tag -> Struct tag
  | BT.Datatype tag -> Datatype tag
  | BT.Record member_types -> Record (List.map_snd of_basetype member_types)
  | BT.Map (bt1, bt2) -> Map (of_basetype bt1, of_basetype bt2)
  | BT.List bt -> List (of_basetype bt)
  | BT.Tuple bts -> Tuple (List.map of_basetype bts)
  | BT.Set bt -> Set (of_basetype bt)


let rec to_basetype = function
  | Unit -> BT.Unit
  | Bool -> BT.Bool
  | Integer -> BT.Integer
  | Real -> BT.Real
  | CType -> BT.CType
  | Loc _ -> BT.Loc
  | Struct tag -> BT.Struct tag
  | Datatype tag -> BT.Datatype tag
  | Record member_types -> BT.Record (List.map_snd to_basetype member_types)
  | Map (bt1, bt2) -> BT.Map (to_basetype bt1, to_basetype bt2)
  | List bt -> BT.List (to_basetype bt)
  | Tuple bts -> BT.Tuple (List.map to_basetype bts)
  | Set bt -> BT.Set (to_basetype bt)
