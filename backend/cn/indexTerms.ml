open List
module BT=BaseTypes
module CF=Cerb_frontend
module SymSet = Set.Make(Sym)
module SymMap = Map.Make(Sym)
open Subst


include Terms

let equal = equal_term BT.equal
let compare = compare_term BT.compare


type sterm = SurfaceBaseTypes.t term
type typed = BT.t term
type t = BT.t term



let basetype (IT (_, bt)) = bt
let bt = basetype

let term (IT (t, _)) = t


let term_of_sterm : sterm -> typed = 
  Terms.map_term SurfaceBaseTypes.to_basetype

let sterm_of_term : typed -> sterm = 
  Terms.map_term SurfaceBaseTypes.of_basetype


let pp ?(atomic=false) =
  Terms.pp ~atomic




let rec free_vars_ = function
  | Const _ -> SymSet.empty
  | Sym s -> SymSet.singleton s
  | Binop (_bop, t1, t2) -> free_vars_list [t1; t2]
  | Not t1 -> free_vars t1
  | ITE (t1, t2, t3) -> free_vars_list [t1; t2; t3]
  | EachI ((_, s, _), t) -> SymSet.remove s (free_vars t)
  | Tuple ts -> free_vars_list ts
  | NthTuple (_, t) -> free_vars t
  | Struct (_tag, members) -> free_vars_list (List.map snd members)
  | StructMember (t, _member) -> free_vars t
  | StructUpdate ((t1, _member), t2) -> free_vars_list [t1; t2]
  | Record members -> free_vars_list (List.map snd members)
  | RecordMember (t, _member) -> free_vars t
  | RecordUpdate ((t1, _member), t2) -> free_vars_list [t1; t2]
  | DatatypeCons (tag, members_xs) -> free_vars members_xs
  | DatatypeMember (t, member) -> free_vars t
  | DatatypeIsCons (tag, t) -> free_vars t
  | Cast (_cbt, t) -> free_vars t
  | MemberOffset (_tag, _id) -> SymSet.empty
  | ArrayOffset (_sct, t) -> free_vars t
  | Nil -> SymSet.empty
  | Cons (t1, t2) -> free_vars_list [t1; t2]
  | List ts -> free_vars_list ts
  | Head t -> free_vars t
  | Tail t -> free_vars t
  | NthList (i, xs, d) -> free_vars_list [i; xs; d]
  | ArrayToList (arr, i, len) -> free_vars_list [arr; i; len]
  | Representable (_sct, t) -> free_vars t
  | Good (_sct, t) -> free_vars t
  | Aligned {t; align} -> free_vars_list [t; align]
  | MapConst (_bt, t) -> free_vars t
  | MapSet (t1, t2, t3) -> free_vars_list [t1; t2; t3]
  | MapGet (t1, t2) -> free_vars_list [t1; t2]
  | MapDef ((s, _bt), t) -> SymSet.remove s (free_vars t)
  | Apply (_pred, ts) -> free_vars_list ts

and free_vars (IT (term_, _bt)) =
  free_vars_ term_

and free_vars_list xs =
  List.fold_left (fun ss t ->
      SymSet.union ss (free_vars t)
    ) SymSet.empty xs


