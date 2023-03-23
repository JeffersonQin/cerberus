open Pp
module CF = Cerb_frontend
module SymSet = Set.Make(Sym)
module SymMap = Map.Make(Sym)
module IT = IndexTerms
open IT
module LC = LogicalConstraints
module LCSet = Set.Make(LC)



type predicate_name = 
  | Block of Sctypes.t
  | Owned of Sctypes.t
  | PName of Sym.t
[@@deriving eq, ord]

let pp_predicate_name = function
  | Block ct -> !^"Block" ^^ angles (Sctypes.pp ct)
  | Owned ct -> !^"Owned" ^^ angles (Sctypes.pp ct)
  | PName pn -> Sym.pp pn




type predicate_type = {
    name : predicate_name; 
    pointer: IT.t;            (* I *)
    permission: IT.t;         (* I *)
    iargs: IT.t list;         (* I *)
  }
[@@deriving eq, ord]


type qpredicate_type = {
    name : predicate_name; 
    pointer: IT.t;            (* I *)
    q: Sym.t;
    step: IT.t;
    permission: IT.t;         (* I, function of q *)
    iargs: IT.t list;         (* I, function of q *)
  }
[@@deriving eq, ord]




type resource_type =
  | P of predicate_type
  | Q of qpredicate_type
[@@deriving eq, ord]


type t = resource_type



let predicate_name = function
  | P p -> p.name
  | Q p -> p.name


let pp_maybe_oargs = function
  | None -> Pp.empty
  | Some oargs -> parens (IT.pp oargs)


let pp_predicate_type_aux (p : predicate_type) oargs =
  let args = List.map IT.pp (p.pointer :: p.iargs) in
  c_app (pp_predicate_name p.name) args 
  ^^ pp_maybe_oargs oargs
  ^^ begin match IT.is_true p.permission with
     | true -> Pp.empty
     | false -> space ^^ !^"if" ^^^ IT.pp p.permission
     end

let pp_qpredicate_type_aux (p : qpredicate_type) oargs =
  let pointer = 
    IT.pp p.pointer 
    ^^^ plus 
    ^^^ Sym.pp p.q 
    ^^^ star 
    ^^^ IT.pp p.step 
  in
  let args = pointer :: List.map IT.pp (p.iargs) in

  !^"each" ^^ 
    parens (BT.pp Integer ^^^ Sym.pp p.q ^^ semi ^^^ IT.pp p.permission) 
    ^/^ braces (c_app (pp_predicate_name p.name) args)
    ^^ pp_maybe_oargs oargs

let pp_predicate_type p = pp_predicate_type_aux p None
let pp_qpredicate_type p = pp_qpredicate_type_aux p None


let pp_aux r o = 
  match r with
  | P p -> pp_predicate_type_aux p o
  | Q qp -> pp_qpredicate_type_aux qp o

let pp r = pp_aux r None



let equal = equal_resource_type
let compare = compare_resource_type


let json re : Yojson.Safe.t = 
  `String (Pp.plain (pp re))




let alpha_rename_qpredicate_type_ (q' : Sym.t) (qp : qpredicate_type) = 
  let subst = make_subst [(qp.q, sym_ (q', BT.Integer))] in
  { name = qp.name;
    pointer = qp.pointer;
    q = q';
    step = qp.step;
    permission = IT.subst subst qp.permission;
    iargs = List.map (IT.subst subst) qp.iargs;
  }

let alpha_rename_qpredicate_type qp =
  alpha_rename_qpredicate_type_ (Sym.fresh_same qp.q) qp


let subst_predicate_type substitution (p : predicate_type) = 
  {
    name = p.name;
    pointer = IT.subst substitution p.pointer;
    permission = IT.subst substitution p.permission;
    iargs = List.map (IT.subst substitution) p.iargs;
  }

let subst_qpredicate_type substitution (qp : qpredicate_type) =
  let qp = 
    if SymSet.mem qp.q substitution.Subst.relevant
    then alpha_rename_qpredicate_type qp 
    else qp
  in
  {
    name = qp.name;
    pointer = IT.subst substitution qp.pointer;
    q = qp.q;
    step = IT.subst substitution qp.step;
    permission = IT.subst substitution qp.permission;
    iargs = List.map (IT.subst substitution) qp.iargs;
  }


let subst (substitution : IT.t Subst.t) = function
  | P p -> P (subst_predicate_type substitution p)
  | Q qp -> Q (subst_qpredicate_type substitution qp)




let free_vars = function
  | P p -> 
     IT.free_vars_list (p.pointer :: p.permission :: p.iargs)
  | Q p -> 
     SymSet.union
       (SymSet.union (IT.free_vars p.pointer) (IT.free_vars p.step))
       (SymSet.remove p.q (IT.free_vars_list (p.permission :: p.iargs)))









(* resources of the same type as a request, such that the resource
   coult potentially be used to fulfil the request *)
let same_predicate_name r1 r2 =
  equal_predicate_name (predicate_name r1) (predicate_name r2)



let alpha_equivalent r1 r2 = match r1, r2 with
  | P x, P y -> equal_resource_type r1 r2
  | Q x, Q y ->
    let y2 = alpha_rename_qpredicate_type_ x.q y in
    equal_resource_type (Q x) (Q y2)
  | _ -> false


let steps_constant = function
  | Q qp -> Option.is_some (IT.is_z qp.step)
  | _ -> true



let pointer = function
  | P pred -> pred.pointer
  | Q pred -> pred.pointer




open Cerb_frontend.Pp_ast
open Pp

let dtree_of_predicate_name = function
  | Block ty -> Dleaf (!^"Block" ^^ angles (Sctypes.pp ty))
  | Owned ty -> Dleaf (!^"Owned" ^^ angles (Sctypes.pp ty))
  | PName s -> Dleaf (Sym.pp s)

let dtree_of_predicate_type (pred : predicate_type) =
  Dnode (pp_ctor "pred", 
        IT.dtree pred.permission ::
        dtree_of_predicate_name pred.name ::
        IT.dtree pred.pointer ::
        List.map IT.dtree pred.iargs)

let dtree_of_qpredicate_type (pred : qpredicate_type) =
  Dnode (pp_ctor "qpred", 
        Dleaf (Sym.pp pred.q) ::
        IT.dtree pred.step ::
        IT.dtree pred.permission ::
        dtree_of_predicate_name pred.name ::
        IT.dtree pred.pointer ::
        List.map IT.dtree pred.iargs)


let dtree = function
  | P pred -> dtree_of_predicate_type pred
  | Q pred -> dtree_of_qpredicate_type pred
