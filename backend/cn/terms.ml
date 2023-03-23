open Pp
module CT = Sctypes

type lit = 
  | Sym of Sym.t
  | Z of Z.t
  | Q of Q.t
  | Pointer of Z.t
  | Bool of bool
  | Unit
  | Default of BaseTypes.t
  | Null
(* Default bt: equivalent to a unique variable of base type bt, that
   we know nothing about other than Default bt = Default bt *)
[@@deriving eq, ord]

(* over integers and reals *)
type 'bt arith_op =
  | Add of 'bt term * 'bt term
  | Sub of 'bt term * 'bt term
  | Mul of 'bt term * 'bt term
  | MulNoSMT of 'bt term * 'bt term
  | Div of 'bt term * 'bt term
  | DivNoSMT of 'bt term * 'bt term
  | Exp of 'bt term * 'bt term
  | ExpNoSMT of 'bt term * 'bt term
  | Rem of 'bt term * 'bt term
  | RemNoSMT of 'bt term * 'bt term
  | Mod of 'bt term * 'bt term
  | ModNoSMT of 'bt term * 'bt term
  | LT of 'bt term * 'bt term
  | LE of 'bt term * 'bt term
  | Min of 'bt term * 'bt term
  | Max of 'bt term * 'bt term
  | IntToReal of 'bt term
  | RealToInt of 'bt term
  | XORNoSMT of 'bt term * 'bt term