let rec fold_ f binders acc = function
  | Sym _s -> acc
  | Const _c -> acc
  | Binop (_bop, t1, t2) -> fold_list f binders acc [t1; t2]
  | Not t1 -> fold f binders acc t1
  | ITE (t1, t2, t3) -> fold_list f binders acc [t1; t2; t3]
  | EachI ((_, s, _), t) ->
     fold f (binders @ [(s, BT.Integer)]) acc t
  | Tuple ts -> fold_list f binders acc ts
  | NthTuple (_, t) -> fold f binders acc t
  | Struct (_tag, members) -> fold_list f binders acc (List.map snd members)
  | StructMember (t, _member) -> fold f binders acc t
  | StructUpdate ((t1, _member), t2) -> fold_list f binders acc [t1; t2]
  | Record members -> fold_list f binders acc (List.map snd members)
  | RecordMember (t, _member) -> fold f binders acc t
  | RecordUpdate ((t1, _member), t2) -> fold_list f binders acc [t1; t2]
  | DatatypeCons (tag, members_rec) -> fold f binders acc members_rec
  | DatatypeMember (t, _member) -> fold f binders acc t
  | DatatypeIsCons (tag, t) -> fold f binders acc t
  | Cast (_cbt, t) -> fold f binders acc t
  | MemberOffset (_tag, _id) -> acc
  | ArrayOffset (_sct, t) -> fold f binders acc t
  | Nil -> acc
  | Cons (t1, t2) -> fold_list f binders acc [t1; t2]
  | List ts -> fold_list f binders acc ts
  | Head t -> fold f binders acc t
  | Tail t -> fold f binders acc t
  | NthList (i, xs, d) -> fold_list f binders acc [i; xs; d]
  | ArrayToList (arr, i, len) -> fold_list f binders acc [arr; i; len]
  | Representable (_sct, t) -> fold f binders acc t
  | Good (_sct, t) -> fold f binders acc t
  | Aligned {t; align} -> fold_list f binders acc [t; align]
  | MapConst (_bt, t) -> fold f binders acc t
  | MapSet (t1, t2, t3) -> fold_list f binders acc [t1; t2; t3]
  | MapGet (t1, t2) -> fold_list f binders acc [t1; t2]
  | MapDef ((s, bt), t) -> fold f (binders @ [(s, bt)]) acc t
  | Apply (_pred, ts) -> fold_list f binders acc ts

and fold f binders acc (IT (term_, _bt)) =
  let acc' = fold_ f binders acc term_ in
  f binders acc' (IT (term_, _bt))

and fold_list f binders acc xs =
  match xs with
  | [] -> acc
  | x :: xs ->
     let acc' = fold f binders acc x in
     fold_list f binders acc' xs

