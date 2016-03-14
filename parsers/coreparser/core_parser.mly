%{
open Lem_pervasives
open Either
open Global

open Core_parser_util

open Core

module Cmm = Cmm_csem

let symbol_compare =
  Symbol.instance_Basic_classes_Ord_Symbol_t_dict.compare_method

let implementation_constant_compare =
  compare

type parsed_pexpr = (unit, _sym) generic_pexpr
type parsed_expr  = (unit, unit, _sym) generic_expr

type declaration =
  | Def_decl  of Implementation_.implementation_constant * Core.core_base_type * parsed_pexpr
  | IFun_decl of Implementation_.implementation_constant * (Core.core_base_type * (_sym * Core.core_base_type) list * parsed_pexpr)
  | Glob_decl of _sym * Core.core_type * parsed_expr
  | Fun_decl  of _sym * (Core.core_base_type * (_sym * Core.core_base_type) list * parsed_pexpr)
  | Proc_decl of _sym * (Core.core_base_type * (_sym * Core.core_base_type) list * parsed_expr)


let rec mk_list_pe = function
  | [] ->
      Pexpr ((), PEctor (Cnil (), []))
  | _pe::_pes ->
      Pexpr ((), PEctor (Ccons, [_pe; mk_list_pe _pes]))


(* TODO ... *)
let mk_file _ =
  if Pmap.is_empty M.std then
    Rstd begin
      Pmap.add (Symbol.Symbol (8, Some "catch_exceptional_condition")) (Fun (BTy_object OTy_integer, [], Pexpr (BTy_unit, PEval Vunit))) (
      Pmap.add (Symbol.Symbol (7, Some "is_representable")) (Fun (BTy_boolean, [], Pexpr (BTy_unit, PEval Vunit))) (
      Pmap.add (Symbol.Symbol (6, Some "ctype_width")) (Fun (BTy_object OTy_integer, [], Pexpr (BTy_unit, PEval Vunit))) (
      Pmap.add (Symbol.Symbol (5, Some "wrapI")) (Fun (BTy_object OTy_integer, [], Pexpr (BTy_unit, PEval Vunit))) (
      Pmap.add (Symbol.Symbol (4, Some "conv")) (Fun (BTy_object OTy_integer, [], Pexpr (BTy_unit, PEval Vunit))) (
      Pmap.add (Symbol.Symbol (3, Some "bitwise_OR")) (Fun (BTy_unit, [], Pexpr (BTy_unit, PEval Vunit))) (
      Pmap.add (Symbol.Symbol (2, Some "bitwise_XOR")) (Fun (BTy_unit, [], Pexpr (BTy_unit, PEval Vunit))) (
      Pmap.add (Symbol.Symbol (1, Some "bitwise_AND")) (Fun (BTy_unit, [], Pexpr (BTy_unit, PEval Vunit))) (
      Pmap.add (Symbol.Symbol (0, Some "conv_int")) (Fun (BTy_unit, [], Pexpr (BTy_unit, PEval Vunit))) (Pmap.empty compare)
     ))))))))
    end
  else
     Rimpl (Pmap.empty compare, Pmap.empty compare)
(*
{
  main= Symbol.Symbol (0, Some "main");
  stdlib= Pmap.empty compare;
  impl= Pmap.empty compare;
  globs= [];
  funs= Pmap.empty compare;
}
*)

(*
let rec symbolify_pexpr (Pexpr ((), _pe_): parsed_pexpr) : pexpr =
  Pexpr ((), match _pe_ with
    | PEundef ub ->
        PEundef ub
    | PEerror (str, _pe) ->
        PEerror (str, symbolify_pexpr _pe)
  )
*)

(*
 | PEval of (generic_value 'sym) (* value *)
 | PEconstrained of list (list Mem.mem_constraint * (generic_pexpr 'ty 'sym)) (* constrained value *)
 | PEsym of 'sym (* core identifier *)
 | PEimpl of Implementation_.implementation_constant (* implementation-defined constant *)
 | PEctor of (generic_ctor 'ty) * list (generic_pexpr 'ty 'sym) (* constructor application *)
 | PEcase of (generic_pexpr 'ty 'sym) * list ((generic_pattern 'ty 'sym) * (generic_pexpr 'ty 'sym)) (* pattern matching *)
 | PEarray_shift of (generic_pexpr 'ty 'sym) * ctype * (generic_pexpr 'ty 'sym) (* pointer array shift *)
 | PEmember_shift of (generic_pexpr 'ty 'sym) * Symbol.t * Cabs.cabs_identifier (* pointer struct/union member shift *)
 | PEnot of (generic_pexpr 'ty 'sym) (* not *)
 | PEop of binop * (generic_pexpr 'ty 'sym) * (generic_pexpr 'ty 'sym) (* binop *)
 | PEmemop of Mem.pure_memop * list (generic_pexpr 'ty 'sym) (* memory operation *)
 | PEstruct of Symbol.t * list (Cabs.cabs_identifier * (generic_pexpr 'ty 'sym)) (* C struct expression *)
 | PEcall of (generic_name 'sym) * list (generic_pexpr 'ty 'sym) (* pure Core function call *)
 | PElet of (generic_pattern 'ty 'sym) * (generic_pexpr 'ty 'sym) * (generic_pexpr 'ty 'sym) (* Core let *)
 | PEif of (generic_pexpr 'ty 'sym) * (generic_pexpr 'ty 'sym) * (generic_pexpr 'ty 'sym) (* Core if *)
 | PEis_scalar of (generic_pexpr 'ty 'sym)
 | PEis_integer of (generic_pexpr 'ty 'sym)
 | PEis_signed of (generic_pexpr 'ty 'sym)
 | PEis_unsigned of (generic_pexpr 'ty 'sym)
*)





(*
type _name =
  | Sym of _sym
  | Impl of Implementation_.implementation_constant

type _pattern =
  | CaseBase of _sym option
  | CaseCtor of Core.ctor * _pattern list


type _expr =
  | Vunit
  | Vtrue | Vfalse
  | Vlist of _expr list (* value *)
(*  | Vtuple of list value *)
  | Vctype of Core_ctype.ctype0
  | Vunspecified of Core_ctype.ctype0
  | Vinteger of Nat_big_num.num
  | Vfloating of string
  | Vcfunction of _name
(* RUNTIME  | Vsymbolic of Symbolic.symbolic *)
(* RUNTIME  | Vpointer of Mem.pointer_value *)
(*  | Varray of list Mem.mem_value *)
  | PEundef of Undefined.undefined_behaviour
  | PEerror of string * _expr
  | PEsym of _sym
  | PEimpl of Implementation_.implementation_constant
  | PEctor of Core.ctor * _expr list
  | PEcase of _expr * (_pattern * _expr) list
  | PEarray_shift of _expr (* pexpr *) * Core_ctype.ctype0 * _expr (* pexpr *)
  | PEnot of _expr (* pexpr *)
  | PEop of Core.binop * _expr (* pexpr *) * _expr (* pexpr *)
  | PEtuple of _expr list (* pexpr *)
  | PEarray of _expr list (* ((Mem.mem_value, _sym) either) list *)
  | PEcall of (_name * Core.core_base_type) * (_expr * Core.core_base_type) list (* pexpr *)
(*
  | PElet of sym * pexpr * pexpr
  | PEif of pexpr * pexpr * pexpr
*)
  | PEis_scalar of _expr (* pexpr *)
  | PEis_integer of _expr (* pexpr *)
  | PEis_signed of _expr (* pexpr *)
  | PEis_unsigned of _expr (* pexpr *)
  | PEis_unspec of _expr (* pexpr *)
  | Eraise of _sym
  | Eregister of _sym * _name
  | Eskip
  | Elet of _sym * _expr (* pexpr *) * _expr
  | Eif of _expr (* pexpr *) * _expr * _expr
  | Eproc of _expr (* pexpr *) * _expr list (* pexpr *)
  | Eaction of paction
  | Eunseq of _expr list
  | Ewseq of (_sym option) list * _expr * _expr
  | Esseq of (_sym option) list * _expr * _expr
  | Easeq of _sym option * action * paction
  | Eindet of _expr
  | Ebound of int * _expr
  | Esave of _sym * (_sym * Core_ctype.ctype0) list * _expr
  | Erun of _sym * (_sym * _expr (* pexpr *)) list
  | Eret of _expr (* pexpr *)
  | End of _expr list
  | Epar of _expr list
(* RUNTIME  | Ewait of Thread.thread_id *)

and action =
  | Create of _expr (* pexpr *) * _expr (* pexpr *)
  | Alloc of _expr (* pexpr *) * _expr (* pexpr *)
  | Kill of _expr (* pexpr *)
  | Store of _expr (* pexpr *) * _expr (* pexpr *) * _expr (* pexpr *) * Cmm.memory_order
  | Load of _expr (* pexpr *) * _expr (* pexpr *) * Cmm.memory_order
  | RMW of _expr (* pexpr *) * _expr (* pexpr *) * _expr (* pexpr *) * _expr (* pexpr *) * Cmm.memory_order * Cmm.memory_order
and paction = Core.polarity * action


type declaration =
  | Def_decl  of Implementation_.implementation_constant * Core.core_base_type * _expr
  | IFun_decl of Implementation_.implementation_constant * (Core.core_base_type * (_sym * Core.core_base_type) list * _expr)
  | Glob_decl of _sym * Core.core_type * _expr
  | Fun_decl  of _sym * (Core.core_base_type * (_sym * Core.core_base_type) list * _expr)
  | Proc_decl of _sym * (Core.core_base_type * (_sym * Core.core_base_type) list * _expr)



let fresh_symbol (str, _) =
  let n = !M.sym_counter in
  M.sym_counter := n+1;
  Symbol.Symbol (n, Some str)


let lookup_symbol ((str, loc) as _sym) syms =
  (* TODO: print location *)
  Debug.print_debug 7 ("[Core_parser.convert_expr] LOOKING FOR: " ^ str);
  begin try
    Pmap.find _sym syms (* TODO: Error handling *)
  with
    | e -> print_endline (pp_pos _sym ^ " [Core_parser.convert_expr] Failed to find: " ^ str);
           Pmap.iter (fun (str, _) _ ->
             Printf.printf "DEBUG, in sigma: %s\n" str
           ) syms;
           raise e
  end


let register_cont_symbols expr =
  let rec f (st : (_sym, Core.sym) Pmap.map) = function
    | Vunit
    | Vtrue
    | Vfalse
    | Vlist _
    | Vctype _
    | Vcfunction _
    | Vunspecified _
    | Vinteger _
    | Vfloating _
    | PEundef _
    | PEerror _
    | PEsym _
    | PEimpl _
    | PEctor _
    | PEcase _
    | PEarray_shift _
    | PEnot _
    | PEop _
    | PEtuple _
    | PEarray _
    | PEcall _
    | PEis_scalar _
    | PEis_integer _
    | PEis_signed _
    | PEis_unsigned _
    | PEis_unspec _
    | Eraise _
    | Eregister _
    | Eskip
    | Elet _
    | Eproc _
    | Eaction _
    | Eunseq _
    | Easeq _
    | Erun _
    | Eret _ ->
        st
    | Eif (_, _e1, _e2)
    | Ewseq (_, _e1, _e2)
    | Esseq (_, _e1, _e2) ->
        f (f st _e1) _e2
    | Eindet _e
    | Ebound (_, _e) ->
        f st _e
    | End _es
    | Epar _es ->
        List.fold_left f st _es
    | Esave (_sym, _, _e) ->
        f (Pmap.add _sym (fresh_symbol _sym) st) _e
  
  in f (Pmap.empty _sym_compare) expr


let symbolify_name _Sigma : _name -> Core.name = function
  | Impl iCst ->
      Core.Impl iCst
  | Sym _sym ->
      let sym = try Pmap.find _sym _Sigma
      with Not_found -> try Pmap.find _sym M.std
      with Not_found ->
        prerr_endline (Colour.ansi_format [Colour.Red] ("PARSING ERROR: the function `" ^ fst _sym ^ "' was not declared."));
        exit 1 in
      Core.Sym sym


type _core =
  | Value of Core.value
  | Pure of Core.pexpr
  | Expr of unit Core.expr

let to_value = function
  | Value cval ->
      Some cval
  | _ ->
      None

let to_values xs =
  List.fold_right (fun x acc_opt ->
    match to_value x, acc_opt with
      | Some cval, Some acc ->
          Some (cval :: acc)
      | _ ->
          None
  ) xs (Some [])

let to_pure = function
  | Value cval ->
      Left (Core.PEval cval)
  | Pure pe ->
      Left pe
  | Expr e ->
      Right e

let to_pures xs =
  List.fold_right (fun x acc_opt ->
    match to_pure x, acc_opt with
      | Left pe, Left acc ->
          Left (pe :: acc)
      | Left pe, Right acc ->
          Right (Core.Epure pe :: acc)
      | Right e, Left acc ->
          Right (e :: List.map (fun pe -> Core.Epure pe) acc)
      | Right e, Right acc ->
          Right (e :: acc)
  ) xs (Left [])

let to_expr = function
  | Value cval ->
      Core.Epure (Core.PEval cval)
  | Pure pe ->
      Core.Epure pe
  | Expr e ->
      e


let symbolify_pattern st (_pat: _pattern) =
  let (pat_rev, st') = List.fold_left (fun (acc, st) _sym_opt ->
    match _sym_opt with
      | Some _sym ->
          let sym = fresh_symbol _sym in
          (Some (sym, Core.BTy_any) :: acc, Pmap.add _sym sym st)
      | None ->
          (None :: acc, st)
  ) ([], st) _pat in
  (List.rev pat_rev, st')


let symbolify_pattern = function
  | CaseBase None ->
      Core.CaseBase None
  | CaseBase (Some _sym) ->
      failwith "WIP"
  | CaseCtor (ctor, _pats) ->
      failwith "WIP"


(* NOTE: the second argument is the map of non-filescoped symbols *)
let symbolify_expr _Sigma st (expr: _expr) : _core =
  let fnm = symbolify_name _Sigma in
  let rec f (st : (_sym, Core.sym) Pmap.map) = function
    | Vunit ->
        Value (Core.Vunit)
    | Vtrue ->
        Value (Core.Vtrue)
    | Vfalse ->
        Value (Core.Vfalse)
    | Vlist _es ->
        (match to_values (List.map (f st) _es) with
          | Some cvals ->
              Value (Core.Vlist cvals)
          | None ->
              failwith "TODO(MSG) type-error: symbolify_expr, Vlist")
    | Vctype ty ->
        Value (Core.Vctype ty)
    | Vcfunction _nm ->
        Value (Core.Vobject (Core.OVcfunction (fnm _nm)))
    | Vunspecified ty ->
        Value (Core.Vunspecified ty)
    | Vinteger n ->
        Value (Core.Vobject (Core.OVinteger (Mem.integer_ival0 n)))
    | Vfloating str ->
        Value (Core.Vobject (Core.OVfloating (Mem.str_fval0 str)))
    | PEundef ub ->
        Pure (Core.PEundef ub)
    | PEerror (str, _e) ->
        (match to_pure (f st _e) with
          | Left pe ->
              Pure (Core.PEerror (str, pe))
          | _ ->
              failwith "TODO(MSG) type-error: symbolify_expr, PEerror")
    | PEsym _sym ->
        Pure (Core.PEsym (lookup_symbol _sym st, Core.BTy_any (* TODO *)))
    | PEimpl iCst ->
        Pure (Core.PEimpl iCst)
    | PEctor (ctor, _es) ->
        (match to_pures (List.map (f st) _es) with
          | Left pes ->
              Pure (Core.PEctor (ctor, pes))
          | _ ->
              failwith "TODO(MSG) type-error: symbolify_expr, PEctor")
(*
    | PEcase (_pe, _pat) ->
        (match to_pure with
          | Left pe ->
              Pure (Core.PEcase (pe, ))
*)
    | PEarray_shift (_e1, ty, _e2) ->
        (match to_pure (f st _e1), to_pure (f st _e2) with
          | Left pe1, Left pe2 ->
              Pure (Core.PEarray_shift (pe1, ty, pe2))
          | _ ->
              failwith "TODO(MSG) type-error: symbolify_expr, PEarray_shift")
(*
        let ty_es_opt = List.fold_right (fun (ty, _e) acc_opt ->
          match to_pure (f st _e), acc_opt with
            | Left pe, Some acc ->
                Some ((ty, pe) :: acc)
            | _ ->
                None
        ) ty_es (Some []) in
        (match to_pure (f st _e1), ty_es_opt with
          | Left pe1, Some ty_pes ->
              Pure (Core.PEshift (pe1, ty_pes))
          | _ ->
              failwith "TODO(MSG) type-error: symbolify_expr, PEshift")
*)
    | PEnot _e ->
        (match to_pure (f st _e) with
          | Left pe ->
              Pure (Core.PEnot pe)
          | _ ->
              failwith "TODO(MSG) type-error: symbolify_expr, PEnot")
    | PEop (bop, _e1, _e2) ->
        (match to_pure (f st _e1), to_pure (f st _e2) with
          | Left pe1, Left pe2 ->
              Pure (Core.PEop (bop, pe1, pe2))
          | _ ->
              failwith "TODO(MSG) type-error: symbolify_expr, PEop")
    | PEcall ((_nm, bTy), _e_bTys) ->
        let nm = fnm _nm in
        (match to_pures (List.map (fun (_e, _) -> f st _e) _e_bTys) with
          | Left pes ->
              Pure (Core.PEcall ((nm, bTy), List.combine pes (map snd _e_bTys)))
          | _ ->
              failwith "TODO(MSG) type-error: symbolify_expr, PEcall")
    | PEis_scalar _e ->
        (match to_pure (f st _e) with
          | Left pe ->
              Pure (Core.PEis_scalar pe)
          | _ ->
              failwith "TODO(MSG) type-error: symbolify_expr, PEis_scalar")
    | PEis_integer _e ->
        (match to_pure (f st _e) with
          | Left pe ->
              Pure (Core.PEis_integer pe)
          | _ ->
              failwith "TODO(MSG) type-error: symbolify_expr, PEis_integer")
    | PEis_signed _e ->
        (match to_pure (f st _e) with
          | Left pe ->
              Pure (Core.PEis_signed pe)
          | _ ->
              failwith "TODO(MSG) type-error: symbolify_expr, PEis_signed")
    | PEis_unsigned _e ->
        (match to_pure (f st _e) with
          | Left pe ->
              Pure (Core.PEis_unsigned pe)
          | _ ->
              failwith "TODO(MSG) type-error: symbolify_expr, PEis_unsigned")
    | Eraise _sym ->
        Expr (Core.Eraise (fst _sym))
    | Eregister (_sym, nm) ->
        Expr (Core.Eregister (fst _sym, fnm nm))
    | Eskip ->
        Expr (Core.Eskip)
    | Elet (_sym, _e1, _e2) ->
        let sym = fresh_symbol _sym in
        let _e2' = f (Pmap.add _sym sym st) _e2 in
        (match to_pure (f st _e1), to_pure _e2' with
          | Left pe1, Left pe2 ->
              Pure (Core.PElet ((sym, Core.BTy_any), pe1, pe2))
          | Left pe1, Right e2 ->
              Expr (Core.Elet ((sym, Core.BTy_any), pe1, e2))
          | _ ->
              failwith "TODO(MSG) type-error: symbolify_expr, Elet")
    | Eif (_e1, _e2, _e3) ->
        let _e2' = f st _e2 in
        let _e3' = f st _e3 in
        (match to_pure (f st _e1), to_pure _e2', to_pure _e3' with
          | Left pe1, Left pe2, Left pe3 ->
              Pure (Core.PEif (pe1, pe2, pe3))
          | Left pe1, Left pe2, Right e3 ->
              Expr (Core.Eif (pe1, Core.Epure pe2, e3))
          | Left pe1, Right e2, Left pe3 ->
              Expr (Core.Eif (pe1, e2, Core.Epure pe3))
          | Left pe1, Right e2, Right e3 ->
              Expr (Core.Eif (pe1, e2, e3))
          | _ ->
              failwith "TODO(MSG) type-error: symbolify_expr, Eif")
    | Eproc (_e, _es) ->
        (match to_pure (f st _e), to_pures (List.map (f st) _es) with
          | Left pe, Left pes ->
              Expr (Core.Eproc ((), pe, pes))
          | _ ->
              failwith "TODO(MSG) type-error: symbolify_expr, Eproc")
    | Eaction (p, act) ->
        Expr (Core.Eaction (Core.Paction (p, Core.Action (Location_ocaml.unknown, (), g st act))))
    | Eunseq _es ->
        Expr (Core.Eunseq (List.map (fun z -> to_expr (f st z)) _es))
    | Ewseq (_pat, _e1, _e2) ->
        let (pat, st') = symbolify_pattern st _pat in
        Expr (Core.Ewseq (pat, to_expr (f st _e1), to_expr (f st' _e2)))
    | Esseq (_as, _e1, _e2) ->
        let (_as', st') = List.fold_left (fun (_as, st) _sym_opt ->
          match _sym_opt with
            | Some _sym ->
                let sym = fresh_symbol _sym in
                (Some (sym, Core.BTy_any) :: _as, Pmap.add _sym sym st)
            | None ->
                (None :: _as, st)
        ) ([], st) _as in
        Expr (Core.Esseq (List.rev _as', to_expr (f st _e1), to_expr (f st' _e2)))
    | Easeq (_sym_opt, act1, (p, act2)) ->
        Expr (match _sym_opt with
          | Some _sym ->
              let sym = fresh_symbol _sym in
              Core.Easeq (Some (sym, Core.BTy_any), Core.Action (Location_ocaml.unknown, (), g st act1), Core.Paction (p, Core.Action (Location_ocaml.unknown, (), g (Pmap.add _sym sym st) act2)))
          | None ->
              Core.Easeq (None, Core.Action (Location_ocaml.unknown, (), g st act1), Core.Paction (p, Core.Action (Location_ocaml.unknown, (), g st act2))))
    | Eindet _e ->
        Expr (Core.Eindet (to_expr (f st _e)))
    | Ebound (n, _e) ->
        Expr (Core.Ebound (n, to_expr (f st _e)))
    | Esave (_sym, _sym_tys, _e) ->
        let sym_tys =
          List.map (fun (_sym, ty) -> (lookup_symbol _sym st, ty)) _sym_tys in
        Expr (Core.Esave (lookup_symbol _sym st, sym_tys, to_expr (f st _e)))
    | Erun (_sym, _sym__es) ->
        let sym_pes_opt = List.fold_right (fun (_sym, _e) acc_opt ->
          match (to_pure (f st _e), acc_opt) with
            | (Left pe, Some acc) ->
                Some ((lookup_symbol _sym st, pe) :: acc)
            | _ ->
                None
        ) _sym__es (Some []) in
        (match sym_pes_opt with
          | Some sym_pes ->
              Expr (Core.Erun ((), lookup_symbol _sym st, sym_pes))
          | None ->
              failwith "TODO(MSG) type-error: symbolify_expr, Erun")
    | Eret _e ->
        (match to_pure (f st _e) with
          | Left pe ->
              Expr (Core.Eret pe)
          | _ ->
              failwith "TODO(MSG) type-error: symbolify_expr, Eret")
    | End _es ->
        Expr (Core.End (List.map (fun z -> to_expr (f st z)) _es))
    | Epar _es ->
        Expr (Core.Epar (List.map (fun z -> to_expr (f st z)) _es))
  
  and g st = function
    | Create (_e1, _e2) ->
        (match to_pure (f st _e1), to_pure (f st _e2) with
          | Left pe1, Left pe2 ->
              Core.Create (pe1, pe2, (Symbol.PrefOther "core parser"))
          | _ ->
            failwith "TODO(MSG) type-error: symbolify_expr, Create")
    | Alloc (_e1, _e2) ->
        (match to_pure (f st _e1), to_pure (f st _e2) with
          | Left pe1, Left pe2 ->
              Core.Alloc0 (pe1, pe2, (Symbol.PrefOther "core parser"))
          | _ ->
            failwith "TODO(MSG) type-error: symbolify_expr, Alloc")
    | Kill _e ->
        (match to_pure (f st _e) with
          | Left pe ->
              Core.Kill pe
          | _ ->
            failwith "TODO(MSG) type-error: symbolify_expr, Kill")
    | Store (_e1, _e2, _e3, mo) ->
        (match to_pure (f st _e1), to_pure (f st _e2), to_pure (f st _e3) with
          | Left pe1, Left pe2, Left pe3 ->
              Core.Store0 (pe1, pe2, pe3, mo)
          | _ ->
            failwith "TODO(MSG) type-error: symbolify_expr, Store")
    | Load (_e1, _e2, mo) ->
        (match to_pure (f st _e1), to_pure (f st _e2) with
          | Left pe1, Left pe2 ->
              Core.Load0 (pe1, pe2, mo)
          | _ ->
            failwith "TODO(MSG) type-error: symbolify_expr, Load")
        
    | RMW (_e1, _e2, _e3, _e4, mo1, mo2) ->
        (match to_pure (f st _e1), to_pure (f st _e2), to_pure (f st _e3), to_pure (f st _e4) with
          | Left pe1, Left pe2, Left pe3, Left pe4 ->
              Core.RMW0 (pe1, pe2, pe3, pe4, mo1, mo2)
          | _ ->
            failwith "TODO(MSG) type-error: symbolify_expr, RMW") in
  f st expr


(* let symbolify_ *)




let symbolify_expr_ (_Sigma, fsyms) (expr: _expr) : unit Core.expr =
  failwith "WIP"
(* TODO: WIP
  let lookup_symbol str syms =
    Debug.print_debug 7 ("[Core_parser.convert_expr] LOOKING FOR: " ^ str);
    begin try
        Pmap.find str syms (* TODO: Error handling *)
      with
        | e -> print_endline ("[Core_parser.convert_expr] Failed to find: " ^ str);
               raise e
    end in
  
  let rec f st = function
    | Eunit ->
        Core.Epure (Core.PEval Core.Vunit)
(*
    | Enull ->
        Core.Enull Core_ctype.Void0 (* TODO *)
*)
    | Etrue ->
        Core.Epure (Core.PEval Core.Etrue)
    | Efalse ->
        Core.Epure (Core.PEval Core.Efalse)
    | Econst c ->
        Core.Econst c
    | Elist es ->
        Core.Elist (List.map (f st) es)
    | Econs (pe1, pe2) ->
        Core.Econs (f st pe1, f st pe2)
    | Ectype ty ->
        Core.Ectype ty
    | Esym a ->
        Core.Esym (lookup_symbol a st)
    | Eimpl ic ->
        Core.Eimpl ic
    | Etuple es ->
        Core.Etuple (List.map (f st) es)
    | Enot e ->
        Core.Enot (f st e)
    | Eop (binop, e1, e2) ->
        Core.Eop (binop, f st e1, f st e2)
    | Ecall (Impl func, params) ->
        Core.Ecall (Core.Impl func, List.map (f st) params)
    | Ecall (Sym func, params) ->
        let fsym = try
            Pmap.find func fsyms
          with Not_found -> try
              Pmap.find func M.std
            with Not_found ->
              prerr_endline (Colour.ansi_format [Colour.Red] ("PARSING ERROR: the function `" ^ func ^ "' was not declared."));
              exit 1 in
        Core.Ecall (Core.Sym fsym, List.map (f st) params)
    | Eundef ub ->
        Core.Eundef ub
    | Eerror str ->
        Core.Eerror str
    | Eraise evnt ->
        Core.Eraise evnt
    | Eregister (evnt, nm) ->
        let nm' = match nm with
          | Impl f ->
              Core.Impl f
          | Sym str ->
              Core.Sym (Pmap.find str fsyms) in
        Core.Eregister (evnt, nm')
(*
    | Etry (e, str_es) ->
        Core.Etry (f st e, List.map (fun (str, e) -> (str, f st e)) str_es)
*)
    | Eshift (pe, sh) ->
        Core.Eshift (f st pe, List.map (fun (ty, e) -> (ty, f st e)) sh)

    | Eskip ->
        Core.Eskip
    | Elet (a, e1, e2) ->
        let sym_n = fresh_symbol a in
        Core.Elet (sym_n, f st e1, f (Pmap.add a sym_n st) e2)
    | Eif (e1, e2, e3) ->
        Core.Eif (f st e1, f st e2, f st e3)
    | Eproc (Impl func, params) ->
        Core.Eproc ((), Core.Impl func, List.map (f st) params)
    | Eproc (Sym func, params) ->
        Core.Eproc ((), Core.Sym (Pmap.find func fsyms), List.map (f st) params)

    | Ecase (e, nm1, nm2, nm3, nm4, nm5, nm6, nm7, nm8, nm9) ->
        let g = (function
          | Impl f -> Core.Impl f
          | Sym f  ->
              begin try
                Core.Sym (Pmap.find f fsyms)
              with
                | e -> print_endline ("[Core_parser.symbolify, Ecase] Failed to find: " ^ f);
                    raise e
              end) in
        Core.Ecase (f st e, g nm1, g nm2, g nm3, g nm4, g nm5, g nm6, g nm7, g nm8, g nm9)


(*
    | Esame (e1, e2) ->
        Core.Esame (f st e1, f st e2)
*)
    | Eaction pact ->
        let (p, (s, act)) = g st pact in
        Core.Eaction (Core.Paction (p, Core.Action (s, act)))
    | Eunseq es ->
        Core.Eunseq (List.map (f st) es)
    | Ewseq (_as, e1, e2) ->
        let (_as', st') = List.fold_left (fun (_as, st) str_opt ->
          match str_opt with
            | Some str ->
                let sym_n = fresh_symbol str in
                (Some sym_n :: _as, Pmap.add str sym_n st)
            | None ->
                (None :: _as, st)
        ) ([], st) _as in
        Core.Ewseq (List.rev _as', f st e1, f st' e2)
(*
        let (count', _as', syms') = List.fold_left (fun (c, _as, syms) sym_opt ->
          match sym_opt with
            | Some sym -> let _a = Symbol.Symbol (c, Some sym) in
                          (c+1, Some _a :: _as, Pmap.add sym _a syms)
            | None     -> (c+1, None :: _as, syms)) (count, [], syms) _as in
        Core.Ewseq (List.rev _as', f st e1, f (count', syms') e2)
*)
    | Esseq (_as, e1, e2) ->
        let (_as', st') = List.fold_left (fun (_as, st) str_opt ->
          match str_opt with
            | Some str ->
                let sym_n = fresh_symbol str in
                (Some sym_n :: _as, Pmap.add str sym_n st)
            | None ->
                (None :: _as, st)
        ) ([], st) _as in
        Core.Esseq (List.rev _as', f st e1, f st' e2)

(*
        let (count', _as', syms') = List.fold_left (fun (c, _as, syms) sym_opt ->
          match sym_opt with
            | Some sym -> let _a = Symbol.Symbol (c, Some sym) in
                          (c+1, Some _a :: _as, Pmap.add sym _a syms)
            | None     -> (c+1, None :: _as, syms)) (count, [], syms) _as in
        Core.Esseq (List.rev _as', f st e1, f (count', syms') e2)
 *)
    | Easeq (_a_opt, act, pact) ->
        begin match _a_opt with
                | Some _a ->
                    let sym_n = !M.sym_counter in
                    let _a' = Symbol.Symbol (sym_n, Some _a) in
                    M.sym_counter := sym_n+1;
                    let (_, (s1, act1)) = g st (Core.Pos, act) in
                    let (p2, (s2, act2)) = g (Pmap.add _a _a' st) pact in
                    Core.Easeq (Some _a', Core.Action (s1, act1), Core.Paction (p2, Core.Action (s2, act2)))
                | None ->
                    let (_, (s1, act1)) = g st (Core.Pos, act) in
                    let (p2, (s2, pact2)) = g st pact in
                    Core.Easeq (None, Core.Action (s1, act1), Core.Paction (p2, Core.Action (s2, pact2)))
        end
    | Eindet e ->
        Core.Eindet (f st e)
    | Ebound (j, e) ->
        failwith "[Core_parser.symbolify] #Ebound: TODO"
    | Esave (k, a_tys, e) ->
        let a_tys' = List.map (fun (a, ty) -> (lookup_symbol a st, ty)) a_tys in
        Core.Esave (lookup_symbol k st, a_tys', f st e)
(* HIP
        let (st', a_tys') = List.fold_left (fun ((count, syms) as st, acc) (a, ty) ->
          let _a = Symbol.Symbol (count, Some a) in
          ((count+1, Pmap.add a _a syms), (_a, ty) :: acc)
        ) (st, []) a_tys in
        Core.Esave (lookup_symbol k syms, List.rev a_tys', f st' e)
 *)
    | Erun (k, a_es) ->
        let a_es' = List.map (fun (a, e) -> (lookup_symbol a st, f st e)) a_es in
        Core.Erun ((), lookup_symbol k st, a_es')
    | Eret e ->
        Core.Eret (f st e)
    | End es ->
        Core.End (List.map (f st) es)
    | Epar es ->
        Core.Epar (List.map (f st) es)
    | Eis_scalar e ->
        Core.Eis_scalar (f st e)
    | Eis_integer e ->
        Core.Eis_integer (f st e)
    | Eis_signed e ->
        Core.Eis_signed (f st e)
    | Eis_unsigned e ->
        Core.Eis_unsigned (f st e)
  
  and g st (p, act) =(p,
    match act with
      | Create (e_al, e_ty) ->
          ((), Core.Create (f st e_al, f st e_ty, []))
      | Alloc (e_al, e_n) ->
          ((), Core.Alloc0 (f st e_al, f st e_n, []))
      | Kill e_o ->
          ((), Core.Kill (f st e_o))
      | Store (e_ty, e_o, e_n, mo) ->
          ((), Core.Store0 (f st e_ty, f st e_o, f st e_n, mo))
      | Load (e_ty, e_o, mo) ->
          ((), Core.Load0 (f st e_ty, f st e_o, mo))
      | CompareExchangeStrong (e_ty, e_o, e_e, e_d, mo1, mo2) ->
          ((), Core.CompareExchangeStrong (f st e_ty, f st e_o, f st e_e, f st e_d, mo1, mo2))
      | CompareExchangeWeak (e_ty, e_o, e_e, e_d, mo1, mo2) ->
          ((), Core.CompareExchangeWeak (f st e_ty, f st e_o, f st e_e, f st e_d, mo1, mo2))
    )
  in
  let conts = register_cont_symbols expr in
  f (Pmap.union _Sigma conts) expr
*)


(*


(* symbolify_impl_map: (Implementation_.implementation_constant, Core.core_basic_type * () list) Pmap.map -> unit Core.impl *)
let symbolify_impl_map global_syms xs : Core.impl =
  Pmap.map (function
    | Left (bTy, _e) ->
        (match to_pure (symbolify_expr global_syms (Pmap.empty _sym_compare) _e) with
          | Left pe ->
              Core.Def (bTy, pe)
          | _ ->
              failwith "(TODO msg) Type-error: symbolify_impl_map, Left")
    
    | Right (bTy, params_, _e) ->
        let (_Sigma, params) =
          List.fold_left (fun (_Sigma_acc, params_acc) (param_str, param_ty) ->
            let param_sym = fresh_symbol param_str in
            ( Pmap.add param_str param_sym _Sigma_acc, (param_sym, param_ty) :: params_acc )
          ) (Pmap.empty _sym_compare, []) params_ in
        
        (match to_pure (symbolify_expr global_syms _Sigma _e) with
          | Left pe ->
              Core.IFun (bTy, params, pe)
          | _ ->
              failwith "(TODO msg) Type-error: symbolify_impl_map, Right")
  ) xs
*)






let symbolify_params _params =
  List.fold_right (fun (str, bTy) (params_acc, _Gamma_acc) ->
    let sym = fresh_symbol str in
    ((sym, bTy) :: params_acc, Pmap.add str sym _Gamma_acc)
  ) _params ([], Pmap.empty _sym_compare)


let symbolify_decls _Sigma _decls =
  List.fold_left (fun (impl_acc, globs_acc, funs_acc) -> function
    | Def_decl (iCst, bTy, _e) ->
        (match to_pure (symbolify_expr _Sigma (Pmap.empty _sym_compare) _e) with
          | Left pe ->
              (Pmap.add iCst (Core.Def (bTy, pe)) impl_acc, globs_acc, funs_acc)
          | _ ->
              failwith "TODO(MSG) type-error: symbolify_decls, Def_decl")
    | IFun_decl (iCst, (bTy, _params, _e)) ->
        let (params, _Gamma) = symbolify_params _params in
        (match to_pure (symbolify_expr _Sigma _Gamma _e) with
          | Left pe ->
              (Pmap.add iCst (Core.IFun (bTy, params, pe)) impl_acc, globs_acc, funs_acc)
          | _ ->
              failwith "TODO(MSG) type-error: symbolify_decls, IFun_decl")
    | Glob_decl (_sym, coreTy, _e) ->
        (impl_acc,
         (lookup_symbol _sym _Sigma, coreTy, to_expr (symbolify_expr (Pmap.remove _sym _Sigma) (Pmap.empty _sym_compare) _e)) :: globs_acc,
         funs_acc)
    | Fun_decl (_sym, (bTy, _params, _e)) ->
        let (params, _Gamma) = symbolify_params _params in
        (match to_pure (symbolify_expr _Sigma _Gamma _e) with
           | Left pe ->
               (impl_acc, globs_acc,
                Pmap.add (lookup_symbol _sym _Sigma) (Core.Fun (bTy, params, pe)) funs_acc)
           | _ ->
               failwith "TODO(MSG) type-error: symbolify_decls, Fun_decl")
    | Proc_decl (_sym, (bTy, _params, _e)) ->
        let (params, _Gamma) = symbolify_params _params in
        (impl_acc, globs_acc,
         Pmap.add (lookup_symbol _sym _Sigma) (Core.Proc (bTy, params, to_expr (symbolify_expr _Sigma _Gamma _e))) funs_acc)
  ) (Pmap.empty implementation_constant_compare, [], Pmap.empty symbol_compare) _decls



let mk_file _decls =
  (* this first pass collect all the file scope symbol names to allow mutually recursive definitions *)
  (* TODO: check for exhaustivity of iCst definition *)
  let (sym_opt, _, _Sigma) = List.fold_left (fun (sym_opt_acc, iCsts, _Sigma_acc) -> function
    | Def_decl (iCst, _, _)
    | IFun_decl (iCst, _) ->
        if List.mem iCst iCsts then
          failwith ("duplicate definition of '" ^ Implementation_.string_of_implementation_constant iCst ^ "'")
        else
          (sym_opt_acc, iCst :: iCsts, _Sigma_acc)
    | Glob_decl ((str, _) as _sym, _, _) ->
        if Pmap.mem _sym _Sigma_acc then
          failwith ("duplicate definition of '" ^ str ^ "'")
        else if str = "main" then
          failwith "a global cannot be named 'main'"
        else
          (sym_opt_acc, iCsts, Pmap.add _sym (fresh_symbol _sym) _Sigma_acc)
    | Fun_decl  ((str, _) as _sym, _)
    | Proc_decl  ((str, _) as _sym, _) ->
        if Pmap.mem _sym _Sigma_acc then
          failwith ("duplicate definition of '" ^ str ^ "'")
        else
          let sym = fresh_symbol _sym in
          ((if str = "main" then Some sym else sym_opt_acc), iCsts, Pmap.add _sym sym _Sigma_acc)
  ) (None, [], Pmap.empty _sym_compare) _decls in
  
  if List.exists (function Glob_decl _ -> true | _ -> false) _decls then
    (* CASE: this must be program file *)
    if List.exists (function IFun_decl _ | Def_decl _ -> true | _ -> false) _decls then
      failwith "TODO(msg): globals are not allowed in implementation files"
    else
      let (_, globs, funs) = symbolify_decls _Sigma _decls in
      match sym_opt with
        | Some sym ->
            Core_parser_util.Rfile (sym, globs, funs)
        | None ->
            failwith "TODO(msg): program file should define the startup function/procedure 'main'"
  else if List.exists (function IFun_decl _ | Def_decl _ -> true | _ -> false) _decls then
    (* CASE: this has to be an implementation file *)
    match sym_opt with
      | Some _ ->
          failwith "TODO(msg): the file-scope name 'main' is reserved for the startup function/procedure in program files"
      | None ->
          let (impl, _, funs) = symbolify_decls _Sigma _decls in
          Core_parser_util.Rimpl (impl, funs)
  else
    (* CASE: program or std file (latter in absence of a main function/procedure *)
    let (_, globs, funs) = symbolify_decls _Sigma _decls in
    match sym_opt with
      | Some sym ->
          Core_parser_util.Rfile (sym, globs, funs)
      | None ->
          Core_parser_util.Rstd funs


(*
              match coreTy with
                | Core.TyBase bTy ->
                    match to_pure (symbolify_expr global_syms _Sigma_acc' _e)
                    (sym_opt_acc, _Sigma_acc', Core.Fun_decl (bTy, [], ) :: fun_map_acc)
                     
*)




(*

  if List.for_all (function Fun_decl _ -> true | _ -> false) decls then
    (* CASE: this is not an implementation file. *)
    let (main_opt, _Sigma, fun_map_) =
      List.fold_left (fun (main_opt_acc, _Sigma_acc, fun_map_acc) decl ->
        match decl with
          | Fun_decl (fun_str, fun_def) ->
            (* TODO: better error *)
            if Pmap.mem fun_str _Sigma_acc then
              failwith ("duplicate definition of `" ^ fun_str ^ "'")
            else
              let fun_sym = fresh_symbol fun_str in
              ((if fun_str = "main" then Some fun_sym else main_opt_acc),
               Pmap.add fun_str fun_sym _Sigma_acc,
               Pmap.add fun_sym fun_def fun_map_acc)
          | _ -> assert false
      ) (None, Pmap.empty compare, Pmap.empty symbol_compare) decls
    in
    
    let fun_map = symbolify_fun_map _Sigma fun_map_ in
    match main_opt with
      | Some sym_main ->
          Core_parser_util.Rfile (sym_main, fun_map)
      | None ->
          Core_parser_util.Rstd fun_map
  
  else
    (* CASE: this is an implementation file *)
    let (impl_map_, (_Sigma, fun_map_)) =
      List.fold_left (fun (impl_map_acc, ((fsyms, fun_map) as funs_acc)) decl ->
        match decl with
          | Def_decl (i, bty, e) ->
              if Pmap.mem i impl_map_acc then
                failwith ("(TODO_MSG) duplication declaration of " ^ Implementation_.string_of_implementation_constant i)
              else
                (Pmap.add i (Left (bty, e)) impl_map_acc, funs_acc)
          
          | IFun_decl (implConst, decl) ->
              if Pmap.mem implConst impl_map_acc then
                failwith ("multiple declaration of " ^ Implementation_.string_of_implementation_constant implConst)
              else
              (Pmap.add implConst (Right decl) impl_map_acc, funs_acc)
          
          | Glob_decl _ ->
              failwith "(TODO_MSG) found a global declaration in an implementation file."
          
          | Fun_decl (fname, fdef) ->
            (* TODO: better error *)
            if Pmap.mem fname fsyms then
              failwith ("duplicate definition of `" ^ fname ^ "'")
            else
              let fun_sym = fresh_symbol fname in
              (impl_map_acc, (Pmap.add fname fun_sym fsyms, Pmap.add fun_sym fdef fun_map))
      ) (Pmap.empty compare, (Pmap.empty compare, Pmap.empty symbol_compare)) decls in
    
    
    (* We perform the symbolification as a second step to allow mutual recursion *)
    let impl_map = failwith "symbolify_impl_map _Sigma impl_map_" in
    let fun_map = failwith "symbolify_fun_map _Sigma fun_map_" in
    
    (* TODO: add a check for completeness of the impl map *)
    Core_parser_util.Rimpl (impl_map, fun_map)
*)


(* HACK for now (maybe we should just get back to concrete names for ctypes) *)
let ctypes_names = ref (0, Pmap.empty symbol_compare)

(*val subst: string -> Symbol.t *)
let subst name =
  let (z, ns) = !ctypes_names in
  if Pmap.mem name ns then
    Pmap.find name ns
  else
    let n = (z, Some name) in
    ctypes_names := (z+1, Pmap.add name n ns);
    n
*)

%}

%token <Nat_big_num.num> INT_CONST
%token <Core_parser_util._sym> SYM
%token <Implementation_.implementation_constant> IMPL
%token <Undefined.undefined_behaviour> UB

(* ctype tokens *)
%token VOID ATOMIC (* SIZE_T INTPTR_T PTRDIFF_T WCHAR_T CHAR16_T CHAR32_T *) (* DOTS *)
%token ICHAR SHORT INT LONG LONG_LONG
%token CHAR BOOL SIGNED UNSIGNED
%token INT8_T INT16_T INT32_T INT64_T UINT8_T UINT16_T UINT32_T UINT64_T
%token STRUCT UNION

(* C11 memory orders *)
%token SEQ_CST RELAXED RELEASE ACQUIRE CONSUME ACQ_REL

(* definition keywords *)
%token DEF GLOB FUN PROC

(* Core types *)
%token INTEGER FLOATING BOOLEAN POINTER CTYPE CFUNCTION UNIT EFF LOADED

(* Core constant keywords *)
%token TRUE FALSE
%token ARRAY_SHIFT MEMBER_SHIFT
%token UNDEF ERROR
%token<string> STRING
%token SKIP IF THEN ELSE
%nonassoc ELSE


(* Core exception operators *)
%token RAISE REGISTER (* TRY WITH PIPE MINUS_GT *)

(* Core sequencing operators *)
%token LET LETW LETS LETA UNSEQ IN END INDET RETURN PURE PCALL
%nonassoc IN DOT


%token DQUOTE LPAREN RPAREN LBRACKET RBRACKET COLON_EQ COLON (* SEMICOLON *) COMMA LBRACE RBRACE NEG

%token IS_INTEGER IS_SIGNED IS_UNSIGNED IS_SCALAR

(* unary operators *)
%token NOT

(* binary operators *)
%token STAR SLASH REM_T REM_F MINUS EQ PLUS CARET

(* boolean operators *)
%token GT LT GE LE

(* logical operators *)
%token SLASH_BACKSLASH BACKSLASH_SLASH

(* memory actions *)
%token CREATE ALLOC STORE LOAD KILL RMW

(* continuation operators *)
%token SAVE RUN DOT

(* binder patterns *)
%token UNDERSCORE

%token ND PAR 


(* integer values *)
%token IVMAX IVMIN IVSIZEOF IVALIGNOF CFUNCTION_VALUE
%token NIL CONS TUPLE ARRAY LOADED_VALUE UNSPECIFIED

%token CASE PIPE EQ_GT OF

(* TODO: not used yet, but the tracing mode of the parser crash othewise ..... *)
(*
%token FLOAT DOUBLE LONG_DOUBLE STRUCT UNION ENUM FUNCTION
RETURN   PROC CASE OF  TILDE PIPES PIPE MINUS_GT LBRACE RBRACE LBRACES RBRACES LANGLE RANGLE DOT SEMICOLON
 *)


%right BACKSLASH_SLASH
%right SLASH_BACKSLASH
%left EQ GT LT GE LE
%left PLUS MINUS
%left STAR SLASH REM_T REM_F
%nonassoc CARET

(* %right ELSE (* TODO: CHECK !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! *) *)


(* HIP
%token CREATE ALLOC KILL STORE LOAD COMPARE_EXCHANGE_STRONG COMPARE_EXCHANGE_WEAK
%token <string> SYM
%token <Core.name> NAME
%token <Implementation_.implementation_constant> IMPL
%token SKIP RETURN
%token NOT
%token TRUE FALSE
%token LET STRONG WEAK ATOM IN
%token DEF FUN PROC END
%token SAVE RUN
%token PLUS MINUS STAR SLASH PERCENT
%token EQ LT LE
%token SLASH_BACKSLASH BACKSLASH_SLASH
%token TILDE
%token EXCLAM
%token PIPE PIPE_PIPE SEMICOLON
%token UNDERSCORE
%token LANGLE RANGLE
%token LT_MINUS MINUS_GT
%token LPAREN RPAREN LBRACE RBRACE LBRACKET RBRACKET DOT DOTS COMMA COLON COLON_EQ LBRACES RBRACES PIPES
%token SAME
%token UNDEF ERROR
%token IF THEN ELSE
%token CASE OF
%token INTEGER BOOLEAN ADDRESS CTYPE UNIT

(* TODO: temporary *)
%token IS_SCALAR IS_INTEGER IS_SIGNED IS_UNSIGNED

(* Memory orders *)
%token SEQ_CST RELAXED RELEASE ACQUIRE CONSUME ACQ_REL

(* ctype tokens *)
%token ATOMIC SHORT INT LONG LONG_LONG
%token BOOL SIGNED UNSIGNED FLOAT DOUBLE LONG_DOUBLE COMPLEX ICHAR CHAR VOID STRUCT UNION ENUM
%token SIZE_T INTPTR_T WCHAR_T CHAR16_T CHAR32_T

 *)


%token EOF

(* HIP
%left SLASH_BACKSLASH BACKSLASH_SLASH
%left ELSE
%left NOT
%left PLUS MINUS
%left STAR SLASH PERCENT
%left EQ LT LE
 *)


%type<Core_parser_util._sym Core.generic_value>
  value
%type<(unit, Core_parser_util._sym) Core.generic_pexpr>
  pexpr
%type<(unit, unit, Core_parser_util._sym) Core.generic_expr>
  expr


%start <Core_parser_util.result>start
%parameter <M : sig
                  val sym_counter: int ref
                  val std: (Core_parser_util._sym, Core.sym) Pmap.map
                end>

%%

(*
n_ary_operator(separator, X):
  x1 = X separator x2 = X
    { [ x1; x2 ] }
| x = X; separator; xs = n_ary_operator(separator, X)
    { x :: xs }

delimited_nonempty_list(opening, separator, X, closing):
  opening x= X closing
   { [x] }
| xs = delimited(opening, n_ary_operator(separator, X),
  closing)
   { xs }
*)

start:
| decls= nonempty_list(declaration) EOF
    { mk_file decls }
;


(* BEGIN Ail types *)
integer_base_type:
| ICHAR
    { AilTypes.Ichar }
| SHORT
    { AilTypes.Short }
| INT
    { AilTypes.Int_ }
| LONG
    { AilTypes.Long }
| LONG_LONG
    { AilTypes.LongLong }
;

integer_type:
| CHAR
    { AilTypes.Char }
| BOOL
    { AilTypes.Bool }
| INT8_T
    { AilTypes.Signed (AilTypes.IntN_t 8) }
| INT16_T
    { AilTypes.Signed (AilTypes.IntN_t 16) }
| INT32_T
    { AilTypes.Signed (AilTypes.IntN_t 32) }
| INT64_T
    { AilTypes.Signed (AilTypes.IntN_t 64) }
| UINT8_T
    { AilTypes.Unsigned (AilTypes.IntN_t 8) }
| UINT16_T
    { AilTypes.Unsigned (AilTypes.IntN_t 16) }
| UINT32_T
    { AilTypes.Unsigned (AilTypes.IntN_t 32) }
| UINT64_T
    { AilTypes.Unsigned (AilTypes.IntN_t 64) }
| SIGNED ibty= integer_base_type
    { AilTypes.Signed ibty }
| UNSIGNED ibty= integer_base_type
    { AilTypes.Unsigned ibty }
;

basic_type:
| ity= integer_type
    { AilTypes.Integer ity }
;

ctype:
| VOID
    { Core_ctype.Void0 }
| bty= basic_type
    { Core_ctype.Basic0 bty }
| ty= ctype LBRACKET n_opt= INT_CONST? RBRACKET
    { Core_ctype.Array0 (ty, n_opt) }
| ty= ctype tys= delimited(LPAREN, separated_list(COMMA, ctype), RPAREN)
    { Core_ctype.Function0 (ty, List.map (fun ty -> (AilTypes.no_qualifiers, ty)) tys, false) }
(* TODO *)
(* | ty= ctype LPAREN tys= separated_list(COMMA, ctype) COMMA DOTS RPAREN *)
(*     { Core_ctype.Function0 (ty, tys, true) } *)
| ty= ctype STAR
    { Core_ctype.Pointer0 (AilTypes.no_qualifiers, ty) }
| ATOMIC ty= delimited(LPAREN, ctype, RPAREN)
    { Core_ctype.Atomic0 ty }
| (* TODO: check the lexing *) str= SYM
    { match Builtins.translate_builtin_typenames ("__cerbty_" ^ fst str) with
        | Some ty ->
            Core_aux.proj_ctype ty
        | None ->
            $syntaxerror
    }
;
(* END Ail types *)


core_object_type:
| INTEGER
    { OTy_integer }
| FLOATING
    { OTy_floating }
| POINTER
    { OTy_pointer }
| CFUNCTION
    { OTy_cfunction }
| ARRAY oTy= delimited(LPAREN, core_object_type, RPAREN)
    { OTy_array oTy }
(*
| STRUCT tag= SYM
    { OTy_struct tag }
| UNION tag= SYM
    { OTy_union tag }
*)
;

core_base_type:
| UNIT
    { BTy_unit }
| BOOLEAN
    { BTy_boolean }
| CTYPE
    { BTy_ctype }
| baseTy= delimited(LBRACKET, core_base_type, RBRACKET)
    { BTy_list baseTy }
| baseTys= delimited(LPAREN, separated_list(COMMA, core_base_type), RPAREN)
    { BTy_tuple baseTys }
| oTy= core_object_type
    { BTy_object oTy }
| LOADED oTy= core_object_type
    { BTy_loaded oTy }
;

core_type:
| baseTy = core_base_type
    { TyBase baseTy }
| EFF baseTy= core_base_type
    { TyEffect baseTy }
;


%inline binary_operator:
| PLUS            { OpAdd   }
| MINUS           { OpSub   }
| STAR            { OpMul   }
| SLASH           { OpDiv   }
| REM_T           { OpRem_t }
| REM_F           { OpRem_f }
| CARET           { OpExp   }
| EQ              { OpEq    }
| GT              { OpGt    }
| LT              { OpLt    }
| GE              { OpGe    }
| LE              { OpLe    }
| SLASH_BACKSLASH { OpAnd   }
| BACKSLASH_SLASH { OpOr    }
;


name:
| _sym= SYM
    { Sym _sym }
| i= IMPL
    { Impl i }
;






memory_order:
| SEQ_CST { Cmm.Seq_cst }
| RELAXED { Cmm.Relaxed }
| RELEASE { Cmm.Release }
| ACQUIRE { Cmm.Acquire }
| CONSUME { Cmm.Consume }
| ACQ_REL { Cmm.Acq_rel }
;



ctor:
| NIL
    { Cnil () }
| CONS
    { Ccons }
| TUPLE
    { Ctuple }
| ARRAY
    { Carray }
| IVMAX
    { Civmax }
| IVMIN
    { Civmin }
| IVSIZEOF
    { Civsizeof }
| IVALIGNOF
    { Civalignof }
| LOADED_VALUE
    { Cloaded }
| UNSPECIFIED
    { Cunspecified }


pattern:
| _sym= SYM
    { CaseBase (Some _sym) }
| UNDERSCORE
    { CaseBase None }
| ctor=ctor _pats= delimited(LPAREN, separated_list(COMMA, pattern), RPAREN)
    { CaseCtor (ctor, _pats) }
(* Syntactic sugar for tuples and lists *)
| LPAREN _pat= pattern COMMA _pats= separated_nonempty_list(COMMA, pattern) RPAREN
    { CaseCtor (Ctuple, _pat :: _pats) }
;

pattern_pair(X):
| PIPE _pat= pattern EQ_GT _body= X
    { (_pat, _body) }

(*
typed_expr:
| _e= expr COLON bTy= core_base_type
  { (_e, bTy) }
*)


value:
(* TODO:
  | Vconstrained of list (list Mem.mem_constraint * generic_value 'sym)
  | Vobject of generic_object_value 'sym
  | Vloaded of generic_object_value 'sym
  | Vunspecified of ctype
*)
| n= INT_CONST
    { Vobject (OVinteger (Mem.integer_ival0 n)) }
| CFUNCTION_VALUE _nm= delimited(LPAREN, name, RPAREN)
  { Vobject (OVcfunction _nm) }
| UNIT
    { Vunit }
| TRUE
    { Vtrue }
| FALSE
    { Vfalse }
| ty= delimited(DQUOTE, ctype, DQUOTE)
    { Vctype ty }



pexpr:
| _pe= delimited(LPAREN, pexpr, RPAREN)
    { _pe }
| UNDEF LPAREN ub= UB RPAREN
    { Pexpr ((), PEundef ub) }
| ERROR LPAREN str= STRING COMMA _pe= pexpr RPAREN
    { Pexpr ((), PEerror (str, _pe))  }
| _cval= value
    { Pexpr ((), PEval _cval) }
(*
  | PEconstrained of list (list Mem.mem_constraint * generic_pexpr 'ty 'sym)
*)
| str= SYM
    { Pexpr ((), PEsym str) }
| iCst= IMPL
    { Pexpr ((), PEimpl iCst) }
(* Syntactic sugar for tuples and lists *)
| LPAREN _pe= pexpr COMMA _pes= separated_nonempty_list(COMMA, pexpr) RPAREN
    { Pexpr ((), PEctor (Ctuple, _pe :: _pes)) }
| _pes= delimited(LBRACKET, separated_list(COMMA, pexpr) , RBRACKET)
    { mk_list_pe _pes }
| ctor= ctor _pes= delimited(LPAREN, separated_list(COMMA, pexpr), RPAREN)
    { Pexpr ((), PEctor (ctor, _pes)) }
| CASE _pe= pexpr OF _pat_pes= list(pattern_pair(pexpr)) END
    { Pexpr ((), PEcase (_pe, _pat_pes)) }
| ARRAY_SHIFT LPAREN _pe1= pexpr COMMA ty= delimited(DQUOTE, ctype, DQUOTE) COMMA _pe2= pexpr RPAREN
    { Pexpr ((), PEarray_shift (_pe1, ty, _pe2)) }
(*
| MEMBER_SHIFT LPAREN _pe1= pexpr COMMA _sym= SYM COMMA RPAREN
*)
| NOT _pe= delimited(LPAREN, pexpr, RPAREN)
    { Pexpr ((), PEnot _pe) }
| MINUS _pe= pexpr
    { Pexpr ((), PEop (OpSub, Pexpr ((), PEval (Vobject (OVinteger (Mem.integer_ival0 (Nat_big_num.of_int 0))))), _pe)) }
| _pe1= pexpr bop= binary_operator _pe2= pexpr
    { Pexpr ((), PEop (bop, _pe1, _pe2)) }
(*
  | PEmemop of Mem.pure_memop * list (generic_pexpr 'ty 'sym)
  | PEstruct of Symbol.t * list (Cabs.cabs_identifier * generic_pexpr 'ty 'sym)
*)
| nm= name _pes= delimited(LPAREN, separated_list(COMMA, pexpr), RPAREN)
    { Pexpr ((), PEcall (nm, _pes)) }
| LET _pat= pattern EQ _pe1= pexpr IN _pe2= pexpr
    { Pexpr ((), PElet (_pat, _pe1, _pe2)) }
| IF _pe1= pexpr THEN _pe2= pexpr ELSE _pe3= pexpr
    { Pexpr ((), PEif (_pe1, _pe2, _pe3)) }
| IS_SCALAR _pe= delimited(LPAREN, pexpr, RPAREN)
    { Pexpr ((), PEis_scalar _pe) }
| IS_INTEGER _pe= delimited(LPAREN, pexpr, RPAREN)
    { Pexpr ((), PEis_integer _pe) }
| IS_SIGNED _pe= delimited(LPAREN, pexpr, RPAREN)
    { Pexpr ((), PEis_signed _pe) }
| IS_UNSIGNED _pe= delimited(LPAREN, pexpr, RPAREN)
    { Pexpr ((), PEis_unsigned _pe) }
;


expr:
| PURE pe_= delimited(LPAREN, pexpr, RPAREN)
    { Epure pe_ }
(*
  | Ememop of Mem.memop * list (generic_pexpr 'ty 'sym)
*)
| SKIP
    { Eskip }
| LET _pat= pattern EQ _pe1= pexpr IN _e2= expr
    { Elet (_pat, _pe1, _e2) }
| IF _pe1= pexpr THEN _e2= expr ELSE _e3= expr
    { Eif (_pe1, _e2, _e3) }
| CASE _pe= pexpr OF _pat_es= list(pattern_pair(expr)) END
    { Ecase (_pe, _pat_es) }
| PCALL LPAREN _pe= pexpr COMMA _pes= separated_list(COMMA, pexpr) RPAREN
    { Core.Eproc ((), _pe, _pes) }
| _pact= paction
    { Eaction _pact }
| UNSEQ _es= delimited(LPAREN, separated_list(COMMA, expr), RPAREN)
    { Eunseq _es }
| LETW _pat= pattern EQ _e1= expr IN _e2= expr
    { Ewseq (_pat, _e1, _e2) }
| LETS _pat= pattern EQ _e1= expr IN _e2= expr
    { Esseq (_pat, _e1, _e2) }
(*
  | Easeq of maybe (Symbol.t * core_base_type) * generic_action 'a 'ty 'sym * generic_paction 'a 'ty 'sym
| Eindet of generic_expr 'a 'ty 'sym
  | Ebound of nat * generic_expr 'a 'ty 'sym
  | Esave of ksym * list (Symbol.t * ctype) * generic_expr 'a 'ty 'sym
  | Erun of 'a * ksym * list (Symbol.t * generic_pexpr 'ty 'sym)
  *)
| RETURN _pe= delimited(LPAREN, pexpr, RPAREN)
    { Ereturn _pe }
| ND _es= delimited(LPAREN, separated_list(COMMA, expr), RPAREN)
    { End _es }
| PAR _es= delimited(LPAREN, separated_list(COMMA, expr), RPAREN)
    { Epar _es }
(*
  | Ewait of Thread.thread_id
*)
;

action:
| CREATE LPAREN _pe1= pexpr COMMA _pe2= pexpr RPAREN
    { Create (_pe1, _pe2, Symbol.PrefOther "Core") }
| ALLOC LPAREN _pe1= pexpr COMMA _pe2= pexpr RPAREN
    { Alloc0 (_pe1, _pe2, Symbol.PrefOther "Core") }
| KILL _pe= delimited(LPAREN, pexpr, RPAREN)
    { Kill _pe }
| STORE LPAREN _pe1= pexpr COMMA _pe2= pexpr COMMA _pe3= pexpr RPAREN
    { Store0 (_pe1, _pe2, _pe3, Cmm.NA) }
| LOAD LPAREN _pe1= pexpr COMMA _pe2= pexpr RPAREN
    { Load0 (_pe1, _pe2, Cmm.NA) }
| STORE LPAREN _pe1= pexpr COMMA _pe2= pexpr COMMA _pe3= pexpr COMMA mo= memory_order RPAREN
    { Store0 (_pe1, _pe2, _pe3, mo) }
| LOAD LPAREN _pe1= pexpr COMMA _pe2= pexpr COMMA mo= memory_order RPAREN
    { Load0 (_pe1, _pe2, mo) }
| RMW LPAREN _pe1= pexpr COMMA _pe2= pexpr COMMA _pe3= pexpr COMMA _pe4= pexpr COMMA mo1= memory_order COMMA mo2= memory_order RPAREN
    { RMW0 (_pe1, _pe2, _pe3, _pe4, mo1, mo2) }
;

paction:
| act= action
    { Paction (Pos, Action (Location_ocaml.unknown, (), act)) }
| NEG act= delimited(LPAREN, action, RPAREN)
    { Paction (Neg, Action (Location_ocaml.unknown, (), act)) }
;





















(*



| _es= delimited(LBRACKET, separated_list(COMMA, expr), RBRACKET)
(*    { Vlist _es } *)
    { List.fold_right (fun _e acc -> PEctor (Core.Ccons, [_e; acc])) _es (Vlist []) }
| LPAREN _e= expr COMMA _es= separated_nonempty_list(COMMA, expr) RPAREN
    { PEtuple (_e::_es) }
(*
| ARRAY _es= delimited(LPAREN, separated_nonempty_list(COMMA, expr), RPAREN)
    { PEarray _es }
*)




(*
| SHIFT LPAREN _e= expr COMMA sh= delimited(LBRACE, separated_nonempty_list(COMMA, shift_elem), RBRACE) RPAREN
    { PEshift (_e, sh) }
*)
| ARRAY_SHIFT LPAREN e1= expr COMMA ty= delimited(DQUOTE, ctype, DQUOTE) COMMA e2= expr RPAREN
    { PEarray_shift (e1, ty, e2) }
(*
| MEMBER_SHIFT LPAREN e= expr COMMA sym= SYM COMMA e2= expr RPAREN
    { PEarray_shift (e1, ty, e2) }
*)
| NOT _e= delimited(LPAREN, expr, RPAREN)
    { PEnot _e }
(*
| _e1= expr LE _e2= expr
    { Eif (PEop (Core.OpLt, _e1, _e2), Vtrue, PEop (Core.OpEq, _e1, _e2)) }
*)
| MINUS _e= expr
    { PEop (Core.OpSub, Vinteger (Nat_big_num.of_int 0), _e) }
| _e1= expr bop= binary_operator _e2= expr
    { PEop (bop, _e1, _e2) }
(* TODO: these are temporary *)
| IS_SCALAR _e= delimited(LPAREN, expr, RPAREN)
    { Core.PEis_scalar _e }
| IS_INTEGER _e= delimited(LPAREN, expr, RPAREN)
    { Core.PEis_integer _e }
| IS_SIGNED _e= delimited(LPAREN, expr, RPAREN)
    { Core.PEis_signed _e }
| IS_UNSIGNED _e= delimited(LPAREN, expr, RPAREN)
    { Core.PEis_unsigned _e }

expr:
(* BEGIN: effectful *)
| RAISE str= delimited(LPAREN, SYM (* TODO: hack *), RPAREN)
    { Core.Eraise str }
| REGISTER LPAREN str= SYM COMMA nm= name RPAREN
    { Core.Eregister (str, nm) }
| SKIP
    { Core.Eskip }
| LET str= SYM EQ _e1= expr IN _e2= expr END
    { Core.Elet (str, _e1, _e2) }
| IF _e1= expr THEN _e2= expr ELSE _e3= expr END
    { Core.Eif (_e1, _e2, _e3) }
| PCALL LPAREN _e= expr COMMA _es= separated_list(COMMA, expr) RPAREN
    { Core.Eproc (_e, _es) }
| pact= paction
    { Eaction pact }
| UNSEQ _es= delimited(LPAREN, separated_nonempty_list(COMMA, expr), RPAREN)
    { Core.Eunseq _es }
| LET STRONG _pat= pattern EQ _e1= expr IN _e2= expr END
    { Core.Esseq (_pat, _e1, _e2) }
| LET WEAK _pat= pattern EQ _e1= expr IN _e2= expr END
    { Core.Ewseq (_as, _e1, _e2) }
(* TODO
| LET ATOM empty_pattern EQ act1= action IN pact2= paction
    { Easeq (None, act1, pact2) }
*)
| LET ATOM str= SYM EQ act1= action IN pact2= paction
    { Easeq (Some str, act1, pact2) }
| INDET _e= delimited(LPAREN, expr, RPAREN)
    { Core.Eindet _e }
(*
WIP  | Ebound of int * expr
*)
| SAVE str= SYM str_tys= delimited(LPAREN, separated_list(COMMA, separated_pair(SYM, COLON, ctype)), RPAREN) DOT _e= expr END
    { Esave (str, str_tys, _e) }
| RUN d= SYM str__es= delimited(LPAREN, separated_list(COMMA, separated_pair(SYM, COLON, expr)), RPAREN)
    { Core.Erun (d, str__es) }
| RETURN _pe= delimited(LPAREN, pexpr, RPAREN)
    { Core.Ereturn _pe }
| ND _es= delimited(LPAREN, separated_list(COMMA, expr), RPAREN)
    { Core.End _es }
| PAR _es= delimited(LPAREN, separated_list(COMMA, expr), RPAREN)
    { Core.Epar _es }
(*
WIP  | Ewait of Thread.thread_id
*)
| LPAREN _e= expr RPAREN
    { _e }
;

(*
shift_elem:
| LPAREN ty= delimited(DQUOTE, ctype, DQUOTE) COMMA _e= expr RPAREN
  { (ty, _e) }
;
*)



























action:
| CREATE LPAREN e1= expr COMMA e2= expr RPAREN
    { Create (e1, e2) }
| ALLOC LPAREN e1= expr COMMA e2= expr RPAREN
    { Alloc (e1, e2) }
| KILL e= delimited(LPAREN, expr, RPAREN)
    { Kill e }
| STORE LPAREN e1= expr COMMA e2= expr COMMA e3= expr RPAREN
    { Store (e1, e2, e3, Cmm.NA) }
| LOAD LPAREN e1= expr COMMA e2= expr RPAREN
    { Load (e1, e2, Cmm.NA) }
| STORE LPAREN e1= expr COMMA e2= expr COMMA e3= expr COMMA mo= memory_order RPAREN
    { Store (e1, e2, e3, mo) }
| LOAD LPAREN e1= expr COMMA e2= expr COMMA mo= memory_order RPAREN
    { Load (e1, e2, mo) }
| RMW LPAREN e1= expr COMMA e2= expr COMMA e3= expr COMMA e4= expr COMMA mo1= memory_order COMMA mo2= memory_order RPAREN
    { RMW (e1, e2, e3, e4, mo1, mo2) }
;

paction:
| act= action
    { (Core.Pos, act) }
| TILDE act= action
    { (Core.Neg, act) }
;

(*
pattern_elem:
| UNDERSCORE    { None   }
(* | LPAREN RPAREN { None   } (\* TODO: add a new constructor in the Ast for better type/syntax checking *\) *)
| a= SYM        { Some a }
;

pattern:
(* | _as= delimited_nonempty_list(LPAREN, COMMA, pattern_elem, RPAREN) *)
| sym= SYM
    { [Some sym] }
| LPAREN _as= separated_nonempty_list(COMMA, pattern_elem) RPAREN
    { _as }
;

empty_pattern:
| LPAREN RPAREN
| UNDERSCORE
    { }
;
*)


(*
try_clauses:
| PIPE str= SYM (* TODO: hack *) MINUS_GT e= expr
    { [(str, e)] }
| str= SYM (* TODO: hack *) MINUS_GT e= expr str_es= try_clauses
    { (str, e) :: str_es }
*)


(*
expr_old:
| e= delimited(LPAREN, expr, RPAREN)
    { e }
| UNIT
    { Eunit }
(*
| NULL
    { Enull }
*)
| TRUE
    { Etrue }
| FALSE
    { Efalse }
(* TODO: other constants *)
| cst= constant
    { Econst cst }

| LIST LPAREN es= separated_list(COMMA, expr) RPAREN
    { Elist es }
| CONS LPAREN pe1= expr COMMA pe2= expr RPAREN
    { Econs (pe1, pe2) }

| ty= delimited(DQUOTE, ctype, DQUOTE)
    { Ectype ty }
(* TODO
| Eaddr of Memory.mem_addr
*)
| a= SYM
    { Esym a }
| i= IMPL
    { Eimpl i }
| LPAREN e= expr COMMA es= separated_nonempty_list(COMMA, expr) RPAREN
    { Etuple (e::es) }
| NOT e = delimited(LPAREN, expr, RPAREN)
    { Enot e }
(* some sugar *)
| e1= expr LE e2= expr
    { Eop (Core.OpOr, Eop (Core.OpLt, e1, e2), Eop (Core.OpEq, e1, e2)) }
| e1= expr bop= binary_operator e2= expr
    { Eop (bop, e1, e2) }
| f= name es= delimited(LPAREN, separated_list(COMMA, expr), RPAREN)
    { Ecall (f, es) }
| UNDEF ub= UB
    { Eundef ub }
| ERROR str= STRING
    { Eerror str }
| RAISE LPAREN evnt= SYM (* TODO: hack *) RPAREN
    { Eraise evnt }


| SHIFT LPAREN pe= expr COMMA sh= delimited(LBRACE, separated_nonempty_list(COMMA, shift_elem), RBRACE) RPAREN
    { Eshift (pe, sh) }

(*
| TRY e= expr WITH str_es= try_clauses END
    { Etry (e, str_es) }
*)
| REGISTER LPAREN evnt= SYM COMMA nm= name RPAREN
    { Eregister (evnt, nm) }
| SKIP
    { Eskip }
| LET a= SYM EQ e1= expr IN e2= expr END
    { Elet (a, e1, e2) }
| IF b= expr THEN e1= expr ELSE e2= expr END
    { Eif (b, e1, e2) }
(* TODO: temporary restricted version *)
| CASE_CTYPE LPAREN e= expr COMMA f_void= name COMMA f_basic= name COMMA f_array= name COMMA
                 f_fun= name COMMA f_ptr= name COMMA f_atom= name COMMA f_struct= name COMMA f_union= name COMMA f_builtin= name RPAREN
    { Ecase (e, f_void, f_basic, f_array, f_fun, f_ptr, f_atom, f_struct, f_union, f_builtin) }


| f= name es= delimited(LBRACE, separated_list(COMMA, expr), RBRACE)
    { Eproc (f, es) }
(* HIP
  | Esame of expr 'a * expr 'a

 *)
| p= paction
    { Eaction p }
| es= delimited(LBRACKET, separated_nonempty_list(PIPE_PIPE, expr), RBRACKET)
    { Eunseq es }
(*
| e1= expr SEMICOLON e2= expr
    { Esseq ([], e1, e2) }
*)
| LET STRONG _as= pattern EQ e1= expr IN e2= expr END
    { Esseq (_as, e1, e2) }
| LET STRONG LPAREN RPAREN EQ e1= expr IN e2= expr END
    { Esseq ([], e1, e2) }
| LET WEAK _as= pattern EQ e1= expr IN e2= expr END
    { Ewseq (_as, e1, e2) }
| LET WEAK LPAREN RPAREN EQ e1= expr IN e2= expr END
    { Ewseq ([], e1, e2) }
| LET ATOM LPAREN RPAREN EQ a= action IN p= paction END
    { Easeq (None, a, p) }
| LET ATOM _a= SYM EQ a= action IN p= paction END
    { Easeq (Some _a, a, p) }
| INDET e= delimited(LPAREN, expr, RPAREN)
    { Eindet e }
(*
  | Ebound of natural * expr 'a (* this ctor doesn't exist at runtine *)
*)
| SAVE d= SYM a_tys= delimited(LPAREN, separated_list(COMMA, separated_pair(SYM, COLON, ctype)), RPAREN) DOT e= expr END
    { Esave (d, a_tys, e) }
| RUN d= SYM a_es= delimited(LPAREN, separated_list(COMMA, separated_pair(SYM, COLON, expr)), RPAREN)
    { Erun (d, a_es) }
| RETURN e= delimited(LPAREN, expr, RPAREN)
    { Eret e }

| ND es= delimited(LPAREN, separated_list(COMMA, expr), RPAREN)
    { End es }
| PAR es= delimited(LPAREN, separated_list(COMMA, expr), RPAREN)
    { Epar es }


(*  HIP
  | Ewait
*)
(* TODO: these are temporary *)
| IS_SCALAR LPAREN e= expr RPAREN
    { Eis_scalar e }
| IS_INTEGER LPAREN e= expr RPAREN
    { Eis_integer e }
| IS_SIGNED LPAREN e= expr RPAREN
    { Eis_signed e }
| IS_UNSIGNED LPAREN e= expr RPAREN
    { Eis_unsigned e }
*)
*)


def_declaration:
| DEF dname= IMPL COLON bTy= core_base_type COLON_EQ pe_= pexpr
    { Def_decl (dname, bTy, pe_) }
;

ifun_declaration:
| FUN fname= IMPL params= delimited(LPAREN, separated_list(COMMA, separated_pair(SYM, COLON, core_base_type)), RPAREN)
  COLON bTy= core_base_type
  COLON_EQ fbody= pexpr
    { IFun_decl (fname, (bTy, params, fbody)) }
;

glob_declaration:
| GLOB gname= SYM COLON cTy= core_type COLON_EQ e= expr
  { Glob_decl (gname, cTy, e) }
;

fun_declaration:
| FUN fname= SYM params= delimited(LPAREN, separated_list(COMMA, separated_pair(SYM, COLON, core_base_type)), RPAREN)
  COLON bTy= core_base_type
  COLON_EQ fbody= pexpr
    { Fun_decl (fname, (bTy, params, fbody)) }
;

proc_declaration:
| PROC _sym= SYM params= delimited(LPAREN, separated_list(COMMA, separated_pair(SYM, COLON, core_base_type)), RPAREN)
  COLON EFF bTy= core_base_type
  COLON_EQ fbody= expr
    { Proc_decl (_sym, (bTy, params, fbody)) }
;


declaration:
| d= def_declaration
| d= ifun_declaration
| d= glob_declaration
| d= fun_declaration
| d= proc_declaration
    { d }

%%