and 'bt bool_op = 
  | And of 'bt term list
  | Or of 'bt term list
  | Impl of 'bt term * 'bt term
  | Not of 'bt term
  | ITE of 'bt term * 'bt term * 'bt term
  | EQ of 'bt term * 'bt term
  | EachI of (int * Sym.t * int) * 'bt term
  (* add Z3's Distinct for separation facts  *)

and 'bt tuple_op = 
  | Tuple of 'bt term list
  | NthTuple of int * 'bt term

and 'bt struct_op =
  | Struct of BaseTypes.tag * (BaseTypes.member * 'bt term) list
  | StructMember of 'bt term * BaseTypes.member
  | StructUpdate of ('bt term * BaseTypes.member) * 'bt term

and 'bt record_op =
  | Record of (Sym.t * 'bt term) list
  | RecordMember of 'bt term * Sym.t
  | RecordUpdate of ('bt term * Sym.t) * 'bt term

and 'bt datatype_op =
  | DatatypeCons of Sym.t * 'bt term
  | DatatypeMember of 'bt term * Sym.t
  | DatatypeIsCons of Sym.t * 'bt term

and 'bt pointer_op = 
  | LTPointer of 'bt term * 'bt term
  | LEPointer of 'bt term * 'bt term
  | IntegerToPointerCast of 'bt term
  | PointerToIntegerCast of 'bt term
  | MemberOffset of BaseTypes.tag * Id.t
  | ArrayOffset of Sctypes.t (*element ct*) * 'bt term (*index*)


and 'bt list_op = 
  | Nil
  | Cons of 'bt term * 'bt term
  | List of 'bt term list
  | Head of 'bt term
  | Tail of 'bt term
  | NthList of 'bt term * 'bt term * 'bt term
  | ArrayToList of 'bt term * 'bt term * 'bt term

and 'bt set_op = 
  | SetMember of 'bt term * 'bt term
  | SetUnion of ('bt term) list
  | SetIntersection of ('bt term) list
  | SetDifference of 'bt term * 'bt term
  | Subset of 'bt term * 'bt term

and 'bt ct_pred = 
  | Representable of Sctypes.t * 'bt term
  | Good of Sctypes.t * 'bt term
  | AlignedI of {t : 'bt term; align : 'bt term}


and 'bt map_op = 
  | MapConst of BaseTypes.t * 'bt term
  | MapSet of 'bt term * 'bt term * 'bt term
  | MapGet of 'bt term * 'bt term
  | MapDef of (Sym.t * BaseTypes.t) * 'bt term

and 'bt term_ =
  | Lit of lit
  | Arith_op of 'bt arith_op
  | Bool_op of 'bt bool_op
  | Tuple_op of 'bt tuple_op
  | Struct_op of 'bt struct_op
  | Record_op of 'bt record_op
  | Datatype_op of 'bt datatype_op
  | Pointer_op of 'bt pointer_op
  | List_op of 'bt list_op
  | Set_op of 'bt set_op
  | CT_pred of 'bt ct_pred
  | Map_op of 'bt map_op
  | Pred of Sym.t * ('bt term) list

and 'bt term =
  | IT of 'bt term_ * 'bt
[@@deriving eq, ord, map]


let equal = equal_term
let compare = compare_term

let pp : 'bt 'a. ?atomic:bool -> ?f:('bt term -> Pp.doc -> Pp.doc) -> 'bt term -> Pp.doc =
  fun ?(atomic=false) ?(f=fun _ x -> x) ->
  let rec aux atomic (IT (it, _) as it_) =
    let aux b x = f x (aux b x) in
    (* Without the `lparen` inside `nest 2`, the printed `rparen` is indented
       by 2 (wrt to the lparen). I don't quite understand it, but it works. *)
    let mparens pped =
      if atomic then
        Pp.group ((nest 2 @@ lparen ^^ break 0 ^^ pped) ^^ break 0 ^^ rparen)
      else
        Pp.group pped in
    let break_op x = break 1 ^^ x ^^ space in
    match it with
    | Lit lit ->
       begin match lit with
       | Sym sym -> Sym.pp sym
       | Z i -> !^(Z.to_string i)
       | Q q -> !^(Q.to_string q)
       | Pointer i ->
          begin match !Pp.loc_pp with
          |  Dec -> !^(Z.to_string i)
          | _ -> !^("0X" ^ (Z.format "016X" i))
          end
       | Bool true -> !^"true"
       | Bool false -> !^"false"
       | Unit -> !^"void"
       | Default bt -> c_app !^"default" [BaseTypes.pp bt]
       | Null -> !^"null"
       end
    | Arith_op arith_op ->
       begin match arith_op with
       | Add (it1,it2) ->
          mparens (flow (break_op plus) [aux true it1; aux true it2])
       | Sub (it1,it2) ->
          mparens (flow (break_op minus) [aux true it1; aux true it2])
       | Mul (it1,it2) ->
          mparens (flow (break_op star) [aux true it1; aux true it2])
       | MulNoSMT (it1,it2) ->
          mparens (c_app !^"mul_uf" [aux true it1; aux true it2])
       | Div (it1,it2) ->
          mparens (flow (break_op slash) [aux true it1; aux true it2])
       | DivNoSMT (it1,it2) ->
          mparens (c_app !^"div_uf" [aux true it1; aux true it2])
       | Exp (it1,it2) ->
          c_app !^"power" [aux true it1; aux true it2]
       | ExpNoSMT (it1,it2) ->
          c_app !^"power_uf" [aux true it1; aux true it2]
       | Rem (it1,it2) ->
          c_app !^"rem" [aux true it1; aux true it2]
       | RemNoSMT (it1,it2) ->
          mparens (c_app !^"rem_uf" [aux true it1; aux true it2])
       | Mod (it1,it2) ->
          c_app !^"mod" [aux true it1; aux true it2]
       | ModNoSMT (it1,it2) ->
          mparens (c_app !^"mod_uf" [aux true it1; aux true it2])
       | LT (o1,o2) ->
          mparens (flow (break_op @@ langle ()) [aux true o1; aux true o2])
       | LE (o1,o2) ->
          mparens (flow (break_op @@ langle () ^^ equals) [aux true o1; aux true o2])
       | Min (o1,o2) ->
          c_app !^"min" [aux false o1; aux false o2]
       | Max (o1,o2) ->
          c_app !^"max" [aux false o1; aux false o2]
       | IntToReal t ->
          c_app !^"intToReal" [aux false t]
       | RealToInt t ->
          c_app !^"realToInt" [aux false t]
       | XORNoSMT (t1, t2) ->
          c_app !^"xor_uf" [aux false t1; aux false t2]
       end
    | Bool_op bool_op ->
       begin match bool_op with
       | And o ->
          let rec consolidate = function
            | IT (Bool_op (And o), _) -> List.concat_map consolidate o
            | it_ -> [ it_ ] in
          let o = consolidate it_ in
          mparens (flow_map (break_op !^"&&") (aux true) o)
       | Or o ->
          let rec consolidate = function
            | IT (Bool_op (Or o), _) -> List.concat_map consolidate o
            | it_ -> [ it_ ] in
          let o = consolidate it_ in
          mparens (flow_map (break_op !^"||") (aux true) o)
       | Impl (o1,o2) ->
          mparens (flow (break_op (equals ^^ rangle ())) [aux true o1; aux true o2])
       | Not (o1) ->
          mparens (!^"!" ^^ parens (aux false o1))
       | ITE (o1,o2,o3) ->
          parens (flow (break 1) [aux true o1; !^"?"; aux true o2; colon; aux true o3])
       | EQ (o1,o2) ->
          mparens (flow (break_op (equals ^^ equals)) [aux true o1; aux true o2])
       | EachI ((i1, s, i2), t) ->
         Pp.(group @@ group (c_app !^"for" [int i1; Sym.pp s; int i2])
             ^/^ group ((nest 2 @@ lbrace ^^ break 0 ^^ (aux false t)) ^^ break 0 ^^ rbrace))
       end
    | Tuple_op tuple_op ->
       begin match tuple_op with
       | NthTuple (n,it2) ->
          mparens (aux true it2 ^^ dot ^^ !^("member" ^ string_of_int n))
       | Tuple its ->
          braces (separate_map (semi ^^ space) (aux false) its)
       end
    | Struct_op struct_op ->
       begin match struct_op with
       | Struct (_tag, members) ->
         align @@ lbrace ^^^ flow_map (break 0 ^^ comma ^^ space) (fun (member,it) ->
             Pp.group @@ (Pp.group @@ dot ^^ Id.pp member ^^^ equals) ^^^ align (aux false it)
           ) members ^^^ rbrace
       | StructMember (t, member) ->
          prefix 0 0 (aux true t) (dot ^^ Id.pp member )
       | StructUpdate ((t, member), v) ->
          mparens (aux true t ^^ braces @@ (Pp.group @@ dot ^^ Id.pp member ^^^ equals) ^^^ align (aux true v))
       end
    | Record_op record_op ->
       begin match record_op with
       | Record members ->
         align @@ lbrace ^^^ flow_map (break 0 ^^ comma ^^ space) (fun (member,it) ->
             Pp.group @@ (Pp.group @@ dot ^^ Sym.pp member ^^^ equals) ^^^ align (aux false it)
           ) members ^^^ rbrace
       | RecordMember (t, member) ->
          prefix 0 0 (aux true t) (dot ^^ Sym.pp member)
       | RecordUpdate ((t, member), v) ->
          mparens (aux true t ^^ braces @@ (Pp.group @@ dot ^^ Sym.pp member ^^^ equals) ^^^ align (aux true v))
       end
    | Datatype_op datatype_op ->
       begin match datatype_op with
       | DatatypeCons (nm, members_rec) -> mparens (Sym.pp nm ^^^ aux false members_rec)
       | DatatypeMember (x, nm) -> aux true x ^^ dot ^^ Sym.pp nm
       | DatatypeIsCons (nm, x) -> mparens (aux false x ^^^ !^ "is" ^^^ Sym.pp nm)
       end
    | Pointer_op pointer_op ->
       begin match pointer_op with
       | LTPointer (o1,o2) ->
          mparens (flow (break_op @@ langle ()) [aux true o1; aux true o2])
       | LEPointer (o1,o2) ->
          mparens (flow (break_op @@ langle () ^^ equals) [aux true o1; aux true o2])
       | IntegerToPointerCast t ->
          mparens (align @@ parens(!^"pointer") ^^ break 0 ^^ aux true t)
       | PointerToIntegerCast t ->
          mparens (align @@ parens(!^"integer") ^^ break 0 ^^ aux true t)
       | MemberOffset (tag, member) ->
          mparens (c_app !^"offsetof" [Sym.pp tag; Id.pp member])
       | ArrayOffset (ct, t) ->
          mparens (c_app !^"arrayOffset" [Sctypes.pp ct; aux false t])
       end
    | CT_pred ct_pred ->
       begin match ct_pred with
       | AlignedI t ->
          c_app !^"aligned" [aux false t.t; aux false t.align]
       | Representable (rt, t) ->
          c_app !^"repr" [CT.pp rt; aux false t]
       | Good (rt, t) ->
          c_app !^"good" [CT.pp rt; aux false t]
       end
    | List_op list_op ->
       begin match list_op with
       | Head (o1) ->
          c_app !^"hd" [aux false o1]
       | Tail (o1) ->
          c_app !^"tl" [aux false o1]
       | Nil ->
          brackets empty
       | Cons (t1,t2) ->
          mparens (aux true t1 ^^ colon ^^ colon ^^ aux true t2)
       | List its ->
          mparens (brackets (separate_map (comma ^^ space) (aux false) its))
       | NthList (n, xs, d) ->
          c_app !^"nth_list" [aux false n; aux false xs; aux false d]
       | ArrayToList (arr, i, len) ->
          c_app !^"array_to_list" [aux false arr; aux false i; aux false len]
       end
    | Set_op set_op ->
       begin match set_op with
       | SetMember (t1,t2) ->
          c_app !^"member" [aux false t1; aux false t2]
       | SetUnion ts ->
          c_app !^"union" (List.map (aux false) ts)
       | SetIntersection ts ->
          c_app !^"intersection" (List.map (aux false) ts)
       | SetDifference (t1, t2) ->
          c_app !^"difference" [aux false t1; aux false t2]
       | Subset (t1, t2) ->
          c_app !^"subset" [aux false t1; aux false t2]
       end
    | Map_op map_op ->
      let rec consolidate ops = function
        | IT (Map_op (MapSet (t1, t2, t3)), _) -> consolidate (`Set (t2, t3) :: ops) t1
        | IT (Map_op (MapGet (t, args)), _) ->  consolidate ((`Get args) :: ops) t
        | it_ -> (it_, ops) in
      let pp_op = function
       | `Set (t2,t3) ->
         Pp.group @@ brackets @@ (aux false t2 ^/^ equals) ^/^ align (aux false t3)
       | `Get args ->
          Pp.group @@ brackets @@ aux false args in
      let (root, ops) = consolidate [] it_ in
      let root_pp = match root with
       | IT (Map_op (MapConst (_, t)), _) ->
          Pp.group @@ brackets @@ aux false t
       | IT (Map_op (MapDef ((s, abt), body)), _) ->
          Pp.group @@ braces (BaseTypes.pp abt ^^^ Sym.pp s ^^^ !^"->" ^^^ aux false body)
       | it_ -> aux true it_
       in
       prefix 2 0 root_pp @@ align (flow_map (break 0) pp_op ops)
    | Pred (name, args) ->
       c_app (Sym.pp name) (List.map (aux false) args)
  in
  fun (it : 'bt term) -> aux atomic it












open Pp_prelude 
open Cerb_frontend.Pp_ast

let rec dtree (IT (it_, bt)) =
  match it_ with
  | Lit (Sym s) -> Dleaf (Sym.pp s)
  | Lit (Z z) -> Dleaf !^(Z.to_string z)
  | Lit (Q q) -> Dleaf !^(Q.to_string q)
  | Lit (Pointer z) -> Dleaf !^(Z.to_string z)
  | Lit (Bool b) -> Dleaf !^(if b then "true" else "false")
  | Lit Unit -> Dleaf !^"unit"
  | Lit (Default _) -> Dleaf !^"default"
  | Lit Null -> Dleaf !^"null"
  | Arith_op (Add (t1, t2)) -> Dnode (pp_ctor "Add", [dtree t1; dtree t2])
  | Arith_op (Sub (t1, t2)) -> Dnode (pp_ctor "Sub", [dtree t1; dtree t2])
  | Arith_op (Mul (t1, t2)) -> Dnode (pp_ctor "Mul", [dtree t1; dtree t2])
  | Arith_op (MulNoSMT (t1, t2)) -> Dnode (pp_ctor "MulNoSMT", [dtree t1; dtree t2])
  | Arith_op (Div (t1, t2)) -> Dnode (pp_ctor "Div", [dtree t1; dtree t2])
  | Arith_op (DivNoSMT (t1, t2)) -> Dnode (pp_ctor "DivNoSMT", [dtree t1; dtree t2])
  | Arith_op (Exp (t1, t2)) -> Dnode (pp_ctor "Exp", [dtree t1; dtree t2])
  | Arith_op (ExpNoSMT (t1, t2)) -> Dnode (pp_ctor "ExpNoSMT", [dtree t1; dtree t2])
  | Arith_op (Rem (t1, t2)) -> Dnode (pp_ctor "Rem", [dtree t1; dtree t2])
  | Arith_op (RemNoSMT (t1, t2)) -> Dnode (pp_ctor "RemNoSMT", [dtree t1; dtree t2])
  | Arith_op (Mod (t1, t2)) -> Dnode (pp_ctor "Mod", [dtree t1; dtree t2])
  | Arith_op (ModNoSMT (t1, t2)) -> Dnode (pp_ctor "ModNoSMT", [dtree t1; dtree t2])
  | Arith_op (LT (t1, t2)) -> Dnode (pp_ctor "LT", [dtree t1; dtree t2])
  | Arith_op (LE (t1, t2)) -> Dnode (pp_ctor "LE", [dtree t1; dtree t2])
  | Arith_op (Min (t1, t2)) -> Dnode (pp_ctor "Min", [dtree t1; dtree t2])
  | Arith_op (Max (t1, t2)) -> Dnode (pp_ctor "Max", [dtree t1; dtree t2])
  | Arith_op (IntToReal t) -> Dnode (pp_ctor "IntToReal", [dtree t])
  | Arith_op (RealToInt t) -> Dnode (pp_ctor "RealToInt", [dtree t])
  | Arith_op (XORNoSMT (t1, t2)) -> Dnode (pp_ctor "XORNoSMT", [dtree t1; dtree t2])
  | Bool_op (And ts) -> Dnode (pp_ctor "And", List.map dtree ts)
  | Bool_op (Or ts) -> Dnode (pp_ctor "Or", List.map dtree ts)
  | Bool_op (Impl (t1, t2)) -> Dnode (pp_ctor "Impl", [dtree t1; dtree t2])
  | Bool_op (Not t) -> Dnode (pp_ctor "Not", [dtree t])
  | Bool_op (ITE (t1, t2, t3)) -> Dnode (pp_ctor "Impl", [dtree t1; dtree t2; dtree t3])
  | Bool_op (EQ (t1, t2)) -> Dnode (pp_ctor "EQ", [dtree t1; dtree t2])
  | Bool_op (EachI ((starti,i,endi), body)) -> Dnode (pp_ctor "EachI", [Dleaf !^(string_of_int starti); Dleaf (Sym.pp i); Dleaf !^(string_of_int endi); dtree body])
  | Tuple_op (Tuple its) -> Dnode (pp_ctor "Tuple", List.map dtree its)
  | Tuple_op (NthTuple (i, t)) -> Dnode (pp_ctor "NthTuple", [Dleaf !^(string_of_int i); dtree t])
  | Struct_op (Struct (tag, members)) ->
     Dnode (pp_ctor ("Struct("^Sym.pp_string tag^")"), List.map (fun (member,e) -> Dnode (pp_ctor "Member", [Dleaf (Id.pp member); dtree e])) members)
  | Struct_op (StructMember (e, member)) ->
     Dnode (pp_ctor "StructMember", [dtree e; Dleaf (Id.pp member)])
  | Struct_op (StructUpdate ((base, member), v)) ->
     Dnode (pp_ctor "StructUpdate", [dtree base; Dleaf (Id.pp member); dtree v])
  | Record_op (Record members) ->
     Dnode (pp_ctor "Record", List.map (fun (member,e) -> Dnode (pp_ctor "Member", [Dleaf (Sym.pp member); dtree e])) members)
  | Record_op (RecordMember (e, member)) ->
     Dnode (pp_ctor "RecordMember", [dtree e; Dleaf (Sym.pp member)])
  | Record_op (RecordUpdate ((base, member), v)) ->
     Dnode (pp_ctor "RecordUpdate", [dtree base; Dleaf (Sym.pp member); dtree v])
  | Datatype_op (DatatypeCons (s, t)) ->
     Dnode (pp_ctor "DatatypeCons", [Dleaf (Sym.pp s); dtree t])
  | Datatype_op (DatatypeMember (t, s)) ->
     Dnode (pp_ctor "DatatypeMember", [dtree t; Dleaf (Sym.pp s)])
  | Datatype_op (DatatypeIsCons (s, t)) ->
     Dnode (pp_ctor "DatatypeIsCons", [Dleaf (Sym.pp s); dtree t])
  | Pointer_op (LTPointer (t1, t2)) -> Dnode (pp_ctor "LTPointer", [dtree t1; dtree t2])
  | Pointer_op (LEPointer (t1, t2)) -> Dnode (pp_ctor "LEPointer", [dtree t1; dtree t2])
  | Pointer_op (IntegerToPointerCast t) -> Dnode (pp_ctor "IntegerToPointerCast", [dtree t])
  | Pointer_op (PointerToIntegerCast t) -> Dnode (pp_ctor "PointerToIntegerCast", [dtree t])
  | Pointer_op (MemberOffset (tag, id)) -> Dnode (pp_ctor "MemberOffset", [Dleaf (Sym.pp tag); Dleaf (Id.pp id)])
  | Pointer_op (ArrayOffset (ty, t)) -> Dnode (pp_ctor "ArrayOffset", [Dleaf (Sctypes.pp ty); dtree t])
  | List_op _ -> failwith "todo"
  | Set_op _ -> failwith "todo"
  | CT_pred (Representable (ty, t)) -> Dnode (pp_ctor "Representable", [Dleaf (Sctypes.pp ty); dtree t])
  | CT_pred (Good (ty, t)) -> Dnode (pp_ctor "Good", [Dleaf (Sctypes.pp ty); dtree t])
  | CT_pred (AlignedI a) -> Dnode (pp_ctor "AlignedI", [dtree a.t; dtree a.align])
  | Map_op (MapConst (bt, t)) -> Dnode (pp_ctor "MapConst", [dtree t])
  | Map_op (MapSet (t1, t2, t3)) -> Dnode (pp_ctor "MapSet", [dtree t1; dtree t2; dtree t3])
  | Map_op (MapGet (t1, t2)) -> Dnode (pp_ctor "MapGet", [dtree t1; dtree t2])
  | Map_op (MapDef ((s, bt), t)) -> Dnode (pp_ctor "MapDef", [Dleaf (Sym.pp s); dtree t])
  | Pred (f, args) -> Dnode (pp_ctor "Pred", (Dleaf (Sym.pp f) :: List.map dtree args))