let fold_subterms : 'a 'bt. ((Sym.t * BT.t) list -> 'a -> 'bt term -> 'a) -> 'a -> 'bt term -> 'a =
  fun f acc t -> fold f [] acc t




let is_call (f: Sym.t) (IT (it_, bt)) = 
  match it_ with
  | Apply (f', _) when Sym.equal f f' -> true
  | _ -> false

let is_good (ct : Sctypes.t) (IT (it_, bt)) = 
  match it_ with
  | Good (ct', _) when Sctypes.equal ct ct' -> true
  | _ -> false

let mentions_call f =
  fold_subterms (fun _binders acc it ->
      acc || is_call f it
    ) false

let mentions_good ct =
  fold_subterms (fun _binders acc it ->
      acc || is_good ct it
    ) false



let preds_of t =
  let add_p s = function
    | IT (Apply (id, _), _) -> SymSet.add id s
    | _ -> s
  in
  fold_subterms (fun _ -> add_p) SymSet.empty t




let json it : Yojson.Safe.t =
  `String (Pp.plain (pp it))


let make_subst = Subst.make free_vars

let rec subst (su : typed subst) (IT (it, bt)) =
  match it with
  | Sym sym ->
     begin match List.assoc_opt Sym.equal sym su.replace with
     | Some after -> after
     | None -> IT (Sym sym, bt)
     end
  | Const const -> 
     IT (Const const, bt)
  | Binop (bop, t1, t2) -> 
     IT (Binop (bop, subst su t1, subst su t2), bt)
  | Not it -> 
     IT (Not (subst su it), bt)
  | ITE (it,it',it'') -> 
     IT (ITE (subst su it, subst su it', subst su it''), bt)
  | EachI ((i1, s, i2), t) ->
     let s, t = suitably_alpha_rename su.relevant (s, BT.Integer) t in
     IT (EachI ((i1, s, i2), subst su t), bt)
  | Tuple its ->
     IT (Tuple (map (subst su) its), bt)
  | NthTuple (n, it') ->
     IT (NthTuple (n, subst su it'), bt)
  | Struct (tag, members) ->
     IT (Struct (tag, map_snd (subst su) members), bt)
  | StructMember (t, m) ->
     IT (StructMember (subst su t, m), bt)
  | StructUpdate ((t, m), v) ->
     IT (StructUpdate ((subst su t, m), subst su v), bt)
  | Record members ->
     IT (Record (map_snd (subst su) members), bt)
  | RecordMember (t, m) ->
     IT (RecordMember (subst su t, m), bt)
  | RecordUpdate ((t, m), v) ->
     IT (RecordUpdate ((subst su t, m), subst su v), bt)
  | DatatypeCons (tag, members_rec) ->
     IT (DatatypeCons (tag, subst su members_rec), bt)
  | DatatypeMember (t, m) ->
     IT (DatatypeMember (subst su t, m), bt)
  | DatatypeIsCons (tag, t) ->
     IT (DatatypeIsCons (tag, subst su t), bt)
  | Cast (cbt, t) ->
     IT (Cast (cbt, subst su t), bt)
  | MemberOffset (tag, member) ->
     IT (MemberOffset (tag, member), bt)
  | ArrayOffset (tag, t) ->
     IT (ArrayOffset (tag, subst su t), bt)
  | Aligned t -> 
     IT (Aligned {t= subst su t.t; align= subst su t.align}, bt)
  | Representable (rt, t) -> 
     IT (Representable (rt, subst su t), bt)
  | Good (rt, t) -> 
     IT (Good (rt, subst su t), bt)
  | Nil -> 
     IT (Nil, bt)
  | Cons (it1,it2) -> 
     IT (Cons (subst su it1, subst su it2), bt)
  | List its -> 
     IT (List (map (subst su) its), bt)
  | Head it -> 
     IT (Head (subst su it), bt)
  | Tail it -> 
     IT (Tail (subst su it), bt)
  | NthList (i, xs, d) -> 
     IT (NthList (subst su i, subst su xs, subst su d), bt)
  | ArrayToList (arr, i, len) -> 
     IT (ArrayToList (subst su arr, subst su i, subst su len), bt)
  | MapConst (bt, t) ->
     IT (MapConst (bt, subst su t), bt)
  | MapSet (t1, t2, t3) ->
     IT (MapSet (subst su t1, subst su t2, subst su t3), bt)
  | MapGet (it, arg) ->
     IT (MapGet (subst su it, subst su arg), bt)
  | MapDef ((s, abt), body) ->
     let s, body = suitably_alpha_rename su.relevant (s, abt) body in
     IT (MapDef ((s, abt), subst su body), bt)
  | Apply (name, args) ->
     IT (Apply (name, List.map (subst su) args), bt)

and alpha_rename (s, bt) body =
  let s' = Sym.fresh_same s in
  (s', subst (make_subst [(s, IT (Sym s', bt))]) body)

and suitably_alpha_rename syms (s, bt) body =
  if SymSet.mem s syms
  then alpha_rename (s, bt) body
  else (s, body)






let is_const = function
  | IT (Const const, bt) -> Some (const, bt)
  | _ -> None

let is_z = function
  | IT (Const (Z z), bt) -> Some z
  | _ -> None

let is_z_ it = Option.is_some (is_z it)

let is_pointer = function
  | IT (Const (Pointer z), bt) -> Some z
  | _ -> None

let is_sym = function
  | IT (Sym sym, bt) -> Some (sym, bt)
  | _ -> None

let is_bool = function
  | IT (Const (Bool b), _) -> Some b
  | _ -> None

let is_q = function
  | IT (Const (Q q), _) -> Some q
  | _ -> None

let is_map_get = function
  | IT (MapGet (f,arg), _) -> Some (f, arg)
  | _ -> None

let zero_frac = function
  | IT (Const (Q q), _) when Q.equal Q.zero q -> true
  | _ -> false

let is_true = function
  | IT (Const (Bool true), _) -> true
  | _ -> false

let is_false = function
  | IT (Const (Bool false), _) -> true
  | _ -> false

let is_eq = function
  | (IT (Binop (EQ, lhs, rhs), _)) -> Some (lhs, rhs)
  | _ -> None

let is_and = function
  | IT (Binop (And, it, it'), _) -> Some (it, it')
  | _ -> None

let is_or = function
  | IT (Binop (Or, it, it'), _) -> Some (it, it')
  | _ -> None

let is_not = function
  | IT (Not it, _) -> Some it
  | _ -> None

let is_lt = function
  | IT (Binop (LT,x, y), _) -> Some (x, y)
  | _ -> None

let is_le = function
  | IT (Binop (LE,x, y), _) -> Some (x, y)
  | _ -> None


let rec split_and it =
  match is_and it with
  | Some (it1, it2) -> split_and it1 @ split_and it2
  | None -> [it]


(* shorthands *)


(* lit *)
let sym_ (sym, bt) = IT (Sym sym, bt)
let z_ n = IT (Const (Z n), BT.Integer)
let q_ (n,n') = IT (Const (Q (Q.make (Z.of_int n) (Z.of_int  n'))), BT.Real)
let q1_ q = IT (Const (Q q), BT.Real)
let pointer_ n = IT (Const (Pointer n), BT.Loc)
let bool_ b = IT (Const (Bool b), BT.Bool)
let unit_ = IT (Const Unit, BT.Unit)
let int_ n = z_ (Z.of_int n)
let default_ bt = IT (Const (Default bt), bt)

(* cmp_op *)
let lt_ (it, it') = IT (Binop (LT, it, it'), BT.Bool)
let le_ (it, it') = IT (Binop (LE,it, it'), BT.Bool)
let gt_ (it, it') = lt_ (it', it)
let ge_ (it, it') = le_ (it', it)

(* bool_op *)
let vargs_binop basevalue binop = function
  | [] -> basevalue
  | it::its -> List.fold_left binop it its

let and2_ (it, it') = IT (Binop (And, it, it'), BT.Bool)
let or2_ (it, it') = IT (Binop (Or, it, it'), BT.Bool)
let and_ = vargs_binop (bool_ true) (Tools.curry and2_)
let or_ = vargs_binop (bool_ false) (Tools.curry or2_)
let impl_ (it, it') = IT (Binop (Impl, it, it'), BT.Bool)
let not_ it = IT (Not it, BT.Bool)
let ite_ (it, it', it'') = IT (ITE (it, it', it''), bt it')
let eq_ (it, it') = IT (Binop (EQ,it, it'), BT.Bool)
let eq__ it it' = eq_ (it, it')
let ne_ (it, it') = not_ (eq_ (it, it'))
let ne__ it it' = ne_ (it, it')

(* let disperse_not_ it = *)
(*   match term it with *)
(*   | And xs -> or_ (List.map not_ xs) *)
(*   | Or xs -> and_ (List.map not_ xs) *)
(*   | Impl (x, y) -> and_ [x; not_ y] *)
(*   | _ -> not_ it *)


let eachI_ (i1, s, i2) t = 
  IT (EachI ((i1, s, i2), t), BT.Bool)
(* let existsI_ (i1, s, i2) t = not_ (eachI_ (i1, s, i2) (not_ t)) *)


(* arith_op *)
let add_ (it, it') = IT (Binop (Add,it, it'), bt it)
let sub_ (it, it') = IT (Binop (Sub,it, it'), bt it)
let mul_ (it, it') = IT (Binop (Mul,it, it'), bt it)
let mul_no_smt_ (it, it') = IT (Binop (MulNoSMT,it, it'), bt it)
let div_ (it, it') = IT (Binop (Div,it, it'), bt it)
let div_no_smt_ (it, it') = IT (Binop (DivNoSMT,it, it'), bt it)
let exp_ (it, it') = IT (Binop (Exp,it, it'), bt it)
let exp_no_smt_ (it, it') = IT (Binop (ExpNoSMT,it, it'), bt it)
let rem_ (it, it') = IT (Binop (Rem,it, it'), bt it)
let rem_no_smt_ (it, it') = IT (Binop (RemNoSMT,it, it'), bt it)
let mod_ (it, it') = IT (Binop (Mod,it, it'), bt it)
let mod_no_smt_ (it, it') = IT (Binop (ModNoSMT,it, it'), bt it)
let divisible_ (it, it') = eq_ (mod_ (it, it'), int_ 0)
let rem_f_ (it, it') = mod_ (it, it')
let min_ (it, it') = IT (Binop (Min,it, it'), bt it)
let max_ (it, it') = IT (Binop (Max,it, it'), bt it)
let intToReal_ it = IT (Cast (Real, it), BT.Real)
let realToInt_ it = IT (Cast (Integer, it), BT.Integer)
let xor_no_smt_ (it, it') = IT (Binop (XORNoSMT,it, it'), bt it)

let (%+) t t' = add_ (t, t')
let (%-) t t' = sub_ (t, t')
let (%*) t t' = mul_ (t, t')
let (%/) t t' = div_ (t, t')

let (%==) t t' = eq_ (t, t')
let (%!=) t t' = ne_ (t, t')
let (%<) t t' = lt_ (t, t')
let (%<=) t t' = le_ (t, t')
let (%>) t t' = gt_ (t, t')
let (%>=) t t' = ge_ (t, t')




(* tuple_op *)
let tuple_ its = IT (Tuple its, BT.Tuple (List.map bt its))
let nthTuple_ ~item_bt (n, it) = IT (NthTuple (n, it), item_bt)

(* struct_op *)
let struct_ (tag, members) =
  IT (Struct (tag, members), BT.Struct tag)
let member_ ~member_bt (tag, it, member) =
  IT (StructMember (it, member), member_bt)

let (%.) struct_decls t member =
  let tag = match bt t with
    | BT.Struct tag -> tag
    | _ -> Debug_ocaml.error "illtyped index term. not a struct"
  in
  let member_bt = match List.assoc_opt Id.equal member
         (Memory.member_types (SymMap.find tag struct_decls))
  with
    | Some sct -> BT.of_sct sct
    | None -> Debug_ocaml.error ("struct " ^ Sym.pp_string tag ^
        " does not have member " ^ (Id.pp_string member))
  in
  member_ ~member_bt (tag, t, member)




let record_ members =
  IT (Record members,
      BT.Record (List.map (fun (s,t) -> (s, basetype t)) members))
let recordMember_ ~member_bt (t, member) =
  IT (RecordMember (t, member), member_bt)

let datatype_cons_ nm dt_tag members =
  IT (DatatypeCons (nm, record_ members), BT.Datatype dt_tag)

let datatype_is_cons_ nm t =
  IT (DatatypeIsCons (nm, t), BT.Bool)

let datatype_member_ t nm bt =
  IT (DatatypeMember (t, nm), bt)


(* pointer_op *)
let null_ = IT (Const Null, BT.Loc)
let ltPointer_ (it, it') = IT (Binop (LTPointer, it, it'), BT.Bool)
let lePointer_ (it, it') = IT (Binop (LEPointer, it, it'), BT.Bool)
let gtPointer_ (it, it') = ltPointer_ (it', it)
let gePointer_ (it, it') = lePointer_ (it', it)
let cast_ bt it =
  IT (Cast (bt, it), bt)
let integerToPointerCast_ it =
  cast_ Loc it
let pointerToIntegerCast_ it =
  cast_ Integer it
let memberOffset_ (tag, member) =
  IT (MemberOffset (tag, member), BT.Integer)
let arrayOffset_ (ct, t) =
  IT (ArrayOffset (ct, t), BT.Integer)

let isIntegerToPointerCast = function
  | IT (Cast (BT.Loc, IT (_, BT.Integer)), _) -> true
  | _ -> false

let pointer_offset_ (p, n) =
  integerToPointerCast_ (add_ (pointerToIntegerCast_ p, n))

let memberShift_ (t, tag, member) =
  pointer_offset_ (t, memberOffset_ (tag, member))
let arrayShift_ (t1, ct, t2) =
  pointer_offset_ (t1, arrayOffset_ (ct, t2))





let array_index_to_pointer ~base ~item_ct ~index =
  arrayShift_ (base, item_ct, index)

let array_offset_of_pointer ~base ~pointer =
  sub_ (pointerToIntegerCast_ pointer,
        pointerToIntegerCast_ base)

let array_pointer_to_index ~base ~item_size ~pointer =
  div_ (array_offset_of_pointer ~base ~pointer,
        item_size)

let subarray_condition ~base ~item_size ~from_index ~to_index ~qpointer =
  let offset = array_offset_of_pointer ~base ~pointer:qpointer in
  and_ [
      lePointer_ (pointer_offset_ (base, mul_ (item_size, from_index)),
                  qpointer);
      ltPointer_ (qpointer,
                  pointer_offset_ (base, mul_ (item_size, to_index)));
      divisible_ (offset, item_size)
    ]




let cellPointer_ ~base ~step ~starti ~endi ~p =
  subarray_condition ~base ~item_size:step
    ~from_index:starti ~to_index:endi ~qpointer:p




let container_of_ (t, tag, member) =
  integerToPointerCast_
    (sub_ (pointerToIntegerCast_ t, memberOffset_ (tag, member)))

(* list_op *)
let nil_ ~item_bt = IT (Nil, BT.List item_bt)
let cons_ (it, it') = IT (Cons (it, it'), bt it')
let list_ ~item_bt its = IT (List its, BT.List item_bt)
let head_ ~item_bt it = IT (Head it, item_bt)
let tail_ it = IT (Tail it, bt it)
let nthList_ (n, it, d) = IT (NthList (n, it, d), bt d)
let array_to_list_ (arr, i, len) bt = IT (ArrayToList (arr, i, len), bt)

(* set_op *)
let setMember_ bt (it, it') = IT (Binop (SetMember,it, it'), BT.Bool)
(* let setUnion_ its = IT (Set_op (SetUnion its), bt (hd its))
 * let setIntersection_ its = IT (Set_op (SetIntersection its), bt (hd its)) *)
let setDifference_ (it, it') = IT (Binop (SetDifference,it, it'), bt it)
let subset_ (it, it') = IT (Binop (Subset,it, it'), BT.Bool)



(* ct_pred *)
let minInteger_ t =
  z_ (Memory.min_integer_type t)
let maxInteger_ t =
  z_ (Memory.max_integer_type t)
let representable_ (t, it) =
  IT (Representable (t, it), BT.Bool)
let good_ (sct, it) =
  IT (Good (sct, it), BT.Bool)
let alignedI_ ~t ~align =
  IT (Aligned {t; align}, BT.Bool)
let aligned_ (t, ct) =
  alignedI_ ~t ~align:(int_ (Memory.align_of_ctype ct))


let const_map_ index_bt t =
  IT (MapConst (index_bt, t), BT.Map (index_bt, bt t))
let map_set_ t1 (t2, t3) =
  IT (MapSet (t1, t2, t3), bt t1)
let map_get_ v arg =
  match bt v with
  | BT.Map (_, rbt) ->
     IT (MapGet (v, arg), rbt)
  | _ -> Debug_ocaml.error "illtyped index term"
let map_def_ (s, abt) body =
  IT (MapDef ((s, abt), body), BT.Map (abt, bt body))

let make_array_ ~item_bt items (* assumed all of item_bt *) =
  let (_, value) =
    List.fold_left (fun (index, value) item ->
        (index + 1, map_set_ value (int_ index, item))
      ) (0, const_map_ Integer (default_ item_bt)) items
  in
  value




let pred_ name args rbt =
  IT (Apply (name, args), rbt)


(* let let_ sym e body = *)
(*   subst (make_subst [(sym, e)]) body *)




let fresh bt =
  let symbol = Sym.fresh () in
  (symbol, sym_ (symbol, bt))

let fresh_named bt name =
  let symbol = Sym.fresh_named name in
  (symbol, sym_ (symbol, bt))

let fresh_same bt symbol' =
  let symbol = Sym.fresh_same symbol' in
  (symbol, sym_ (symbol, bt))







let def_ sym e = eq_ (sym_ (sym, bt e), e)

let in_range within (min, max) =
  and_ [le_ (min, within); le_ (within, max)]




let value_check_pointer alignment ~pointee_ct about =
  let about_int = pointerToIntegerCast_ about in
  let pointee_size = match pointee_ct with
    | Sctypes.Void -> 1
    | Function _ -> 1
    | _ -> Memory.size_of_ctype pointee_ct
  in
  and_ [le_ (z_ Z.zero, about_int);
        le_ (sub_ (add_ (about_int, int_ pointee_size), int_ 1), z_ Memory.max_pointer);
        if alignment then aligned_ (about, pointee_ct) else bool_ true]

let value_check alignment (struct_layouts : Memory.struct_decls) ct about =
  let open Sctypes in
  let open Memory in
  let rec aux (ct_ : Sctypes.t) about =
    match ct_ with
    | Void ->
       bool_ true
    | Integer it ->
       in_range about (z_ (min_integer_type it), z_ (max_integer_type it))
    | Array (it, None) ->
       Debug_ocaml.error "todo: 'representable' for arrays with unknown length"
    | Array (item_ct, Some n) ->
       (* let partiality = partiality_check_array ~length:n ~item_ct about in *)
       let i_s, i = fresh BT.Integer in
       and_
         [eachI_ (0, i_s, n - 1) (aux item_ct (map_get_ about i))]
    | Pointer pointee_ct ->
       value_check_pointer alignment ~pointee_ct about
    | Struct tag ->
       and_ begin
           List.filter_map (fun piece ->
               match piece.member_or_padding with
               | Some (member, mct) ->
                  let member_bt = BT.of_sct mct in
                  let member_it = member_ ~member_bt (tag, about, member) in
                  Some (aux mct member_it)
               | None ->
                  None
             ) (SymMap.find tag struct_layouts)
         end
    | Function _ ->
       Debug_ocaml.error "todo: function types"
  in
  aux ct about

let good_value = value_check true
let representable = value_check false

let good_pointer = value_check_pointer true

let nth_array_to_list_fact n xs d = match term xs with
  | ArrayToList (arr, i, len) ->
    let lhs = nthList_ (n, xs, d) in
    let rhs = ite_ (and_ [le_ (int_ 0, n); lt_ (n, len)], map_get_ arr (add_ (i, n)), d) in
    Some (eq_ (lhs, rhs))
  | _ -> None

let nth_array_to_list_facts terms =
  let nths = fold_list (fun _ acc it -> match term it with
    | NthList (n, xs, d) -> (n, d, bt xs) :: acc
    | _ -> acc) [] [] terms in
  let arr_lists = fold_list (fun _ acc it -> match term it with
    | ArrayToList _ -> (it, bt it) :: acc
    | _ -> acc) [] [] terms in
  List.map (fun (n, d, bt1) -> List.filter_map (fun (xs, bt2) ->
    if BT.equal bt1 bt2 then nth_array_to_list_fact n xs d else None) arr_lists
  ) nths |> List.concat






