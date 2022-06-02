module CF=Cerb_frontend
module RE = Resources
module RET = ResourceTypes
module IT = IndexTerms
module BT = BaseTypes
module LS = LogicalSorts
module LRT = LogicalReturnTypes
module RT = ReturnTypes
module AT = ArgumentTypes
module LAT = LogicalArgumentTypes
module TE = TypeErrors
module SymSet = Set.Make(Sym)
module SymMap = Map.Make(Sym)
module S = Solver
module Loc = Locations
module LP = LogicalPredicates

open Tools
open Sctypes
open Context
open Global

open IT
open TypeErrors
module Mu = Retype.New
open CF.Mucore
open Mu

open Pp
open BT
open Resources
open ResourceTypes
open ResourcePredicates
open LogicalConstraints

open List





(* some of this is informed by impl_mem *)



(*** mucore pp setup **********************************************************)

module PP_TYPS = struct
  module T = Retype.SR_Types
  let pp_bt = BT.pp 
  let pp_ct ct = Sctypes.pp ct
  let pp_ft = AT.pp RT.pp
  let pp_gt = pp_ct
  let pp_lt = AT.pp False.pp
  let pp_ut _ = Pp.string "todo: implement union type printer"
  let pp_st _ = Pp.string "todo: implement struct type printer"
end

module PP_MUCORE = CF.Pp_mucore.Make(CF.Pp_mucore.Basic)(PP_TYPS)
(* let pp_budget () = Some !debug_level *)
let pp_budget () = Some (!print_level*5)
let pp_pexpr e = PP_MUCORE.pp_pexpr e
let pp_tpexpr e = PP_MUCORE.pp_tpexpr (pp_budget ()) e
let pp_expr e = PP_MUCORE.pp_expr e
let pp_texpr e = PP_MUCORE.pp_texpr (pp_budget ()) e


open Typing
open Effectful.Make(Typing)



type mem_value = CF.Impl_mem.mem_value
type pointer_value = CF.Impl_mem.pointer_value




(*** pattern matching *********************************************************)


(* pattern-matches and binds *)
let pattern_match = 

  let rec aux pat : (IT.t, type_error) m = 
    let (M_Pattern (loc, _, pattern) : mu_pattern) = pat in
    match pattern with
    | M_CaseBase (o_s, has_bt) ->
       let@ () = WellTyped.WBT.is_bt loc has_bt in
       let lsym = Sym.fresh () in 
       let@ () = add_l lsym has_bt in
       begin match o_s with
       | Some s -> 
          let@ () = add_a s (has_bt, lsym) in
          return (sym_ (lsym, has_bt))
       | None -> 
          return (sym_ (lsym, has_bt))
       end
    | M_CaseCtor (constructor, pats) ->
       match constructor, pats with
       | M_Cnil item_bt, [] ->
          let@ () = WellTyped.WBT.is_bt loc item_bt in
          return (IT.nil_ ~item_bt)
       | M_Cnil item_bt, _ ->
          let@ () = WellTyped.WBT.is_bt loc item_bt in
          fail (fun _ -> {loc; msg = Number_arguments {has = List.length pats; expect = 0}})
       | M_Ccons, [p1; p2] ->
          let@ it1 = aux p1 in
          let@ it2 = aux p2 in
          let@ () = WellTyped.ensure_base_type loc ~expect:(List (IT.bt it1)) (IT.bt it2) in
          return (cons_ (it1, it2))
       | M_Ccons, _ -> 
          fail (fun _ -> {loc; msg = Number_arguments {has = List.length pats; expect = 2}})
       | M_Ctuple, pats ->
          let@ its = ListM.mapM aux pats in
          return (tuple_ its)
       | M_Cspecified, [pat] ->
          aux pat
       | M_Cspecified, _ ->
          fail (fun _ -> {loc; msg = Number_arguments {expect = 1; has = List.length pats}})
       | M_Carray, _ ->
          Debug_ocaml.error "todo: array types"
  in

  fun to_match ((M_Pattern (loc, _, _)) as pat : mu_pattern) ->
  let@ it = aux pat in
  let@ () = WellTyped.ensure_base_type loc ~expect:(IT.bt to_match) (IT.bt it) in
  add_c (t_ (eq_ (it, to_match)))





let rec bind_logical where (lrt : LRT.t) = 
  match lrt with
  | Define ((s, it), oinfo, rt) ->
     let s, rt = LRT.alpha_rename (s, IT.bt it) rt in
     let@ () = add_l s (IT.bt it) in
     let@ () = add_c (LC.t_ (IT.def_ s it)) in
     bind_logical where rt
  | Resource ((s, (re, oarg_spec)), _oinfo, rt) -> 
     let s, rt = LRT.alpha_rename (s, oarg_spec) rt in
     let@ () = add_l s oarg_spec in
     let@ () = add_r where (re, O (sym_ (s, oarg_spec))) in
     bind_logical where rt
  | Constraint (lc, _oinfo, rt) -> 
     let@ () = add_c lc in
     bind_logical where rt
  | I -> 
     return ()

let bind_computational where (name : Sym.t) (rt : RT.t) =
  let Computational ((s, bt), _oinfo, rt) = rt in
  let s' = Sym.fresh () in
  let rt' = LRT.subst (IT.make_subst [(s, IT.sym_ (s', bt))]) rt in
  let@ () = add_l s' bt in
  let@ () = add_a name (bt, s') in
  bind_logical where rt'


let bind where (name : Sym.t) (rt : RT.t) =
  bind_computational where name rt

let bind_logically where (rt : RT.t) : ((BT.t * Sym.t), type_error) m =
  let Computational ((s, bt), _oinfo, rt) = rt in
  let s' = Sym.fresh () in
  let rt' = LRT.subst (IT.make_subst [(s, IT.sym_ (s', bt))]) rt in
  let@ () = add_l s' bt in
  let@ () = bind_logical where rt' in
  return (bt, s')






(* The pattern-matching might de-struct 'bt'. For easily making
   constraints carry over to those values, record (lname,bound) as a
   logical variable and record constraints about how the variables
   introduced in the pattern-matching relate to (lname,bound). *)
let pattern_match_rt loc (pat : mu_pattern) (rt : RT.t) : (unit, type_error) m =
  let@ (bt, s') = bind_logically (Some loc) rt in
  pattern_match (sym_ (s', bt)) pat





(* resource inference *)

let oargs_list (O oargs) = 
  let members = match IT.bt oargs with
    | Record members -> members
    | _ -> assert false
  in
  List.map (fun (s, member_bt) ->
      (s, recordMember_ ~member_bt (oargs, s))
    ) members


module ResourceInference = struct 

  let reorder_points = ref true
  let additional_sat_check = ref true
  let span_actions = ref true

  module General = struct

    type one = {one_index : IT.t; value : IT.t}
    type many = {many_guard: IT.t; value : IT.t}

    type case =
      | One of one
      | Many of many

    let pp_case = function
      | One {one_index;value} -> 
         !^"one" ^^ parens (IT.pp one_index ^^ colon ^^^ IT.pp value)
      | Many {many_guard;value} -> 
         !^"many" ^^ parens (IT.pp many_guard ^^ colon ^^^ IT.pp value)

    type cases = C of case list


    let unfold_struct_request tag pointer_t permission_t = 
      {
        name = Owned (Struct tag);
        pointer = pointer_t;
        iargs = [];
        permission = permission_t;
      }

    let exact_ptr_match () =
      let@ global = get_global () in
      let@ values, equalities, lcs = simp_constraints () in
      let simp t = Simplify.simp global.struct_decls values equalities lcs t in
      return (fun (p, p') -> is_true (simp (eq_ (p, p'))))

    let exact_match () =
      let@ pmatch = exact_ptr_match () in
      let match_f (request, resource) =
        match (request, resource) with
        | (P req_p, 
           P res_p) ->
           pmatch (req_p.pointer, res_p.pointer)
        | (Q ({name = Owned _; _} as req_qp), 
           Q ({name = Owned _; _} as res_qp)) ->
           pmatch (req_qp.pointer, res_qp.pointer)
        | _ -> false
      in
      return match_f

    let exact_match_point_ptrs ptrs =
      let@ pmatch = exact_ptr_match () in
      let match_f resource = 
        match resource with
        | P ({name = Owned _; _} as res_p) -> 
           List.exists (fun p -> pmatch (p, res_p.pointer)) ptrs
        | _ -> false
      in
      return match_f

    let scan_key_indices v_nm t =
      let is_i t = match t with
        | IT (Lit (Sym nm2), _) -> Sym.equal nm2 v_nm
        | _ -> false
      in
      let rec f pol t = match t with
        | IT (Bool_op (And xs), _) -> List.concat (List.map (f pol) xs)
        | IT (Bool_op (Or xs), _) -> List.concat (List.map (f pol) xs)
        | IT (Bool_op (Impl (x, y)), _) -> f (not pol) x @ f pol y
        | IT (Bool_op (EQ (x, y)), _) ->
          if pol && is_i x then [y] else if pol && is_i y then [x] else []
        | IT (Bool_op (Not x), _) -> f (not pol) x
        | _ -> []
      in
      let xs = f true t in
      List.sort_uniq IT.compare xs

    
    let cases_to_map loc (situation, (orequest, oinfo)) a_bt item_bt (C cases) = 
      let update_with_ones base_array ones =
        List.fold_left (fun m {one_index; value} ->
            map_set_ m (one_index, value)
          ) base_array ones
      in
      let ones, manys = 
        List.partition_map (function One c -> Left c | Many c -> Right c) cases in
      let@ base_value = match manys with
        | [] -> return (default_ (BT.Map (a_bt, item_bt)))
        | [{many_guard = _; value}] -> return value
        | _ -> 
           let@ model = model () in
           fail (fun ctxt ->
               let msg = Merging_multiple_arrays {orequest; situation; oinfo; model; ctxt} in
               {loc; msg})
      in
      return (update_with_ones base_value ones)






    (* TODO: check that oargs are in the same order? *)
    let rec predicate_request ~recursive loc uiinfo (requested : RET.predicate_type) =
      match requested.name with
      | Owned requested_ct ->
         assert (match requested.iargs with [] -> true | _ -> false);
         debug 7 (lazy (item "point request" (RET.pp (P requested))));
         let@ _ = span_fold_unfolds loc uiinfo (RET.P requested) false in
         let start_timing = time_log_start "point-request" "" in
         let@ provable = provable loc in
         let@ is_ex = exact_match () in
         let is_exact_re (re : RET.t) = !reorder_points && (is_ex (RET.P requested, re)) in
         let@ global = get_global () in
         let@ simp_lcs = simp_constraints () in
         let needed = requested.permission in 
         let sub_resource_if = fun cond re (needed, oargs) ->
               let continue = (Unchanged, (needed, oargs)) in
               if is_false needed || not (cond (fst re)) then continue else
               match re with
               | (P p', p'_oargs) when equal_predicate_name (Owned requested_ct) p'.name ->
                  debug 15 (lazy (item "point/point sub at ptr" (IT.pp p'.pointer)));
                  let pmatch = eq_ (requested.pointer, p'.pointer) in
                  let took = and_ [pmatch; p'.permission; needed] in
                  begin match provable (LC.T took) with
                  | `True ->
                     Deleted, 
                     (bool_ false, p'_oargs)
                  | `False -> 
                     continue
                  end
               | (Q p', p'_oargs) when equal_predicate_name (Owned requested_ct) p'.name ->
                  let base = p'.pointer in
                  debug 15 (lazy (item "point/qpoint sub at base ptr" (IT.pp base)));
                  let item_size = int_ (Memory.size_of_ctype requested_ct) in
                  let offset = array_offset_of_pointer ~base ~pointer:requested.pointer in
                  let index = array_pointer_to_index ~base ~item_size ~pointer:requested.pointer in
                  let pre_match =
                    (* adapting from RE.subarray_condition *)
                    and_ [lePointer_ (base, requested.pointer);
                          divisible_ (offset, item_size)]
                  in
                  let subst = IT.make_subst [(p'.q, index)] in
                  let took = and_ [pre_match; IT.subst subst p'.permission; needed] in
                  begin match provable (LC.T took) with
                  | `True ->
                     let permission' = and_ [p'.permission; ne_ (sym_ (p'.q, Integer), index)] in
                     let oargs = 
                       List.map_snd (fun oa' -> map_get_ oa' index) 
                         (oargs_list p'_oargs)
                     in
                     Changed (Q {p' with permission = permission'}, p'_oargs), 
                     (bool_ false, O (record_ oargs))
                  | `False -> continue
                  end
               | _ ->
                  continue
         in
         let@ (needed, oargs) =
           map_and_fold_resources loc (sub_resource_if is_exact_re)
             (needed, O (default_ (owned_oargs requested_ct)))
         in
         let@ (needed, oargs) =
           map_and_fold_resources loc (sub_resource_if (fun re -> not (is_exact_re re)))
             (needed, oargs) in
         let@ res = begin match provable (t_ (not_ needed)) with
         | `True ->
            let r = ({ 
                name = Owned requested_ct;
                pointer = requested.pointer;
                iargs = [];
                permission = requested.permission 
              }, oargs)
            in
            return (Some r)
         | `False ->
            return None
         end in
         time_log_end start_timing;
         return res
      | pname -> 
         debug 7 (lazy (item "predicate request" (RET.pp (P requested))));
         let start_timing = time_log_start "predicate-request" "" in
         let@ def_oargs = match pname with
           | Block _ -> return Resources.block_oargs
           | Owned _ -> assert false
           | PName pname -> 
              let@ def = Typing.get_resource_predicate_def loc pname in
              return (Record def.oargs)
         in
         let@ provable = provable loc in
         let@ global = get_global () in
         let@ simp_lcs = simp_constraints () in
         let needed = requested.permission in 
         let sub_predicate_if = fun cond re (needed, oargs) ->
               let continue = (Unchanged, (needed, oargs)) in
               if is_false needed then continue else
               match re with
               | (P p', p'_oargs) when equal_predicate_name requested.name p'.name ->
                  let pmatch = 
                    eq_ (requested.pointer, p'.pointer)
                    :: List.map2 eq__ requested.iargs p'.iargs
                  in
                  let took = and_ (needed :: p'.permission :: pmatch) in
                  begin match provable (LC.T took) with
                  | `True ->
                     Deleted, 
                     (bool_ false, p'_oargs)
                  | `False -> continue
                  end
               | (Q p', p'_oargs) when equal_predicate_name requested.name p'.name ->
                  let base = p'.pointer in
                  let item_size = int_ p'.step in
                  let offset = array_offset_of_pointer ~base ~pointer:requested.pointer in
                  let index = array_pointer_to_index ~base ~item_size ~pointer:requested.pointer in
                  let subst = IT.make_subst [(p'.q, index)] in
                  let pre_match = 
                    (* adapting from RE.subarray_condition *)
                    and_ (lePointer_ (base, requested.pointer)
                          :: divisible_ (offset, item_size)
                          :: List.map2 (fun ia ia' -> eq_ (ia, IT.subst subst ia')) requested.iargs p'.iargs)
                  in
                  let took = and_ [pre_match; needed; IT.subst subst p'.permission] in
                  begin match provable (LC.T took) with
                  | `True ->
                     let oargs = List.map_snd (fun oa' -> map_get_ oa' index) (oargs_list p'_oargs) in
                     let i_match = eq_ (sym_ (p'.q, Integer), index) in
                     let permission' = and_ [p'.permission; not_ i_match] in
                     Changed (Q {p' with permission = permission'}, p'_oargs), 
                     (bool_ false, O (record_ oargs))
                  | `False -> continue
                  end
               | re ->
                  continue
         in
         let@ is_ex = exact_match () in
         let is_exact_re re = !reorder_points && (is_ex (P requested, re)) in
         let@ (needed, oargs) =
           map_and_fold_resources loc (sub_predicate_if is_exact_re)
               (needed, O (default_ def_oargs))
         in
         let@ (needed, oargs) =
           map_and_fold_resources loc (sub_predicate_if (fun re -> not (is_exact_re re)))
               (needed, oargs)
         in
         let@ res = begin match provable (t_ (not_ needed)) with
         | `True ->
            let r = ({ 
                name = requested.name;
                pointer = requested.pointer;
                permission = requested.permission;
                iargs = requested.iargs; 
              }, oargs)
            in
            (* let r = RE.simp_predicate ~only_outputs:true global.struct_decls all_lcs r in *)
            return (Some r)
         | `False ->
            begin match pname with
            | Block ct -> 
               let@ oresult = 
                 predicate_request ~recursive loc uiinfo 
                   ({name = Owned ct; 
                     pointer = requested.pointer;
                     iargs = [];
                     permission = requested.permission;
                    } : predicate_type)
               in
               begin match oresult with
               | None -> return None
               | Some _ -> 
                  let r = ({
                      name = requested.name;
                      pointer = requested.pointer;
                      permission = requested.permission;
                      iargs = requested.iargs;
                    }, O (record_ []))
                  in
                  return (Some r)
               end
            | _ -> 
               return None
            end
         end in
         time_log_end start_timing;
         return res


    and qpredicate_request_aux loc uiinfo (requested : RET.qpredicate_type) =
      match requested.name with
      | Owned requested_ct ->
         assert (match requested.iargs with [] -> true | _ -> false);
         debug 7 (lazy (item "qpoint request" (RET.pp (Q requested))));
         let@ _ = span_fold_unfolds loc uiinfo (RET.Q requested) false in
         let start_timing = time_log_start "qpoint-request" "" in
         let@ provable = provable loc in
         let@ is_ex = exact_match () in
         let is_exact_re re = !reorder_points && (is_ex (Q requested, re)) in
         let@ global = get_global () in
         let@ values, equalities, lcs = simp_constraints () in
         let simp t = Simplify.simp global.struct_decls values equalities lcs t in
         let needed = requested.permission in
         let sub_resource_if = fun cond re (needed, oargs) ->
               let continue = (Unchanged, (needed, oargs)) in
               if is_false needed || not (cond (fst re)) then continue else
               match re with
               | (P p', p'_oargs) when equal_predicate_name (Owned requested_ct) p'.name ->
                  let base = requested.pointer in
                  let item_size = int_ (Memory.size_of_ctype requested_ct) in
                  let offset = array_offset_of_pointer ~base ~pointer:p'.pointer in
                  let index = array_pointer_to_index ~base ~item_size ~pointer:p'.pointer in
                  let pre_match = 
                    and_ [lePointer_ (base, p'.pointer);
                          divisible_ (offset, item_size)]
                  in
                  let subst = IT.make_subst [(requested.q, index)] in
                  let took = and_ [pre_match; IT.subst subst needed; p'.permission] in
                  begin match provable (LC.T took) with
                  | `True -> 
                     let i_match = eq_ (sym_ (requested.q, Integer), index) in
                     let oargs = 
                       List.map2 (fun (oarg_name, C oargs) (oarg_name', oa') ->
                           assert (Sym.equal oarg_name oarg_name');
                           (oarg_name, C (oargs @ [One {one_index = index; value = oa'}]))
                         ) oargs (oargs_list p'_oargs)
                     in
                     let needed' = and_ [needed; not_ (i_match)] in
                     Deleted, 
                     (simp needed', oargs)
                  | `False -> continue
                  end
               | (Q p', p'_oargs) when equal_predicate_name (Owned requested_ct) p'.name ->
                  let p' = alpha_rename_qpredicate_type requested.q p' in
                  let pmatch = eq_ (requested.pointer, p'.pointer) in
                  (* todo: check for p' non-emptiness? *)
                  begin match provable (LC.T pmatch) with
                  | `True ->
                     let took = and_ [requested.permission; p'.permission] in
                     let oargs = 
                       List.map2 (fun (oarg_name, C oargs) (oarg_name', oa') ->
                           (oarg_name, C (oargs @ [Many {many_guard = took; value = oa'}]))
                         ) oargs (oargs_list p'_oargs)
                     in
                     let needed' = and_ [needed; not_ p'.permission] in
                     let permission' = and_ [p'.permission; not_ needed] in
                     Changed (Q {p' with permission = permission'}, p'_oargs), 
                     (simp needed', oargs)
                  | `False -> continue
                  end
               | re ->
                  continue
         in
         let@ (needed, oargs) =
           map_and_fold_resources loc (sub_resource_if is_exact_re)
             (needed, List.map_snd (fun _ -> C []) (q_owned_oargs_list requested_ct))
         in
         debug 10 (lazy (item "needed after exact matches:" (IT.pp needed)));
         let k_is = scan_key_indices requested.q needed in
         let k_ptrs = List.map (fun i -> (i, arrayShift_ (requested.pointer, requested_ct, i))) k_is in
         let k_ptrs = List.map (fun (i, p) -> (simp i, simp p)) k_ptrs in
         if List.length k_ptrs == 0 then ()
         else debug 10 (lazy (item "key ptrs for additional matches:"
             (Pp.list IT.pp (List.map snd k_ptrs))));
         let@ k_ptr_match = exact_match_point_ptrs (List.map snd k_ptrs) in
         let is_exact_k (re : RET.t) = !reorder_points && k_ptr_match re in
         let necessary_k_ptrs = List.filter (fun (i, p) ->
             let i_match = eq_ (sym_ (requested.q, Integer), i) in
             match provable (forall_ (requested.q, BT.Integer) (impl_ (i_match, needed)))
             with `True -> true | _ -> false) k_ptrs in
         let@ () = 
           ListM.iterM (fun (_, p) ->
               let@ r = 
                 predicate_request ~recursive:true loc uiinfo {
                     name = Owned requested_ct;
                     pointer = p;
                     iargs = [];
                     permission = bool_ true;
                   }
               in
               match r with
               | Some (res, res_oargs) -> add_r None (P res, res_oargs)
               | None -> return ()
             ) necessary_k_ptrs 
         in
         let@ (needed, oargs) =
           map_and_fold_resources loc (sub_resource_if is_exact_k)
             (needed, oargs) 
         in
         if List.length k_ptrs == 0 then ()
         else debug 10 (lazy (item "needed after additional matches:" (IT.pp needed)));
         let needed = if !additional_sat_check
           then begin
           match provable (forall_ (requested.q, BT.Integer) (not_ needed)) with
             | `True -> (debug 10 (lazy (format [] "proved needed == false.")); bool_ false)
             | _ -> (debug 10 (lazy (format [] "checked, needed is satisfiable.")); needed)
           end
           else needed in
         let@ (needed, oargs) =
           map_and_fold_resources loc (sub_resource_if
             (fun re -> not (is_exact_re re) && not (is_exact_k re)))
             (needed, oargs) 
         in
         let holds = provable (forall_ (requested.q, BT.Integer) (not_ needed)) in
         time_log_end start_timing;
         begin match holds with
         | `True -> return (Some oargs)
         | `False -> return None
         end
      | pname ->
         debug 7 (lazy (item "qpredicate request" (RET.pp (Q requested))));
         let@ def_oargs = match pname with
           | Block _ -> return block_oargs_list 
           | Owned _ -> assert false
           | PName pname ->
              let@ def = Typing.get_resource_predicate_def loc pname in
              return def.oargs
         in
         let@ provable = provable loc in
         let@ global = get_global () in
         let@ values, equalities, lcs = simp_constraints () in
         let simp it = Simplify.simp global.struct_decls values equalities lcs it in
         let needed = requested.permission in
         let@ (needed, oargs) =
           map_and_fold_resources loc (fun re (needed, oargs) ->
               let continue = (Unchanged, (needed, oargs)) in
               if is_false needed then continue else
               match re with
               | (P p', p'_oargs) when equal_predicate_name requested.name p'.name ->
                  let base = requested.pointer in
                  let item_size = int_ requested.step in
                  let offset = array_offset_of_pointer ~base ~pointer:p'.pointer in
                  let index = array_pointer_to_index ~base ~item_size ~pointer:p'.pointer in
                  let subst = IT.make_subst [(requested.q, index)] in
                  let pre_match = 
                    and_ (lePointer_ (base, p'.pointer)
                          :: divisible_ (offset, item_size)
                          :: List.map2 (fun ia ia' -> eq_ (IT.subst subst ia, ia')) requested.iargs p'.iargs
                      )
                  in
                  let took = and_ [pre_match; IT.subst subst needed; p'.permission] in
                  begin match provable (LC.T took) with
                  | `True ->
                     let i_match = eq_ (sym_ (requested.q, Integer), index) in
                     let oargs = 
                       List.map2 (fun (name, C oa) (name', oa') -> 
                           assert (Sym.equal name name');
                           (name, C (oa @ [One {one_index = index; value = oa'}]))
                         ) oargs (oargs_list p'_oargs)
                     in
                     let needed' = and_ [needed; not_ i_match] in
                     Deleted, 
                     (simp needed', oargs)
                  | `False -> continue
                  end
               | (Q p', p'_oargs) when equal_predicate_name requested.name p'.name 
                           && requested.step = p'.step ->
                  let p' = alpha_rename_qpredicate_type requested.q p' in
                  let pmatch = eq_ (requested.pointer, p'.pointer) in
                  begin match provable (LC.T pmatch) with
                  | `True ->
                     let iarg_match = and_ (List.map2 eq__ requested.iargs p'.iargs) in
                     let took = and_ [iarg_match; requested.permission; p'.permission] in
                     let needed' = and_ [needed; not_ (and_ [iarg_match; p'.permission])] in
                     let permission' = and_ [p'.permission; not_ (and_ [iarg_match; needed])] in
                     let oargs = 
                       List.map2 (fun (name, C oa) (name', oa') -> 
                           assert (Sym.equal name name');
                           (name, C (oa @ [Many {many_guard = took; value = oa'}]))
                         ) oargs (oargs_list p'_oargs)
                     in
                     Changed (Q {p' with permission = permission'}, p'_oargs), 
                     (simp needed', oargs)
                  | `False -> continue
                  end
               | re ->
                  continue
             ) (needed, List.map_snd (fun _ -> C []) def_oargs)
         in
         let holds = provable (forall_ (requested.q, BT.Integer) (not_ needed)) in
         begin match holds with
         | `True -> return (Some oargs)
         | `False -> return None
         end

    and qpredicate_request loc uiinfo (requested : RET.qpredicate_type) = 
      let@ o_oargs = qpredicate_request_aux loc uiinfo requested in
      let@ oarg_item_bts = match requested.name with
        | Block _ -> return block_oargs_list
        | Owned ct -> return (owned_oargs_list ct)
        | PName pn ->
           let@ def = Typing.get_resource_predicate_def loc pn in
           return def.oargs
      in
      match o_oargs with
      | None -> return None
      | Some oargs ->
         let@ oas = 
           ListM.map2M (fun (name, C oa) (name', oa_bt) ->
               assert (Sym.equal name name');
               let@ map = cases_to_map loc uiinfo Integer oa_bt (C oa) in
               return (name, map)
             ) oargs oarg_item_bts
         in
         let r = { 
             name = requested.name;
             pointer = requested.pointer;
             q = requested.q;
             step = requested.step;
             permission = requested.permission;
             iargs = requested.iargs; 
           } 
         in
         return (Some (r, O (record_ oas)))


    and fold_array loc uiinfo item_ct base length permission =
      debug 7 (lazy (item "fold array" Pp.empty));
      debug 7 (lazy (item "item_ct" (Sctypes.pp item_ct)));
      debug 7 (lazy (item "base" (IT.pp base)));
      debug 7 (lazy (item "length" (IT.pp (int_ length))));
      debug 7 (lazy (item "permission" (IT.pp permission)));
      let q_s, q = IT.fresh Integer in
      let@ o_values = 
        qpredicate_request_aux loc uiinfo {
            name = Owned item_ct;
            pointer = base;
            q = q_s;
            step = Memory.size_of_ctype item_ct;
            iargs = [];
            permission = and_ [permission; (int_ 0) %<= q; q %<= (int_ (length - 1))];
          }
      in
      match o_values with 
      | None -> return None
      | Some oargs ->
         let oarg_bts = owned_oargs_list item_ct in
         let@ oargs = 
           ListM.map2M (fun (name, oa) (name', oa_bt) ->
               assert (Sym.equal name name');
               cases_to_map loc uiinfo Integer oa_bt oa
             ) oargs oarg_bts
         in
         let folded_value = List.hd oargs in
         let value_s, value = IT.fresh (IT.bt folded_value) in
         let@ () = add_ls [(value_s, IT.bt value)] in
         let@ () = add_c (t_ (def_ value_s folded_value)) in
         let@ provable = provable loc in
         let folded_oargs = 
           record_ [(Resources.value_sym, value)]
         in
         let folded_resource = ({
             name = Owned (Array (item_ct, Some length));
             pointer = base;
             iargs = [];
             permission = permission;
           }, 
           O folded_oargs)
         in
         return (Some folded_resource)


    and fold_struct ~recursive loc uiinfo tag pointer_t permission_t =
      debug 7 (lazy (item "fold struct" Pp.empty));
      debug 7 (lazy (item "tag" (Sym.pp tag)));
      debug 7 (lazy (item "pointer" (IT.pp pointer_t)));
      debug 7 (lazy (item "permission" (IT.pp permission_t)));
      let open Memory in
      let@ global = get_global () in
      let@ layout = get_struct_decl loc tag in
      let@ values_err =
        ListM.fold_leftM (fun o_values {offset; size; member_or_padding} ->
            match o_values with
            | Result.Error e -> return (Result.Error e)
            | Result.Ok values ->
               match member_or_padding with
               | Some (member, sct) ->
                  let request : RET.predicate_type = {
                      name = Owned sct;
                      pointer = memberShift_ (pointer_t, tag, member);
                      iargs = [];
                      permission = permission_t;
                    }
                  in
                  let@ point = predicate_request ~recursive loc uiinfo request in
                  begin match point with
                  | None -> 
                     return (Result.Error (RET.P request))
                  | Some (point, point_oargs) -> 
                     let value = snd (List.hd (oargs_list point_oargs)) in
                     return (Result.Ok (values @ [(member, value)]))
                  end
               | None ->
                  let request : RET.predicate_type = {
                      name = Block (Array (Integer Char, Some size));
                      pointer = integerToPointerCast_ (add_ (pointerToIntegerCast_ pointer_t, int_ offset));
                      permission = permission_t;
                      iargs = [];
                    } 
                  in
                  let@ result = predicate_request ~recursive loc uiinfo request in
                  begin match result with
                  | None -> return (Result.Error (RET.P request))
                  | Some _ -> return (Result.Ok values)
                  end
       ) (Result.Ok []) layout
      in
      match values_err with
      | Result.Error e -> return (Result.Error e)
      | Result.Ok values ->
         let value_s, value = IT.fresh (Struct tag) in
         let@ () = add_ls [(value_s, IT.bt value)] in
         let@ () = add_c (t_ (def_ value_s (IT.struct_ (tag, values)))) in
         let folded_oargs = record_ [(Resources.value_sym, value)] in
         let folded_resource = ({
             name = Owned (Struct tag);
             pointer = pointer_t;
             iargs = [];
             permission = permission_t;
           }, 
           O folded_oargs)
         in
         return (Result.Ok folded_resource)


    (* HEREHEREHERE *)


    and unfolded_array item_ct base length permission value =
      (let q_s, q = IT.fresh_named Integer "i" in
       let unfolded_oargs = record_ [(Resources.value_sym, value)] in
       {
         name = Owned item_ct;
         pointer = base;
         step = Memory.size_of_ctype item_ct;
         q = q_s;
         iargs = [];
         permission = and_ [permission; (int_ 0) %<= q; q %<= (int_ (length - 1))]
      },
       O unfolded_oargs)

    and unfold_array ~recursive loc uiinfo item_ct length base permission =
      debug 7 (lazy (item "unfold array" Pp.empty));
      debug 7 (lazy (item "item_ct" (Sctypes.pp item_ct)));
      debug 7 (lazy (item "base" (IT.pp base)));
      debug 7 (lazy (item "permission" (IT.pp permission)));
      let@ result = 
        predicate_request ~recursive loc uiinfo ({
              name = Owned (Array (item_ct, Some length));
              pointer = base;
              iargs = [];
              permission = permission;
          }
        ) 
      in
      match result with
      | None -> return None
      | Some (point, point_oargs) ->
         let length = match point.name with
           | Owned (Array (_, Some length)) -> length
           | _ -> assert false
         in
         let qpoint =
           unfolded_array item_ct base length permission 
             (snd (List.hd (oargs_list point_oargs))) 
         in
         return (Some qpoint)


    and unfolded_struct layout tag pointer_t permission_t value =
      let open Memory in
      List.map (fun {offset; size; member_or_padding} ->
          match member_or_padding with
          | Some (member, sct) ->
             let oargs = 
               record_
                 [(Resources.value_sym, member_ ~member_bt:(BT.of_sct sct) (tag, value, member))]
             in
             let resource = 
               (P {
                   name = Owned sct;
                   pointer = memberShift_ (pointer_t, tag, member);
                   permission = permission_t;
                   iargs = [];
                  },
                O oargs)
             in
             resource
          | None ->
             (P {
                 name = Block (Array (Integer Char, Some size));
                 pointer = integerToPointerCast_ (add_ (pointerToIntegerCast_ pointer_t, int_ offset));
                 permission = permission_t;
                 iargs = [];
               },
             O (record_ []))
        ) layout


    and unfold_struct ~recursive loc uiinfo tag pointer_t permission_t =
      debug 7 (lazy (item "unfold struct" Pp.empty));
      debug 7 (lazy (item "tag" (Sym.pp tag)));
      debug 7 (lazy (item "pointer" (IT.pp pointer_t)));
      debug 7 (lazy (item "permission" (IT.pp permission_t)));
      let@ global = get_global () in
      let@ result = 
        predicate_request ~recursive loc uiinfo
          (unfold_struct_request tag pointer_t permission_t)
      in
      match result with
      | None -> return None
      | Some (point, point_oargs) -> 
         let layout = SymMap.find tag global.struct_decls in
         let resources = 
           unfolded_struct layout tag pointer_t permission_t
             (snd (List.hd (oargs_list point_oargs))) 
         in
         return (Some resources)


    and span_fold_unfolds loc uiinfo req is_tail_rec =
      if not (! span_actions)
      then return ()
      else
      let start_timing = if is_tail_rec then 0.0
          else time_log_start "span_check" "" in
      let@ ress = all_resources () in
      let@ global = get_global () in
      let@ provable = provable loc in
      let@ m = model_with loc (bool_ true) in
      let@ _ = match m with
        | None -> return ()
        | Some (model, _) ->
          let opts = Spans.guess_span_intersection_action ress req model global in
          let confirmed = List.find_opt (fun (act, confirm) ->
              match provable (t_ confirm) with
                  | `False -> false
                  | `True -> true
          ) opts in
          begin match confirmed with
          | None -> return ()
          | Some (Spans.Pack (pt, ct), _) ->
              let@ success = do_pack loc uiinfo pt ct in
              if success then span_fold_unfolds loc uiinfo req true else return ()
          | Some (Spans.Unpack (pt, ct), _) ->
              let@ success = do_unpack loc uiinfo pt ct in
              if success then span_fold_unfolds loc uiinfo req true else return ()
          end
      in
      if is_tail_rec then () else time_log_end start_timing;
      return ()

    and do_pack loc uiinfo pt ct =
      let@ opt = match ct with
        | Sctypes.Array (act, Some length) ->
          fold_array loc uiinfo act pt length (bool_ true)
        | Sctypes.Struct tag ->
          let@ result = fold_struct ~recursive:true loc uiinfo tag pt (bool_ true) in
          begin match result with
            | Result.Ok res -> return (Some res)
            | _ -> return None
          end
        | _ -> return None
      in
      match opt with
      | None -> return false
      | Some (resource, oargs) ->
         let@ _ = add_r None (P resource, oargs) in
         return true

    and do_unpack loc uiinfo pt ct =
      match ct with
        | Sctypes.Array (act, Some length) ->
          let@ oqp = unfold_array ~recursive:true loc uiinfo act
                       length pt (bool_ true) in
          begin match oqp with
            | None -> return false
            | Some (qp, oargs) ->
                let@ _ = add_r None (Q qp, oargs) in
                return true
          end
        | Sctypes.Struct tag ->
          let@ ors = unfold_struct ~recursive:true loc uiinfo tag pt (bool_ true) in
          begin match ors with
            | None -> return false
            | Some rs ->
               let@ _ = add_rs None rs in
               return true
          end
        | _ -> return false




    let resource_request ~recursive loc uiinfo (request : RET.t) : (RE.t option, type_error) m = 
      match request with
      | P request ->
         let@ result = predicate_request ~recursive loc uiinfo request in
         return (Option.map_fst (fun p -> P p) result)
      | Q request ->
         let@ result = qpredicate_request loc uiinfo request in
         return (Option.map_fst (fun q -> Q q) result)

  end

  module Special = struct

    let fail_missing_resource loc situation (orequest, oinfo) = 
      let@ model = model () in
      fail (fun ctxt ->
          let msg = Missing_resource_request {orequest; situation; oinfo; model; ctxt} in
          {loc; msg})


    let predicate_request ~recursive loc situation (request, oinfo) = 
      let uiinfo = (situation, (Some (P request), oinfo)) in
      let@ result = General.predicate_request ~recursive loc uiinfo request in
      match result with
      | Some r -> return r
      | None -> fail_missing_resource loc situation (Some (P request), oinfo)

    let qpredicate_request loc situation (request, oinfo) = 
      let uiinfo = (situation, (Some (Q request), oinfo)) in
      let@ result = General.qpredicate_request loc uiinfo request in
      match result with
      | Some r -> return r
      | None -> fail_missing_resource loc situation (Some (Q request), oinfo)

    let unfold_struct ~recursive loc situation tag pointer_t permission_t = 
      let request = General.unfold_struct_request tag pointer_t permission_t in
      let uiinfo = (situation, (Some (P request), None)) in
      let@ result = General.unfold_struct ~recursive loc uiinfo tag pointer_t permission_t in
      match result with
      | Some resources -> return resources
      | None -> 
         fail_missing_resource loc situation (Some (P request), None)
      

    let fold_struct ~recursive loc situation tag pointer_t permission_t = 
      let uiinfo = (situation, (None, None)) in
      let@ result = General.fold_struct ~recursive loc uiinfo tag pointer_t permission_t in
      match result with
      | Result.Ok r -> return r
      | Result.Error request -> fail_missing_resource loc situation (Some request, None)

  end


end






module InferenceEqs = struct

let use_model_eqs = ref true

(* todo: what is this? Can we replace this by using the predicate_name
   + information about whether iterated or not? *)
let res_pointer_kind (res, _) = match res with
  | (RET.P ({name = Owned ct; _} as res_pt)) -> Some ((("", "Pt"), ct), res_pt.pointer)
  | (RET.Q ({name = Owned ct; _} as res_qpt)) -> Some ((("", "QPt"), ct), res_qpt.pointer)
  | (RET.P ({name = PName pn; _} as res_pd)) -> Some (((Sym.pp_string pn, "Pd"), Sctypes.Void), res_pd.pointer)
  | _ -> None

let div_groups cmp xs =
  let rec gather x xs gps ys = match ys with
    | [] -> (x :: xs) :: gps
    | (z :: zs) -> if cmp x z == 0 then gather z (x :: xs) gps zs
    else gather z [] ((x :: xs) :: gps) zs
  in
  match List.sort cmp xs with
    | [] -> []
    | (y :: ys) -> gather y [] [] ys

let div_groups_discard cmp xs =
  List.map (List.map snd) (div_groups (fun (k, _) (k2, _) -> cmp k k2) xs)

let unknown_eq_in_group simp ptr_gp = List.find_map (fun (p, req) -> if not req then None
  else List.find_map (fun (p2, req) -> if req then None
    else if is_true (simp (eq_ (p, p2))) then None
    else Some (eq_ (p, p2))) ptr_gp) ptr_gp

let upd_ptr_gps_for_model global m ptr_gps =
  let eval_f p = match Solver.eval global m p with
    | Some (IT (Lit (Pointer i), _)) -> i
    | _ -> (print stderr (IT.pp p); assert false)
  in
  let eval_eqs = List.map (List.map (fun (p, req) -> (eval_f p, (p, req)))) ptr_gps in
  let ptr_gps = List.concat (List.map (div_groups_discard Z.compare) eval_eqs) in
  ptr_gps

let add_eqs_for_infer loc ftyp =
  (* TODO: tweak 'fuel'-related things *)
  if not (! use_model_eqs) then return ()
  else
  begin
  let start_eqs = time_log_start "eqs" "" in
  debug 5 (lazy (format [] "pre-inference equality discovery"));
  let reqs = LAT.r_resource_requests ftyp in
  let@ ress = map_and_fold_resources loc (fun re xs -> (Unchanged, re :: xs)) [] in
  let res_ptr_k k r = Option.map (fun (ct, p) -> (ct, (p, k))) (res_pointer_kind r) in
  let ptrs = List.filter_map (fun (_, r) -> res_ptr_k true r) reqs @
    (List.filter_map (res_ptr_k false) ress) in
  let cmp2 = Lem_basic_classes.pairCompare
        (Lem_basic_classes.pairCompare String.compare String.compare) CT.compare in
  let ptr_gps = div_groups_discard cmp2 ptrs in
  let@ ms = prev_models_with loc (bool_ true) in
  let@ global = get_global () in
  let ptr_gps = List.fold_right (upd_ptr_gps_for_model global)
        (List.map fst ms) ptr_gps in
  let@ provable = provable loc in
  let rec loop fuel ptr_gps =
    if fuel <= 0 then begin
      debug 5 (lazy (format [] "equality discovery fuel exhausted"));
      return ()
    end
    else
    let@ values, equalities, lcs = simp_constraints () in
    let simp t = Simplify.simp global.struct_decls values equalities lcs t in
    let poss_eqs = List.filter_map (unknown_eq_in_group simp) ptr_gps in
    debug 7 (lazy (format [] ("investigating " ^
        Int.to_string (List.length poss_eqs) ^ " possible eqs")));
    if List.length poss_eqs == 0
    then return ()
    else match provable (t_ (and_ poss_eqs)) with
      | `True ->
        debug 5 (lazy (item "adding equalities" (IT.pp (and_ poss_eqs))));
        let@ () = add_cs (List.map t_ poss_eqs) in
        loop (fuel - 1) ptr_gps
      | `False ->
        let (m, _) = Solver.model () in
        debug 7 (lazy (format [] ("eqs refuted, processing model")));
        let ptr_gps = upd_ptr_gps_for_model global m ptr_gps in
        loop (fuel - 1) ptr_gps
  in
  let@ () = loop 10 ptr_gps in
  debug 5 (lazy (format [] "finished equality discovery"));
  time_log_end start_eqs;
  return ()
  end

(*
    let exact_match () =
      let@ global = get_global () in
      let@ all_lcs = all_constraints () in
      return begin fun (request, resource) -> match (request, resource) with
      | (RER.Point req_p, RE.Point res_p) ->
        let simp t = Simplify.simp global.struct_decls all_lcs t in
        let pmatch = eq_ (req_p.pointer, res_p.pointer) in
        let more_perm = impl_ (req_p.permission, res_p.permission) in
        (* FIXME: simp of Impl isn't all that clever *)
        (is_true (simp pmatch) && is_true (simp more_perm))
      | _ -> false
      end
*)




end



module RI = ResourceInference






(* got until here *)




(*** function call typing, subtyping, and resource inference *****************)

(* spine is parameterised so it can be used both for function and
   label types (which don't have a return type) *)



type arg = {lname : Sym.t; bt : BT.t; loc : loc}
type args = arg list
let it_of_arg arg = sym_ (arg.lname, arg.bt)


let check_computational_bound loc s = 
  let@ is_bound = bound_a s in
  if is_bound then return () 
  else fail (fun _ -> {loc; msg = Unknown_variable s})


let arg_of_sym (loc : loc) (sym : Sym.t) : (arg, type_error) m = 
  let@ () = check_computational_bound loc sym in
  let@ (bt,lname) = get_a sym in
  return {lname; bt; loc}

let arg_of_asym (asym : 'bty asym) : (arg, type_error) m = 
  arg_of_sym asym.loc asym.sym

let args_of_asyms (asyms : 'bty asyms) : (args, type_error) m = 
  ListM.mapM arg_of_asym asyms


(* info gathered during spine judgements, per path through a
   function/procedure, which are only useful once this has completed
   for all paths *)
type per_path_info_entry =
  SuggestEqsData of SuggestEqs.constraint_analysis
type per_path = per_path_info_entry list


module Spine : sig
  val calltype_ft : 
    Loc.t -> args -> AT.ft -> (RT.t * per_path, type_error) m
  val calltype_lft : 
    Loc.t -> LAT.lft -> (LRT.t * per_path, type_error) m
  val calltype_lt : 
    Loc.t -> args -> AT.lt * label_kind -> (per_path, type_error) m
  val calltype_packing : 
    Loc.t -> Sym.t -> LAT.packing_ft -> (OutputDef.t * per_path, type_error) m
  val calltype_lpred_argument_inference : 
    Loc.t -> Sym.t -> args -> AT.arginfer_ft -> (IT.t list * per_path, type_error) m
  val subtype : 
    Loc.t -> arg -> RT.t -> (per_path, type_error) m
end = struct

  let pp_unis (unis : (LS.t * Locations.info) SymMap.t) : Pp.document = 
   Pp.list (fun (sym, (ls, _)) ->
     Sym.pp sym ^^^ !^"unresolved" ^^^ parens (LS.pp ls)
     ) (SymMap.bindings unis)



  let ls_matches_spec loc unis uni_var instantiation = 
    let (expect, info) = SymMap.find uni_var unis in
    if LS.equal (IT.bt instantiation) expect 
    then return ()
    else fail (fun _ -> {loc; msg = Mismatch_lvar { has = IT.bt instantiation; expect; spec_info = info}})


  (* let prefer_req i ftyp = *)
  (*   let open NormalisedArgumentTypes in *)
  (*   let rec grab i ftyp = match ftyp with *)
  (*     | Resource (resource, info, ftyp) -> if i = 0 *)
  (*         then (resource, info) *)
  (*         else grab (i - 1) ftyp *)
  (*     | _ -> assert false *)
  (*   in *)
  (*   let rec del i ftyp = match ftyp with *)
  (*     | Resource (resource, info, ftyp) -> if i = 0 *)
  (*         then ftyp *)
  (*         else Resource (resource, info, del (i - 1) ftyp) *)
  (*     | _ -> assert false *)
  (*   in *)
  (*   let (resource, info) = grab i ftyp in *)
  (*   let ftyp = del i ftyp in *)
  (*   Resource (resource, info, ftyp) *)

  let has_exact loc (r : RET.t) =
    let@ is_ex = RI.General.exact_match () in
    map_and_fold_resources loc (fun re found -> (Unchanged, found || is_ex (RE.request re, r))) false

  (* let prefer_exact loc ftyp =  *)
  (*   if ! RI.reorder_points then return ftyp *)
  (*   else *)
  (*   let reqs1 = NormalisedArgumentTypes.r_resource_requests ftyp in *)
  (*   let unis = SymSet.of_list (List.map fst reqs1) in *)
  (*   (\* capture avoiding *\) *)
  (*   assert (SymSet.cardinal unis = List.length reqs1); *)
  (*   let reqs = List.mapi (fun i res -> (i, res)) reqs1 in *)
  (*   let res_free_vars (r, _) = match r with *)
  (*     | P ({name = Owned _; _} as p) -> IT.free_vars p.pointer *)
  (*     | Q ({name = Owned _; _} as p) -> IT.free_vars p.pointer *)
  (*     | _ -> SymSet.empty *)
  (*   in *)
  (*   let no_unis r = SymSet.for_all (fun x -> not (SymSet.mem x unis)) (res_free_vars r) in *)
  (*   let reqs = List.filter (fun (_, (_, r)) -> no_unis r) reqs in *)
  (*   let@ reqs = ListM.filterM (fun (_, (_, r)) -> has_exact loc r) reqs in *)
  (*   (\* just need an actual preference function *\) *)
  (*   match List.rev reqs with *)
  (*     | ((i, _) :: _) -> return (prefer_req i ftyp) *)
  (*     | [] -> return ftyp *)



  let spine_l rt_subst rt_pp loc situation ftyp = 

    let start_spine = time_log_start "spine_l" "" in

    (* record the resources now, so we can later re-construct the
       memory state "before" running spine *)
    let@ original_resources = all_resources () in

    let@ () = 
      let@ trace_length = get_trace_length () in
      time_f_logs loc 9 "pre_inf_eqs" trace_length
        (InferenceEqs.add_eqs_for_infer loc) ftyp
    in

    let@ rt, cs = 
      let@ provable = provable loc in
      let rec check cs ftyp = 
        let@ () = print_with_ctxt (fun ctxt ->
            debug 6 (lazy (item "ctxt" (Context.pp ctxt)));
            debug 6 (lazy (item "spec" (LAT.pp rt_pp ftyp)));
          )
        in
        (* let@ ftyp = prefer_exact loc ftyp in *)
        match ftyp with
        | LAT.Resource ((s, (resource, bt)), info, ftyp) -> 
           let uiinfo = (situation, (Some resource, Some info)) in
           let@ o_re_oarg = RI.General.resource_request ~recursive:true loc uiinfo resource in
           let@ oargs = match o_re_oarg with
             | None ->
                let@ model = model () in
                fail (fun ctxt ->
                    let ctxt = { ctxt with resources = original_resources } in
                    let msg = Missing_resource_request 
                                {orequest = Some resource; 
                                 situation; oinfo = Some info; model; ctxt} in
                    {loc; msg}
                  )

             | Some (re, O oargs) ->
                assert (ResourceTypes.equal re resource);
                return oargs
           in
           check cs (LAT.subst rt_subst (IT.make_subst [(s, oargs)]) ftyp)
        | Define ((s, it), info, ftyp) ->
           let s' = Sym.fresh () in
           let bt = IT.bt it in
           let@ () = add_l s' bt in
           let@ () = add_c (LC.t_ (def_ s' it)) in
           check cs (LAT.subst rt_subst (IT.make_subst [(s, sym_ (s', bt))]) ftyp)
        | Constraint (c, info, ftyp) -> 
           let@ () = return (debug 9 (lazy (item "checking constraint" (LC.pp c)))) in
           let res = provable c in
           begin match res with
           | `True -> check (c :: cs) ftyp
           | `False ->
              let@ model = model () in
              fail (fun ctxt ->
                  let ctxt = { ctxt with resources = original_resources } in
                  {loc; msg = Unsat_constraint {constr = c; info; ctxt; model}}
                )
           end
        | I rt ->
           return (rt, cs)
      in
      check [] ftyp
    in

    let@ constraints = all_constraints () in
    let per_path = SuggestEqs.eqs_from_constraints (LCSet.elements constraints) cs
      |> Option.map (fun x -> SuggestEqsData x) |> Option.to_list in

    let@ () = return (debug 9 (lazy !^"done")) in
    time_log_end start_spine;
    return (rt, per_path)


  let spine rt_subst rt_pp loc situation args ftyp =

    let open ArgumentTypes in

    let original_ftyp = ftyp in
    let original_args = args in

    let@ () = print_with_ctxt (fun ctxt ->
        debug 6 (lazy (checking_situation situation));
        debug 6 (lazy (item "ctxt" (Context.pp ctxt)));
        debug 6 (lazy (item "spec" (pp rt_pp ftyp)))
      )
    in

    let@ ftyp = 
      let rec check args ftyp = 
        match args, ftyp with
        | (arg :: args), (Computational ((s, bt), _info, ftyp)) ->
           if BT.equal arg.bt bt then
             check args (subst rt_subst (make_subst [(s, sym_ (arg.lname, bt))]) ftyp)
           else
             fail (fun _ -> {loc = arg.loc; msg = Mismatch {has = arg.bt; expect = bt}})
        | [], (L ftyp) -> 
           return ftyp
        | _ -> 
           let expect = count_computational original_ftyp in
           let has = List.length original_args in
           fail (fun _ -> {loc; msg = Number_arguments {expect; has}})
      in
      check args ftyp 
    in
    
    spine_l rt_subst rt_pp loc situation ftyp


  let calltype_ft loc args (ftyp : AT.ft) : (RT.t * per_path, type_error) m =
    spine RT.subst RT.pp loc FunctionCall args ftyp

  let calltype_lft loc (ftyp : LAT.lft) : (LRT.t * per_path, type_error) m =
    spine_l LRT.subst LRT.pp loc FunctionCall ftyp

  let calltype_lt loc args ((ltyp : AT.lt), label_kind) : (per_path, type_error) m =
    let@ (False.False, per_path) =
      spine False.subst False.pp 
        loc (LabelCall label_kind) args ltyp
    in
    return per_path

  let calltype_packing loc (name : Sym.t) (ft : LAT.packing_ft)
        : (OutputDef.t * per_path, type_error) m =
    spine_l OutputDef.subst OutputDef.pp 
      loc (PackPredicate name) ft

  let calltype_lpred_argument_inference loc (name : Sym.t) 
        supplied_args (ft : AT.arginfer_ft) : (IT.t list * per_path, type_error) m =
    let@ (output_assignment, per_path) =
      spine OutputDef.subst OutputDef.pp 
        loc (ArgumentInference name) supplied_args ft
    in
    return (List.map (fun o -> o.OutputDef.value) output_assignment, per_path)


  (* The "subtyping" judgment needs the same resource/lvar/constraint
     inference as the spine judgment. So implement the subtyping
     judgment 'arg <: RT' by type checking 'f(arg)' for 'f: RT -> False'. *)
  let subtype (loc : loc) arg (rtyp : RT.t) : (per_path, type_error) m =
    let ft = AT.of_rt rtyp (LAT.I False.False) in
    let@ (False.False, per_path) =
      spine False.subst False.pp loc Subtyping [arg] ft in
    return per_path


end


(*** pure value inference *****************************************************)

type vt = BT.t * IT.t
let vt_of_arg arg = (arg.bt, it_of_arg arg)

let rt_of_vt loc (bt,it) = 
  let s = Sym.fresh () in 
  RT.Computational ((s, bt), (loc, None),
  LRT.Constraint (t_ (def_ s it), (loc, None),
  LRT.I))


let infer_tuple (loc : loc) (vts : vt list) : (vt, type_error) m = 
  let bts, its = List.split vts in
  return (Tuple bts, IT.tuple_ its)

let infer_array (loc : loc) (vts : vt list) = 
  let item_bt = match vts with
    | [] -> Debug_ocaml.error "todo: empty arrays"
    | (item_bt, _) :: _ -> item_bt
  in
  let@ (_, it) = 
    ListM.fold_leftM (fun (index,it) (arg_bt, arg_it) -> 
        let@ () = WellTyped.ensure_base_type loc ~expect:item_bt arg_bt in
        return (index + 1, map_set_ it (int_ index, arg_it))
         ) (0, const_map_ Integer (default_ item_bt)) vts
  in
  return (BT.Map (Integer, item_bt), it)


let infer_constructor (loc : loc) (constructor : mu_ctor) 
                      (args : arg list) : (vt, type_error) m = 
  match constructor, args with
  | M_Ctuple, _ -> 
     infer_tuple loc (List.map vt_of_arg args)
  | M_Carray, args -> 
     infer_array loc (List.map vt_of_arg args)
  | M_Cspecified, [arg] ->
     return (vt_of_arg arg)
  | M_Cspecified, _ ->
     fail (fun _ -> {loc; msg = Number_arguments {has = List.length args; expect = 1}})
  | M_Cnil item_bt, [] -> 
     let@ () = WellTyped.WBT.is_bt loc item_bt in
     let bt = List item_bt in
     return (bt, nil_ ~item_bt)
  | M_Cnil item_bt, _ -> 
     let@ () = WellTyped.WBT.is_bt loc item_bt in
     fail (fun _ -> {loc; msg = Number_arguments {has = List.length args; expect=0}})
  | M_Ccons, [arg1; arg2] -> 
     let bt = List arg1.bt in
     let@ () = WellTyped.ensure_base_type arg2.loc ~expect:bt arg2.bt in
     let list_it = cons_ (it_of_arg arg1, it_of_arg arg2) in
     return (arg2.bt, list_it)
  | M_Ccons, _ ->
     fail (fun _ -> {loc; msg = Number_arguments {has = List.length args; expect = 2}})





let infer_ptrval (loc : loc) (ptrval : pointer_value) : (vt, type_error) m =
  CF.Impl_mem.case_ptrval ptrval
    ( fun ct -> 
      let sct = Retype.ct_of_ct loc ct in
      let@ () = WellTyped.WCT.is_ct loc sct in
      return (Loc, IT.null_) )
    ( fun sym -> 
      let@ _ = get_fun_decl loc sym in
      return (Loc, sym_ (sym, BT.Loc)) 
    )
    ( fun _prov loc -> 
      return (Loc, pointer_ loc) )
    ( fun () -> 
      Debug_ocaml.error "unspecified pointer value" )

let rec infer_mem_value (loc : loc) (mem : mem_value) : (vt, type_error) m =
  let open BT in
  CF.Impl_mem.case_mem_value mem
    ( fun ct -> 
      let@ () = WellTyped.WCT.is_ct loc (Retype.ct_of_ct loc ct) in
      fail (fun _ -> {loc; msg = Unspecified ct}) )
    ( fun _ _ -> 
      unsupported loc !^"infer_mem_value: concurrent read case" )
    ( fun ity iv -> 
      (* TODO: do anything with ity? *)
      return (Integer, int_ (Memory.int_of_ival iv)) )
    ( fun ft fv -> 
      unsupported loc !^"floats" )
    ( fun ct ptrval -> 
      (* TODO: do anything else with ct? *)
      let@ () = WellTyped.WCT.is_ct loc (Retype.ct_of_ct loc ct) in
      infer_ptrval loc ptrval  )
    ( fun mem_values -> 
      let@ vts = ListM.mapM (infer_mem_value loc) mem_values in
      infer_array loc vts )
    ( fun tag mvals -> 
      let mvals = List.map (fun (member, _, mv) -> (member, mv)) mvals in
      infer_struct loc tag mvals )
    ( fun tag id mv -> 
      infer_union loc tag id mv )

and infer_struct (loc : loc) (tag : tag) 
                 (member_values : (member * mem_value) list) : (vt, type_error) m =
  (* might have to make sure the fields are ordered in the same way as
     in the struct declaration *)
  let@ layout = get_struct_decl loc tag in
  let rec check fields spec =
    match fields, spec with
    | ((member, mv) :: fields), ((smember, sct) :: spec) 
         when Id.equal member smember ->
       let@ (member_bt, member_it) = infer_mem_value loc mv in
       let@ () = WellTyped.ensure_base_type loc ~expect:(BT.of_sct sct) member_bt in
       let@ member_its = check fields spec in
       return ((member, member_it) :: member_its)
    | [], [] -> 
       return []
    | ((id, mv) :: fields), ((smember, sbt) :: spec) ->
       Debug_ocaml.error "mismatch in fields in infer_struct"
    | [], ((member, _) :: _) ->
       fail (fun _ -> {loc; msg = Generic (!^"field" ^/^ Id.pp member ^^^ !^"missing")})
    | ((member,_) :: _), [] ->
       fail (fun _ -> {loc; msg = Generic (!^"supplying unexpected field" ^^^ Id.pp member)})
  in
  let@ it = check member_values (Memory.member_types layout) in
  return (BT.Struct tag, IT.struct_ (tag, it))

and infer_union (loc : loc) (tag : tag) (id : Id.t) 
                (mv : mem_value) : (vt, type_error) m =
  Debug_ocaml.error "todo: union types"

let rec infer_object_value (loc : loc)
                       (ov : 'bty mu_object_value) : (vt, type_error) m =
  match ov with
  | M_OVinteger iv ->
     let i = Memory.z_of_ival iv in
     return (Integer, z_ i)
  | M_OVpointer p -> 
     infer_ptrval loc p
  | M_OVarray items ->
     let@ vts = ListM.mapM (infer_loaded_value loc) items in
     infer_array loc vts
  | M_OVstruct (tag, fields) -> 
     let mvals = List.map (fun (member,_,mv) -> (member, mv)) fields in
     infer_struct loc tag mvals       
  | M_OVunion (tag, id, mv) -> 
     infer_union loc tag id mv
  | M_OVfloating iv ->
     unsupported loc !^"floats"

and infer_loaded_value loc (M_LVspecified ov) =
  infer_object_value loc ov

let rec infer_value (loc : loc) (v : 'bty mu_value) : (vt, type_error) m = 
  match v with
  | M_Vobject ov ->
     infer_object_value loc ov
  | M_Vloaded lv ->
     infer_loaded_value loc lv
  | M_Vunit ->
     return (Unit, IT.unit_)
  | M_Vtrue ->
     return (Bool, IT.bool_ true)
  | M_Vfalse -> 
     return (Bool, IT.bool_ false)
  | M_Vlist (bt, vals) ->
     let@ () = WellTyped.WBT.is_bt loc bt in
     let@ its = 
       ListM.mapM (fun v -> 
           let@ (i_bt, i_it) = infer_value loc v in
           let@ () = WellTyped.ensure_base_type loc ~expect:bt i_bt in
           return i_it
         ) vals
     in
     return (BT.List bt, list_ ~item_bt:bt its)
  | M_Vtuple vals ->
     let@ vts = ListM.mapM (infer_value loc) vals in
     let bts, its = List.split vts in
     return (Tuple bts, tuple_ its)






(*** pure expression inference ************************************************)


let infer_array_shift loc asym1 loc_ct ct asym2 =
  let@ () = WellTyped.WCT.is_ct loc_ct ct in
  let@ arg1 = arg_of_asym asym1 in
  let@ arg2 = arg_of_asym asym2 in
  let@ () = WellTyped.ensure_base_type arg1.loc ~expect:Loc arg1.bt in
  let@ () = WellTyped.ensure_base_type arg2.loc ~expect:Integer arg2.bt in
  let v = arrayShift_ (it_of_arg arg1, ct, it_of_arg arg2) in
  return (rt_of_vt loc (BT.Loc, v))


let wrapI ity arg =
  (* try to follow wrapI from runtime/libcore/std.core *)
  let maxInt = Memory.max_integer_type ity in
  let minInt = Memory.min_integer_type ity in
  let dlt = Z.add (Z.sub maxInt minInt) (Z.of_int 1) in
  let r = rem_f_ (arg, z_ dlt) in
  ite_ (le_ (r, z_ maxInt), r, sub_ (r, z_ dlt))



(* could potentially return a vt instead of an RT.t *)
let infer_pexpr (pe : 'bty mu_pexpr) : (RT.t * per_path, type_error) m =
  let (M_Pexpr (loc, _annots, _bty, pe_)) = pe in
  let@ () = print_with_ctxt (fun ctxt ->
      debug 3 (lazy (action "inferring pure expression"));
      debug 3 (lazy (item "expr" (pp_pexpr pe)));
      debug 3 (lazy (item "ctxt" (Context.pp ctxt)))
    )
  in
  let@ (rt, per_path) = match pe_ with
    | M_PEsym sym ->
       let@ arg = arg_of_sym loc sym in
       return (rt_of_vt loc (vt_of_arg arg), [])
    | M_PEimpl i ->
       let@ global = get_global () in
       let rt = Global.get_impl_constant global i in
       return (rt, [])
    | M_PEval v ->
       let@ vt = infer_value loc v in
       return (rt_of_vt loc vt, [])
    | M_PEconstrained _ ->
       Debug_ocaml.error "todo: PEconstrained"
    | M_PEctor (ctor, asyms) ->
       let@ args = args_of_asyms asyms in
       let@ vt = infer_constructor loc ctor args in
       return (rt_of_vt loc vt, [])
    | M_CivCOMPL _ ->
       Debug_ocaml.error "todo: CivCOMPL"
    | M_CivAND _ ->
       Debug_ocaml.error "todo: CivAND"
    | M_CivOR _ ->
       Debug_ocaml.error "todo: CivOR"
    | M_CivXOR (act, asym1, asym2) -> 
       let ity = match act.ct with
         | Integer ity -> ity
         | _ -> Debug_ocaml.error "M_CivXOR with non-integer c-type"
       in
       let@ arg1 = arg_of_asym asym1 in
       let@ arg2 = arg_of_asym asym2 in
       let@ () = WellTyped.ensure_base_type arg1.loc ~expect:Integer arg1.bt in
       let@ () = WellTyped.ensure_base_type arg2.loc ~expect:Integer arg2.bt in
       let vt = (Integer, xor_ ity (it_of_arg arg1, it_of_arg arg2)) in
       return (rt_of_vt loc vt, [])
    | M_Cfvfromint _ -> 
       unsupported loc !^"floats"
    | M_Civfromfloat (act, _) -> 
       let@ () = WellTyped.WCT.is_ct act.loc act.ct in
       unsupported loc !^"floats"
    | M_PEarray_shift (asym1, ct, asym2) ->
       let@ rt = infer_array_shift loc asym1 loc ct asym2 in
       return (rt, [])
    | M_PEmember_shift (asym, tag, member) ->
       let@ arg = arg_of_asym asym in
       let@ () = WellTyped.ensure_base_type arg.loc ~expect:Loc arg.bt in
       let@ layout = get_struct_decl loc tag in
       let@ _member_bt = get_member_type loc tag member layout in
       let it = it_of_arg arg in
       let vt = (Loc, memberShift_ (it, tag, member)) in
       return (rt_of_vt loc vt, [])
    | M_PEnot asym ->
       let@ arg = arg_of_asym asym in
       let@ () = WellTyped.ensure_base_type arg.loc ~expect:Bool arg.bt in
       let vt = (Bool, not_ (it_of_arg arg)) in
       return (rt_of_vt loc vt, [])
    | M_PEop (op, asym1, asym2) ->
       let@ arg1 = arg_of_asym asym1 in
       let@ arg2 = arg_of_asym asym2 in
       let v1 = it_of_arg arg1 in
       let v2 = it_of_arg arg2 in
       let@ (((ebt1, ebt2), rbt), result_it) = match op with
         | OpAdd ->   return (((Integer, Integer), Integer), IT.add_ (v1, v2))
         | OpSub ->   return (((Integer, Integer), Integer), IT.sub_ (v1, v2))
         | OpMul ->   return (((Integer, Integer), Integer), IT.mul_ (v1, v2))
         | OpDiv ->   return (((Integer, Integer), Integer), IT.div_ (v1, v2))
         | OpRem_f -> return (((Integer, Integer), Integer), IT.rem_f_ (v1, v2))
         | OpExp ->   return (((Integer, Integer), Integer), IT.exp_ (v1, v2))
         | OpEq ->    return (((Integer, Integer), Bool), IT.eq_ (v1, v2))
         | OpGt ->    return (((Integer, Integer), Bool), IT.gt_ (v1, v2))
         | OpLt ->    return (((Integer, Integer), Bool), IT.lt_ (v1, v2))
         | OpGe ->    return (((Integer, Integer), Bool), IT.ge_ (v1, v2))
         | OpLe ->    return (((Integer, Integer), Bool), IT.le_ (v1, v2))
         | OpAnd ->   return (((Bool, Bool), Bool), IT.and_ [v1; v2])
         | OpOr ->    return (((Bool, Bool), Bool), IT.or_ [v1; v2])
         | OpRem_t -> 
            let@ provable = provable loc in
            begin match provable (LC.T (and_ [le_ (int_ 0, v1); le_ (int_ 0, v2)])) with
            | `True ->
               (* if the arguments are non-negative, then rem or mod should be sound to use for rem_t *)
               return (((Integer, Integer), Integer), IT.mod_ (v1, v2))
            | `False ->
               let@ model = model () in
               let err = !^"Unsupported: rem_t applied to negative arguments" in
               fail (fun ctxt ->
                   let msg = Generic_with_model {err; model; ctxt} in
                   {loc; msg}
                 )
            end
       in
       let@ () = WellTyped.ensure_base_type arg1.loc ~expect:ebt1 arg1.bt in
       let@ () = WellTyped.ensure_base_type arg2.loc ~expect:ebt2 arg2.bt in
       return (rt_of_vt loc (rbt, result_it), [])
    | M_PEstruct _ ->
       Debug_ocaml.error "todo: PEstruct"
    | M_PEunion _ ->
       Debug_ocaml.error "todo: PEunion"
    | M_PEmemberof _ ->
       Debug_ocaml.error "todo: M_PEmemberof"
    | M_PEcall (called, asyms) ->
       let@ global = get_global () in
       let@ decl_typ = match called with
         | CF.Core.Impl impl -> 
            return (Global.get_impl_fun_decl global impl )
         | CF.Core.Sym sym -> 
            let@ (_, t, _) = get_fun_decl loc sym in
            return t
       in
       let@ args = args_of_asyms asyms in
       Spine.calltype_ft loc args decl_typ
    | M_PEassert_undef (asym, _uloc, ub) ->
       let@ arg = arg_of_asym asym in
       let@ () = WellTyped.ensure_base_type arg.loc ~expect:Bool arg.bt in
       let@ provable = provable loc in
       begin match provable (t_ (it_of_arg arg)) with
       | `True -> return (rt_of_vt loc (Unit, unit_), [])
       | `False ->
          let@ model = model () in
          fail (fun ctxt -> {loc; msg = Undefined_behaviour {ub; ctxt; model}})
       end
    | M_PEbool_to_integer asym ->
       let@ arg = arg_of_asym asym in
       let@ () = WellTyped.ensure_base_type arg.loc ~expect:Bool arg.bt in
       let vt = (Integer, (ite_ (it_of_arg arg, int_ 1, int_ 0))) in
       return (rt_of_vt loc vt, [])
    | M_PEconv_int (act, asym) ->
       let@ () = WellTyped.WCT.is_ct act.loc act.ct in
       let@ arg = arg_of_asym asym in
       let@ () = WellTyped.ensure_base_type arg.loc ~expect:Integer arg.bt in
       (* try to follow conv_int from runtime/libcore/std.core *)
       let arg_it = it_of_arg arg in
       let ity = match act.ct with
         | Integer ity -> ity
         | _ -> Debug_ocaml.error "conv_int applied to non-integer type"
       in
       let@ provable = provable loc in
       let fail_unrepresentable () = 
         let@ model = model () in
         fail (fun ctxt ->
             let msg = Int_unrepresentable 
                         {value = arg_it; ict = act.ct; ctxt; model} in
             {loc; msg}
           )
       in
       begin match ity with
       | Bool ->
          let vt = (Integer, ite_ (eq_ (arg_it, int_ 0), int_ 0, int_ 1)) in
          return (rt_of_vt loc vt, [])
       | _
            when Sctypes.is_unsigned_integer_type ity ->
          let result = match provable (t_ (representable_ (act.ct, arg_it))) with
            | `True -> arg_it
            | `False ->
               ite_ (representable_ (act.ct, arg_it),
                     arg_it,
                     wrapI ity arg_it)
          in
          return (rt_of_vt loc (Integer, result), [])
       | _ ->
          begin match provable (t_ (representable_ (act.ct, arg_it))) with
          | `True -> return (rt_of_vt loc (Integer, arg_it), [])
          | `False -> fail_unrepresentable ()
          end
       end
    | M_PEwrapI (act, asym) ->
       let@ arg = arg_of_asym asym in
       let@ () = WellTyped.ensure_base_type arg.loc ~expect:Integer arg.bt in
       let ity = match act.ct with
         | Integer ity -> ity
         | _ -> Debug_ocaml.error "wrapI applied to non-integer type"
       in
       let result = wrapI ity (it_of_arg arg) in
       return (rt_of_vt loc (Integer, result), [])
  in
  debug 3 (lazy (item "type" (RT.pp rt)));
  return (rt, per_path)


let rec check_tpexpr (e : 'bty mu_tpexpr) (typ : RT.t) : (per_path, type_error) m =
  let (M_TPexpr (loc, _annots, _, e_)) = e in
  let@ () = print_with_ctxt (fun ctxt ->
      debug 3 (lazy (action "checking pure expression"));
      debug 3 (lazy (item "expr" (group (pp_tpexpr e))));
      debug 3 (lazy (item "type" (RT.pp typ)));
      debug 3 (lazy (item "ctxt" (Context.pp ctxt)));
    )
  in
  match e_ with
  | M_PEif (casym, e1, e2) ->
     let@ carg = arg_of_asym casym in
     let@ () = WellTyped.ensure_base_type carg.loc ~expect:Bool carg.bt in
     let@ per_paths = ListM.mapM (fun (lc, e) ->
         pure begin
             let@ () = add_c (t_ lc) in
             let@ provable = provable loc in
             match provable (t_ (bool_ false)) with
             | `True -> return []
             | `False -> check_tpexpr_in [loc_of_tpexpr e; loc] e typ
           end
       ) [(it_of_arg carg, e1); (not_ (it_of_arg carg), e2)] in
     return (List.concat per_paths)
  | M_PEcase (asym, pats_es) ->
     let@ arg = arg_of_asym asym in
     let@ per_paths = ListM.mapM (fun (pat, pe) ->
         pure begin
             let@ () = pattern_match (it_of_arg arg) pat in
             let@ provable = provable loc in
             match provable (t_ (bool_ false)) with
             | `True -> return []
             | `False -> check_tpexpr_in [loc_of_tpexpr pe; loc] pe typ
           end
       ) pats_es in
     return (List.concat per_paths)
  | M_PElet (p, e1, e2) ->
     let@ (rt, per_path1) = infer_pexpr e1 in
     let@ () = match p with
       | M_Symbol sym -> bind (Some (Loc (loc_of_pexpr e1))) sym rt
       | M_Pat pat -> pattern_match_rt (Loc (loc_of_pexpr e1)) pat rt
     in
     let@ per_path2 = check_tpexpr e2 typ in
     return (per_path1 @ per_path2)
  | M_PEdone asym ->
     let@ arg = arg_of_asym asym in
     let@ per_path = Spine.subtype loc arg typ in
     return per_path
  | M_PEundef (_loc, ub) ->
     let@ provable = provable loc in
     begin match provable (t_ (bool_ false)) with
     | `True -> return []
     | `False ->
        let@ model = model () in
        fail (fun ctxt -> {loc; msg = Undefined_behaviour {ub; ctxt; model}})
     end
  | M_PEerror (err, asym) ->
     let@ arg = arg_of_asym asym in
     let@ provable = provable loc in
     begin match provable (t_ (bool_ false)) with
     | `True -> return []
     | `False ->
        let@ model = model () in
        fail (fun ctxt -> {loc; msg = StaticError {err; ctxt; model}})
     end


and check_tpexpr_in locs e typ =
  let@ loc_trace = get_loc_trace () in
  in_loc_trace (locs @ loc_trace) (fun () -> check_tpexpr e typ)

(*** impure expression inference **********************************************)



(* `t` is used for the type of Run/Goto: Goto has no return type
   (because the control flow does not return there), but instead
   returns `False`. Type inference of impure expressions returns
   either a return type and a typing context or `False` *)
type 'a orFalse = 
  | Normal of 'a
  | False

let pp_or_false (ppf : 'a -> Pp.document) (m : 'a orFalse) : Pp.document = 
  match m with
  | Normal a -> ppf a
  | False -> parens !^"no return"



let all_empty loc = 
  let@ provable = provable loc in
  let@ all_resources = all_resources () in
  ListM.iterM (fun resource ->
      let constr = match resource with
        | (P p, _) -> t_ (not_ p.permission)
        | (Q p, _) -> forall_ (p.q, BT.Integer) (not_ p.permission)
      in
      match provable constr with
      | `True -> return () 
      | `False -> 
         let@ model = model () in 
         fail (fun ctxt -> {loc; msg = Unused_resource {resource; ctxt; model}})
    ) all_resources


type labels = (AT.lt * label_kind) SymMap.t


let infer_expr labels (e : 'bty mu_expr) : (RT.t * per_path, type_error) m =
  let (M_Expr (loc, _annots, e_)) = e in
  let@ () = print_with_ctxt (fun ctxt ->
       debug 3 (lazy (action "inferring expression"));
       debug 3 (lazy (item "expr" (group (pp_expr e))));
       debug 3 (lazy (item "ctxt" (Context.pp ctxt)));
    )
  in
  let@ result = match e_ with
    | M_Epure pe -> 
       infer_pexpr pe
    | M_Ememop memop ->
       let pointer_op op asym1 asym2 = 
         let@ arg1 = arg_of_asym asym1 in
         let@ arg2 = arg_of_asym asym2 in
         let@ () = WellTyped.ensure_base_type arg1.loc ~expect:Loc arg1.bt in
         let@ () = WellTyped.ensure_base_type arg2.loc ~expect:Loc arg2.bt in
         let vt = (Bool, op (it_of_arg arg1, it_of_arg arg2)) in
         return (rt_of_vt loc vt, [])
       in
       begin match memop with
       | M_PtrEq (asym1, asym2) -> 
          pointer_op eq_ asym1 asym2
       | M_PtrNe (asym1, asym2) -> 
          pointer_op ne_ asym1 asym2
       | M_PtrLt (asym1, asym2) -> 
          pointer_op ltPointer_ asym1 asym2
       | M_PtrGt (asym1, asym2) -> 
          pointer_op gtPointer_ asym1 asym2
       | M_PtrLe (asym1, asym2) -> 
          pointer_op lePointer_ asym1 asym2
       | M_PtrGe (asym1, asym2) -> 
          pointer_op gePointer_ asym1 asym2
       | M_Ptrdiff (act, asym1, asym2) -> 
          let@ () = WellTyped.WCT.is_ct act.loc act.ct in
          let@ arg1 = arg_of_asym asym1 in
          let@ arg2 = arg_of_asym asym2 in
          let@ () = WellTyped.ensure_base_type arg1.loc ~expect:Loc arg1.bt in
          let@ () = WellTyped.ensure_base_type arg2.loc ~expect:Loc arg2.bt in
          (* copying and adapting from memory/concrete/impl_mem.ml *)
          let divisor = match act.ct with
            | Array (item_ty, _) -> Memory.size_of_ctype item_ty
            | ct -> Memory.size_of_ctype ct
          in
          let v =
            div_
              (sub_ (pointerToIntegerCast_ (it_of_arg arg1),
                     pointerToIntegerCast_ (it_of_arg arg2)),
               int_ divisor)
          in
          let vt = (Integer, v) in
          return (rt_of_vt loc vt, [])
       | M_IntFromPtr (act_from, act_to, asym) ->
          let@ () = WellTyped.WCT.is_ct act_from.loc act_from.ct in
          let@ () = WellTyped.WCT.is_ct act_to.loc act_to.ct in
          let@ arg = arg_of_asym asym in
          let@ () = WellTyped.ensure_base_type arg.loc ~expect:Loc arg.bt in
          let v = pointerToIntegerCast_ (it_of_arg arg) in
          let@ () = 
            (* after discussing with Kavyan *)
            let@ provable = provable loc in
            let lc = t_ (representable_ (act_to.ct, v)) in
            begin match provable lc with
            | `True -> return () 
            | `False ->
               let@ model = model () in
               fail (fun ctxt ->
                   let ict = act_to.ct in
                   let value = it_of_arg arg in
                   {loc; msg = Int_unrepresentable {value; ict; ctxt; model}}
                 )
            end
          in
          let vt = (Integer, v) in
          return (rt_of_vt loc vt, [])
       | M_PtrFromInt (act_from, act2_to, asym) ->
          let@ () = WellTyped.WCT.is_ct act_from.loc act_from.ct in
          let@ () = WellTyped.WCT.is_ct act2_to.loc act2_to.ct in
          let@ arg = arg_of_asym asym in
          let@ () = WellTyped.ensure_base_type arg.loc ~expect:Integer arg.bt in
          let vt = (Loc, integerToPointerCast_ (it_of_arg arg)) in
          return (rt_of_vt loc vt, [])
       | M_PtrValidForDeref (act, asym) ->
          (* check *)
          let@ () = WellTyped.WCT.is_ct act.loc act.ct in
          let@ arg = arg_of_asym asym in
          let@ () = WellTyped.ensure_base_type arg.loc ~expect:Loc arg.bt in
          let vt = (Bool, aligned_ (it_of_arg arg, act.ct)) in
          return (rt_of_vt loc vt, [])
       | M_PtrWellAligned (act, asym) ->
          let@ () = WellTyped.WCT.is_ct act.loc act.ct in
          let@ arg = arg_of_asym asym in
          let@ () = WellTyped.ensure_base_type arg.loc ~expect:Loc arg.bt in
          let vt = (Bool, aligned_ (it_of_arg arg, act.ct)) in
          return (rt_of_vt loc vt, [])
       | M_PtrArrayShift (asym1, act, asym2) ->
          let@ rt = infer_array_shift loc asym1 act.loc act.ct asym2 in
          return (rt, [])
       | M_Memcpy _ (* (asym 'bty * asym 'bty * asym 'bty) *) ->
          Debug_ocaml.error "todo: M_Memcpy"
       | M_Memcmp _ (* (asym 'bty * asym 'bty * asym 'bty) *) ->
          Debug_ocaml.error "todo: M_Memcmp"
       | M_Realloc _ (* (asym 'bty * asym 'bty * asym 'bty) *) ->
          Debug_ocaml.error "todo: M_Realloc"
       | M_Va_start _ (* (asym 'bty * asym 'bty) *) ->
          Debug_ocaml.error "todo: M_Va_start"
       | M_Va_copy _ (* (asym 'bty) *) ->
          Debug_ocaml.error "todo: M_Va_copy"
       | M_Va_arg _ (* (asym 'bty * actype 'bty) *) ->
          Debug_ocaml.error "todo: M_Va_arg"
       | M_Va_end _ (* (asym 'bty) *) ->
          Debug_ocaml.error "todo: M_Va_end"
       end
    | M_Eaction (M_Paction (_pol, M_Action (aloc, action_))) ->
       begin match action_ with
       | M_Create (asym, act, _prefix) -> 
          let@ () = WellTyped.WCT.is_ct act.loc act.ct in
          let@ arg = arg_of_asym asym in
          let@ () = WellTyped.ensure_base_type arg.loc ~expect:Integer arg.bt in
          let ret = Sym.fresh () in
          let oarg_s, oarg = IT.fresh (Resources.block_oargs) in
          let resource = 
            (oarg_s, (P {
                name = Block act.ct; 
                pointer = sym_ (ret, Loc);
                permission = bool_ true;
                iargs = [];
              },
             IT.bt oarg))
          in
          let rt = 
            RT.Computational ((ret, Loc), (loc, None),
            LRT.Constraint (t_ (representable_ (pointer_ct act.ct, sym_ (ret, Loc))), (loc, None),
            LRT.Constraint (t_ (alignedI_ ~align:(it_of_arg arg) ~t:(sym_ (ret, Loc))), (loc, None),
            LRT.Resource (resource, (loc, None), 
            LRT.I))))
          in
          return (rt, [])
       | M_CreateReadOnly (sym1, ct, sym2, _prefix) -> 
          Debug_ocaml.error "todo: CreateReadOnly"
       | M_Alloc (ct, sym, _prefix) -> 
          Debug_ocaml.error "todo: Alloc"
       | M_Kill (M_Dynamic, asym) -> 
          Debug_ocaml.error "todo: Free"
       | M_Kill (M_Static ct, asym) -> 
          let@ () = WellTyped.WCT.is_ct loc ct in
          let@ arg = arg_of_asym asym in
          let@ () = WellTyped.ensure_base_type arg.loc ~expect:Loc arg.bt in
          let@ _ = 
            RI.Special.predicate_request ~recursive:true loc (Access Kill) ({
              name = Owned ct;
              pointer = it_of_arg arg;
              permission = bool_ true;
              iargs = [];
            }, None)
          in
          let rt = RT.Computational ((Sym.fresh (), Unit), (loc, None), I) in
          return (rt, [])
       | M_Store (_is_locking, act, pasym, vasym, mo) -> 
          let@ () = WellTyped.WCT.is_ct act.loc act.ct in
          let@ parg = arg_of_asym pasym in
          let@ varg = arg_of_asym vasym in
          let@ () = WellTyped.ensure_base_type loc ~expect:(BT.of_sct act.ct) varg.bt in
          let@ () = WellTyped.ensure_base_type loc ~expect:Loc parg.bt in
          (* The generated Core program will in most cases before this
             already have checked whether the store value is
             representable and done the right thing. Pointers, as I
             understand, are an exception. *)
          let@ () = 
            let in_range_lc = good_ (act.ct, it_of_arg varg) in
            let@ provable = provable loc in
            let holds = provable (t_ in_range_lc) in
            match holds with
            | `True -> return () 
            | `False ->
               let@ model = model () in
               fail (fun ctxt ->
                   let msg = 
                     Write_value_bad {
                         ct = act.ct; 
                         location = it_of_arg parg; 
                         value = it_of_arg varg; 
                         ctxt;
                         model}
                   in
                   {loc; msg}
                 )
          in
          let@ _ = 
            RI.Special.predicate_request ~recursive:true loc (Access (Store None)) ({
                name = Block act.ct; 
                pointer = it_of_arg parg;
                permission = bool_ true;
                iargs = [];
              }, None)
          in
          let oarg_s, oarg = IT.fresh (owned_oargs act.ct) in
          let resource = 
            (oarg_s, (P {
                name = Owned act.ct;
                pointer = it_of_arg parg;
                permission = bool_ true;
                iargs = [];
               },
             IT.bt oarg))
          in
          let value_constr = 
            t_ (eq_ (recordMember_ ~member_bt:(BT.of_sct act.ct) (oarg, value_sym),
                     it_of_arg varg))
          in
          let rt = 
            RT.Computational ((Sym.fresh (), Unit), (loc, None),
            Resource (resource, (loc, None),
            Constraint (value_constr, (loc, None),
            LRT.I)))
          in
          return (rt, [])
       | M_Load (act, pasym, _mo) -> 
          let@ () = WellTyped.WCT.is_ct act.loc act.ct in
          let@ parg = arg_of_asym pasym in
          let@ () = WellTyped.ensure_base_type parg.loc ~expect:Loc parg.bt in
          let@ (point, point_oargs) = 
            restore_resources 
              (RI.Special.predicate_request ~recursive:true loc (Access (Load None)) ({ 
                     name = Owned act.ct;
                     pointer = it_of_arg parg;
                     permission = bool_ true;
                     iargs = [];
                   }, None))
          in
          let value = snd (List.hd (oargs_list point_oargs)) in
          (* let@ () =  *)
          (*   let@ provable = provable loc in *)
          (*   match provable (t_ init) with *)
          (*   | `True -> return ()  *)
          (*   | `False -> *)
          (*      let@ model = model () in *)
          (*      fail (fun ctxt -> {loc; msg = Uninitialised_read {ctxt; model}}) *)
          (* in *)
          let ret = Sym.fresh () in
          let rt = 
            RT.Computational ((ret, IT.bt value), (loc, None),
            Constraint (t_ (def_ ret value), (loc, None),
                        (* TODO: check *)
            Constraint (t_ (good_ (act.ct, value)), (loc, None),
            LRT.I)))
          in
          return (rt, [])
       | M_RMW (ct, sym1, sym2, sym3, mo1, mo2) -> 
          Debug_ocaml.error "todo: RMW"
       | M_Fence mo -> 
          Debug_ocaml.error "todo: Fence"
       | M_CompareExchangeStrong (ct, sym1, sym2, sym3, mo1, mo2) -> 
          Debug_ocaml.error "todo: CompareExchangeStrong"
       | M_CompareExchangeWeak (ct, sym1, sym2, sym3, mo1, mo2) -> 
          Debug_ocaml.error "todo: CompareExchangeWeak"
       | M_LinuxFence mo -> 
          Debug_ocaml.error "todo: LinuxFemce"
       | M_LinuxLoad (ct, sym1, mo) -> 
          Debug_ocaml.error "todo: LinuxLoad"
       | M_LinuxStore (ct, sym1, sym2, mo) -> 
          Debug_ocaml.error "todo: LinuxStore"
       | M_LinuxRMW (ct, sym1, sym2, mo) -> 
          Debug_ocaml.error "todo: LinuxRMW"
       end
    | M_Eskip -> 
       let rt = RT.Computational ((Sym.fresh (), Unit), (loc, None), I) in
       return (rt, [])
    | M_Eccall (act, afsym, asyms) ->
       (* todo: do anything with act? *)
       let@ () = WellTyped.WCT.is_ct act.loc act.ct in
       let@ args = args_of_asyms asyms in
       let@ (_loc, ft, _) = get_fun_decl loc afsym.sym in
       Spine.calltype_ft loc args ft
    | M_Eproc (fname, asyms) ->
       let@ (_, decl_typ) = match fname with
         | CF.Core.Impl impl -> 
            let@ global = get_global () in
            return (loc, Global.get_impl_fun_decl global impl)
         | CF.Core.Sym sym -> 
            let@ (loc, fun_decl, _) = get_fun_decl loc sym in
            return (loc, fun_decl)
       in
       let@ args = args_of_asyms asyms in
       Spine.calltype_ft loc args decl_typ
    | M_Erpredicate (pack_unpack, TPU_Predicate pname, asyms) ->
       let@ global = get_global () in
       let@ pname, def = Typing.todo_get_resource_predicate_def_s loc (Id.s pname) in
       let@ pointer_asym, iarg_asyms = match asyms with
         | pointer_asym :: iarg_asyms -> return (pointer_asym, iarg_asyms)
         | _ -> fail (fun _ -> {loc; msg = Generic !^"pointer argument to predicate missing"})
       in
       let@ pointer_arg = arg_of_asym pointer_asym in
       let@ iargs = args_of_asyms iarg_asyms in
       let@ () = 
         (* "+1" because of pointer argument *)
         let has, expect = List.length iargs + 1, List.length def.iargs + 1 in
         if has = expect then return ()
         else fail (fun _ -> {loc; msg = Number_arguments {has; expect}})
       in
       let@ () = WellTyped.ensure_base_type pointer_arg.loc ~expect:Loc pointer_arg.bt in
       let@ () = 
         ListM.iterM (fun (arg, expected_sort) ->
             WellTyped.ensure_base_type arg.loc ~expect:expected_sort arg.bt
           ) (List.combine iargs (List.map snd def.iargs))
       in
       let instantiated_clauses = 
         let subst = 
           make_subst (
               (def.pointer, it_of_arg pointer_arg) ::
               List.map2 (fun (def_ia, _) ia -> (def_ia, it_of_arg ia)) def.iargs iargs
             )
         in
         List.map (ResourcePredicates.subst_clause subst) def.clauses
       in
       let@ provable = provable loc in
       let@ right_clause = 
         let rec try_clauses negated_guards clauses = 
           match clauses with
           | clause :: clauses -> 
              begin match provable (t_ (and_ (clause.guard :: negated_guards))) with
              | `True -> return clause.packing_ft
              | `False -> try_clauses (not_ clause.guard :: negated_guards) clauses
              end
           | [] -> 
              let err = 
                !^"do not have enough information for" ^^^
                (match pack_unpack with Pack -> !^"packing" | Unpack -> !^"unpacking") ^^^
                Sym.pp pname
              in
              fail (fun _ -> {loc; msg = Generic err})
         in
         try_clauses [] instantiated_clauses
       in
       begin match pack_unpack with
       | Unpack ->
          let@ (pred, O pred_oargs) =
            RI.Special.predicate_request ~recursive:false
              loc (UnpackPredicate pname) ({
                name = PName pname;
                pointer = it_of_arg pointer_arg;
                permission = bool_ true;
                iargs = List.map it_of_arg iargs;
              }, None)
          in
          let condition, outputs = LAT.logical_arguments_and_return right_clause in
          let lc = 
            eq_ (pred_oargs, 
                 record_ (List.map (fun (o : OutputDef.entry) -> (o.name, o.value)) outputs))
          in
          let lrt = LRT.concat condition (Constraint (t_ lc, (loc, None), I)) in
          return (RT.Computational ((Sym.fresh (), BT.Unit), (loc, None), lrt), [])
       | Pack ->
          let@ (output_assignment, per_path) = Spine.calltype_packing loc pname right_clause in
          let output = record_ (List.map (fun (o : OutputDef.entry) -> (o.name, o.value)) output_assignment) in
          let oarg_s, oarg = IT.fresh (IT.bt output) in
          let resource = 
            (oarg_s, (P {
              name = PName pname;
              pointer = it_of_arg pointer_arg;
              permission = bool_ true;
              iargs = List.map it_of_arg iargs;
            }, IT.bt oarg))
          in
          let rt =
            (RT.Computational ((Sym.fresh (), BT.Unit), (loc, None),
             Resource (resource, (loc, None),
             Constraint (t_ (eq_ (oarg, output)), (loc, None), 
             LRT.I))))
          in
          return (rt, per_path)
       end
    | M_Erpredicate (pack_unpack, TPU_Struct tag, asyms) ->
       let@ _layout = get_struct_decl loc tag in
       let@ args = args_of_asyms asyms in
       let@ () = 
         (* "+1" because of pointer argument *)
         let has = List.length args in
         if has = 1 then return ()
         else fail (fun _ -> {loc; msg = Number_arguments {has; expect = 1}})
       in
       let pointer_arg = List.hd args in
       let@ () = WellTyped.ensure_base_type pointer_arg.loc ~expect:Loc pointer_arg.bt in
       begin match pack_unpack with
       | Pack ->
          let situation = TypeErrors.PackStruct tag in
          let@ (resource, O resource_oargs) = 
            RI.Special.fold_struct ~recursive:true loc situation tag 
              (it_of_arg pointer_arg) (bool_ true) 
          in
          let oargs_s, oargs = IT.fresh (IT.bt resource_oargs) in
          let rt = 
            RT.Computational ((Sym.fresh (), BT.Unit), (loc, None),
            LRT.Resource ((oargs_s, (P resource, IT.bt oargs)), (loc, None), 
            LRT.Constraint (t_ (eq_ (oargs, resource_oargs)), (loc, None),
            LRT.I)))
          in
          return (rt, [])
       | Unpack ->
          let situation = TypeErrors.UnpackStruct tag in
          let@ resources = 
            RI.Special.unfold_struct ~recursive:true loc situation tag 
              (it_of_arg pointer_arg) (bool_ true) 
          in
          let constraints, resources = 
            List.fold_left_map (fun acc (r, O o) -> 
                let oarg_s, oarg = IT.fresh (IT.bt o) in
                let acc = acc @ [(t_ (eq_ (oarg, o)), (loc, None))] in
                acc, ((oarg_s, (r, IT.bt oarg)), (loc, None))
              ) [] resources in
          let lrt = LRT.mResources resources (LRT.mConstraints constraints LRT.I) in
          let rt = RT.Computational ((Sym.fresh (), BT.Unit), (loc, None), lrt) in
          return (rt, [])
       end
    | M_Elpredicate (have_show, pname, asyms) ->
       let@ global = get_global () in
       let@ pname, def = Typing.todo_get_logical_predicate_def_s loc (Id.s pname) in
       let@ (args, per_path) =
         restore_resources begin 
           let@ supplied_args = args_of_asyms asyms in
           Spine.calltype_lpred_argument_inference loc pname 
             supplied_args def.infer_arguments 
           end
       in
       (* let@ () = 
        *   let has, expect = List.length args, List.length def.args in
        *   if has = expect then return ()
        *   else fail (fun _ -> {loc; msg = Number_arguments {has; expect}})
        * in
        * let@ () = 
        *   ListM.iterM (fun (arg, expected_sort) ->
        *       WellTyped.ensure_base_type arg.loc ~expect:expected_sort arg.bt
        *     ) (List.combine args (List.map snd def.args))
        * in *)
       let rt = 
         RT.Computational ((Sym.fresh (), BT.Unit), (loc, None), 
         LRT.Constraint (LC.t_ (pred_ pname args def.return_bt), (loc, None),
         LRT.I))
       in
       let@ def_body = match def.definition with
         | Def body -> return body
         | Uninterp -> 
            let err = Generic !^"cannot use 'have' or 'show' with uninterpreted predicates" in
            fail (fun _ -> {loc; msg = err})
       in
       begin match have_show with
       | Have
       | Show ->
          let@ constraints = all_constraints () in
          let extra_assumptions = match args with
            | [] -> []
            | key_arg :: _ ->  
               let key_arg_bt = IT.bt key_arg in
               LCSet.fold (fun lc acc ->
                   match lc with
                   | Forall ((s, bt), t) when BT.equal bt key_arg_bt ->
                      IT.subst (IT.make_subst [(s, key_arg)]) t :: acc
                   | _ -> 
                      acc
                 ) constraints []
          in
          let@ provable = provable loc in
          let lc = LC.t_ (impl_ (and_ extra_assumptions, pred_ pname args def.return_bt)) in
          begin match provable lc with
          | `True -> return (rt, per_path)
          | `False ->
             let@ model = model () in
             fail (fun ctxt -> {loc; msg = Unsat_constraint {constr = lc; info = (loc, None); ctxt; model}})
          end
       end
  in
  debug 3 (lazy (RT.pp (fst result)));
  return result

(* check_expr: type checking for impure epressions; type checks `e`
   against `typ`, which is either a return type or `False`; returns
   either an updated environment, or `False` in case of Goto *)
let rec check_texpr labels (e : 'bty mu_texpr) (typ : RT.t orFalse) 
        : (per_path, type_error) m =

  let@ () = increase_trace_length () in
  let (M_TExpr (loc, _annots, e_)) = e in
  let@ () = print_with_ctxt (fun ctxt ->
      debug 3 (lazy (action "checking expression"));
      debug 3 (lazy (item "expr" (group (pp_texpr e))));
      debug 3 (lazy (item "type" (pp_or_false RT.pp typ)));
      debug 3 (lazy (item "ctxt" (Context.pp ctxt)));
    )
  in
  let@ result = match e_ with
    | M_Eif (casym, e1, e2) ->
       let@ carg = arg_of_asym casym in
       let@ () = WellTyped.ensure_base_type carg.loc ~expect:Bool carg.bt in
       let@ per_paths = ListM.mapM (fun (lc, nm, e) ->
           pure begin
               let@ () = add_c (t_ lc) in
               let@ provable = provable loc in
               match provable (t_ (bool_ false)) with
               | `True -> return []
               | `False ->
                 let start = time_log_start (nm ^ " branch") (Locations.to_string loc) in
                 let@ per_path = check_texpr_in [loc_of_texpr e; loc] labels e typ in
                 time_log_end start;
                 return per_path
             end
         ) [(it_of_arg carg, "true", e1); (not_ (it_of_arg carg), "false", e2)] in
       return (List.concat per_paths)
    | M_Ebound (_, e) ->
       check_texpr labels e typ 
    | M_End _ ->
       Debug_ocaml.error "todo: End"
    | M_Ecase (asym, pats_es) ->
       let@ arg = arg_of_asym asym in
       let@ per_paths = ListM.mapM (fun (pat, pe) ->
           pure begin
               let@ () = pattern_match (it_of_arg arg) pat in
               let@ provable = provable loc in
               match provable (t_ (bool_ false)) with
               | `True -> return []
               | `False -> check_texpr_in [loc_of_texpr pe; loc] labels pe typ
             end
         ) pats_es in
       return (List.concat per_paths)
    | M_Elet (p, e1, e2) ->
       let@ (rt, per_path1) = infer_pexpr e1 in
       let@ () = match p with 
         | M_Symbol sym -> bind (Some (Loc (loc_of_pexpr e1))) sym rt
         | M_Pat pat -> pattern_match_rt (Loc (loc_of_pexpr e1)) pat rt
       in
       let@ per_path2 = check_texpr labels e2 typ in
       return (per_path1 @ per_path2)
    | M_Ewseq (pat, e1, e2) ->
       let@ (rt, per_path1) = infer_expr labels e1 in
       let@ () = pattern_match_rt (Loc (loc_of_expr e1)) pat rt in
       let@ per_path2 = check_texpr labels e2 typ in
       return (per_path1 @ per_path2)
    | M_Esseq (pat, e1, e2) ->
       let@ (rt, per_path1) = infer_expr labels e1 in
       let@ () = match pat with
         | M_Symbol sym -> bind (Some (Loc (loc_of_expr e1))) sym rt
         | M_Pat pat -> pattern_match_rt (Loc (loc_of_expr e1)) pat rt
       in
       let@ per_path2 = check_texpr labels e2 typ in
       return (per_path1 @ per_path2)
    | M_Edone asym ->
       begin match typ with
       | Normal typ ->
          let@ arg = arg_of_asym asym in
          let@ per_path = Spine.subtype loc arg typ in
          let@ () = all_empty loc in
          return per_path
       | False ->
          let err = 
            "This expression returns but is expected "^
              "to have non-return type."
          in
          fail (fun _ -> {loc; msg = Generic !^err})
       end
    | M_Eundef (_loc, ub) ->
       let@ provable = provable loc in
       begin match provable (t_ (bool_ false)) with
       | `True -> return []
       | `False ->
          let@ model = model () in
          fail (fun ctxt -> {loc; msg = Undefined_behaviour {ub; ctxt; model}})
       end
  | M_Eerror (err, asym) ->
     let@ arg = arg_of_asym asym in
     let@ provable = provable loc in
     begin match provable (t_ (bool_ false)) with
     | `True -> return []
     | `False ->
        let@ model = model () in
        fail (fun ctxt -> {loc; msg = StaticError {err; ctxt; model}})
     end
    | M_Erun (label_sym, asyms) ->
       let@ (lt,lkind) = match SymMap.find_opt label_sym labels with
         | None -> fail (fun _ -> {loc; msg = Generic (!^"undefined code label" ^/^ Sym.pp label_sym)})
         | Some (lt,lkind) -> return (lt,lkind)
       in
       let@ args = args_of_asyms asyms in
       let@ per_path = Spine.calltype_lt loc args (lt,lkind) in
       let@ () = all_empty loc in
       return per_path

  in
  return result


and check_texpr_in locs labels e typ =
  let@ loc_trace = get_loc_trace () in
  in_loc_trace (locs @ loc_trace) (fun () -> check_texpr labels e typ)



let check_and_bind_arguments rt_subst loc arguments (function_typ : 'rt AT.t) = 
  let rec check args (ftyp : 'rt AT.t) =
    match args, ftyp with
    | ((aname, abt) :: args), (AT.Computational ((lname, sbt), _info, ftyp)) ->
       if BT.equal abt sbt then
         let new_lname = Sym.fresh () in
         let subst = make_subst [(lname, sym_ (new_lname, sbt))] in
         let ftyp' = AT.subst rt_subst subst ftyp in
         let@ () = add_l new_lname abt in
         let@ () = add_a aname (abt,new_lname) in
         check args ftyp'
       else
         fail (fun _ -> {loc; msg = Mismatch {has = abt; expect = sbt}})
    | [], (AT.Computational (_, _, _))
    | (_ :: _), (AT.L _) ->
       let expect = AT.count_computational function_typ in
       let has = List.length arguments in
       fail (fun _ -> {loc; msg = Number_arguments {expect; has}})
    | [], AT.L ftyp ->
       let open LAT in
       let rec bind resources = function
         | Define ((sname, it), _, ftyp) ->
            let@ () = add_l sname (IT.bt it) in
            let@ () = add_c (t_ (def_ sname it)) in
            bind resources ftyp
         | Resource ((s, (re, bt)), _, ftyp) ->
            let@ () = add_l s bt in
            bind ((re, O (sym_ (s, bt))) :: resources) ftyp
         | Constraint (lc, _, ftyp) ->
            let@ () = add_c lc in
            bind resources ftyp
         | I rt ->
            return (rt, resources)
       in
       bind [] ftyp
  in
  check arguments function_typ


let do_post_typing info =
  let eqs_data = List.filter_map (function
    | SuggestEqsData x -> Some x) info
  in
  SuggestEqs.warn_missing_spec_eqs eqs_data;
  return ()


(* check_function: type check a (pure) function *)
let check_function 
      (loc : loc) 
      (info : string) 
      (arguments : (Sym.t * BT.t) list) 
      (rbt : BT.t) 
      (body : 'bty mu_tpexpr) 
      (function_typ : AT.ft)
    : (unit, type_error) Typing.m =
  debug 2 (lazy (headline ("checking function " ^ info)));
  pure begin
      let@ (rt, resources) = 
        check_and_bind_arguments RT.subst loc arguments function_typ 
      in
      let@ () = ListM.iterM (add_r (Some (Label "start"))) resources in
      (* rbt consistency *)
      let@ () = 
        let Computational ((sname, sbt), _info, t) = rt in
        WellTyped.ensure_base_type loc ~expect:sbt rbt
      in
      let@ per_path = check_tpexpr_in [loc] body rt in
      let@ () = do_post_typing per_path in
      return ()
    end

(* check_procedure: type check an (impure) procedure *)
let check_procedure 
      (loc : loc) 
      (fsym : Sym.t)
      (arguments : (Sym.t * BT.t) list)
      (rbt : BT.t) 
      (body : 'bty mu_texpr)
      (function_typ : AT.ft) 
      (label_defs : 'bty mu_label_defs)
    : (unit, type_error) Typing.m =
  debug 2 (lazy (headline ("checking procedure " ^ Sym.pp_string fsym)));
  debug 2 (lazy (item "type" (AT.pp RT.pp function_typ)));

  pure begin 
      (* check and bind the function arguments *)
      let@ ((rt, label_defs), resources) = 
        let function_typ = AT.map (fun rt -> (rt, label_defs)) function_typ in
        let rt_and_label_defs_subst substitution (rt, label_defs) = 
          (RT.subst substitution rt, 
           subst_label_defs (AT.subst False.subst) substitution label_defs)
        in
        check_and_bind_arguments rt_and_label_defs_subst
          loc arguments function_typ 
      in
      (* rbt consistency *)
      let@ () = 
        let Computational ((sname, sbt), _info, t) = rt in
        WellTyped.ensure_base_type loc ~expect:sbt rbt
      in
      (* check well-typedness of labels and record their types *)
      let@ labels = 
        PmapM.foldM (fun sym def acc ->
            pure begin 
                match def with
                | M_Return (loc, lt) ->
                   let@ () = WellTyped.WLT.welltyped "return label" loc lt in
                   return (SymMap.add sym (lt, Return) acc)
                | M_Label (loc, lt, _, _, annots) -> 
                   let label_kind = match CF.Annot.get_label_annot annots with
                     | Some (LAloop_body loop_id) -> Loop
                     | Some (LAloop_continue loop_id) -> Loop
                     | _ -> Other
                   in
                   let@ () = WellTyped.WLT.welltyped "label" loc lt in
                   return (SymMap.add sym (lt, label_kind) acc)
              end
          ) label_defs SymMap.empty 
      in
      (* check each label *)
      let check_label lsym def per_path1 =
        pure begin 
          match def with
          | M_Return (loc, lt) ->
             return per_path1
          | M_Label (loc, lt, args, body, annots) ->
             debug 2 (lazy (headline ("checking label " ^ Sym.pp_string lsym)));
             debug 2 (lazy (item "type" (AT.pp False.pp lt)));
             let label_name = match Sym.description lsym with
               | Sym.SD_Id l -> l
               | _ -> Debug_ocaml.error "label without name"
             in
             let@ (rt, resources) = 
               check_and_bind_arguments False.subst loc args lt 
             in
             let@ () = ListM.iterM (add_r (Some (Label label_name))) resources in
             let@ per_path2 = check_texpr_in [loc] labels body False in
             return (per_path1 @ per_path2)
          end
      in
      let check_body () = 
        pure begin 
            debug 2 (lazy (headline ("checking function body " ^ Sym.pp_string fsym)));
            let@ () = ListM.iterM (add_r (Some (Label "start"))) resources in
            check_texpr labels body (Normal rt)
          end
      in
      let@ per_path = check_body () in
      let@ per_path = PmapM.foldM check_label label_defs per_path in
      let@ () = do_post_typing per_path in
      return ()
    end

 

let only = ref None


let check mu_file = 
  let () = Debug_ocaml.begin_csv_timing "total" in

  let () = Debug_ocaml.begin_csv_timing "tagDefs" in
  let@ () = 
    (* check and record tagDefs *)
    let@ () = 
      PmapM.iterM (fun tag def ->
          match def with
          | M_UnionDef _ -> unsupported Loc.unknown !^"todo: union types"
          | M_StructDef layout -> add_struct_decl tag layout
        ) mu_file.mu_tagDefs
    in
    let@ () = 
      PmapM.iterM (fun tag def ->
          let open Memory in
          match def with
          | M_UnionDef _ -> 
             unsupported Loc.unknown !^"todo: union types"
          | M_StructDef layout -> 
             ListM.iterM (fun piece ->
                 match piece.member_or_padding with
                 | Some (name, ct) -> WellTyped.WCT.is_ct Loc.unknown ct
                 | None -> return ()
               ) layout
        ) mu_file.mu_tagDefs
    in
    return ()
  in
  let () = Debug_ocaml.end_csv_timing "tagDefs" in


  let () = Debug_ocaml.begin_csv_timing "impls" in
  let@ () = 
    (* check and record impls *)
    let open Global in
    PmapM.iterM (fun impl impl_decl ->
        let descr = CF.Implementation.string_of_implementation_constant impl in
        match impl_decl with
        | M_Def (rt, rbt, pexpr) -> 
           let@ () = WellTyped.WRT.welltyped Loc.unknown rt in
           let@ () = WellTyped.WBT.is_bt Loc.unknown rbt in
           let@ () = check_function Loc.unknown descr [] rbt pexpr (AT.L (LAT.I rt)) in
           add_impl_constant impl rt
        | M_IFun (ft, rbt, args, pexpr) ->
           let@ () = WellTyped.WFT.welltyped "implementation-defined function" Loc.unknown ft in
           let@ () = WellTyped.WBT.is_bt Loc.unknown rbt in
           let@ () = check_function Loc.unknown descr args rbt pexpr ft in
           add_impl_fun_decl impl ft
      ) mu_file.mu_impl
  in
  let () = Debug_ocaml.end_csv_timing "impls" in
  

  let () = Debug_ocaml.begin_csv_timing "logical predicates" in
  let@ () = 
    (* check and record logical predicate defs *)
    Pp.progress_simple "checking specifications" "logical predicate welltypedness";
    ListM.iterM (fun (name,(def : LP.definition)) -> 
        let@ () = WellTyped.WLPD.welltyped def in
        add_logical_predicate name def
      ) mu_file.mu_logical_predicates
  in
  let () = Debug_ocaml.end_csv_timing "logical predicates" in

  let () = Debug_ocaml.begin_csv_timing "resource predicates" in
  let@ () = 
    (* check and record resource predicate defs *)
    let@ () = 
      ListM.iterM (fun (name, def) -> add_resource_predicate name def)
        mu_file.mu_resource_predicates
    in
    Pp.progress_simple "checking specifications" "resource predicate welltypedness";
    let@ () = 
      ListM.iterM (fun (name,def) -> WellTyped.WRPD.welltyped def)
        mu_file.mu_resource_predicates
    in
    return ()
  in
  let () = Debug_ocaml.end_csv_timing "resource predicates" in


  let () = Debug_ocaml.begin_csv_timing "globals" in
  let@ () = 
    (* record globals *)
    (* TODO: check the expressions *)
    ListM.iterM (fun (sym, def) ->
        match def with
        | M_GlobalDef (lsym, (gbt, ct), _)
        | M_GlobalDecl (lsym, (gbt, ct)) ->
           let@ () = WellTyped.WBT.is_bt Loc.unknown gbt in
           let@ () = WellTyped.WCT.is_ct Loc.unknown ct in
           let bt = Loc in
           let@ () = add_l lsym bt in
           let@ () = add_a sym (bt, lsym) in
           let@ () = add_c (t_ (IT.good_pointer ~pointee_ct:ct (sym_ (lsym, bt)))) in
           return ()
      ) mu_file.mu_globs 
  in
  let () = Debug_ocaml.end_csv_timing "globals" in

  let@ () =
    PmapM.iterM
      (fun fsym (M_funinfo (loc, _attrs, ftyp, trusted, _has_proto)) ->
        (* let lc1 = t_ (ne_ (null_, sym_ (fsym, Loc))) in *)
        (* let lc2 = t_ (representable_ (Pointer Void, sym_ (fsym, Loc))) in *)
        (* let@ () = add_l fsym Loc in *)
        (* let@ () = add_cs [lc1; lc2] in *)
        add_fun_decl fsym (loc, ftyp, trusted)
      ) mu_file.mu_funinfo
  in

  let () = Debug_ocaml.begin_csv_timing "welltypedness" in
  let@ () =
    Pp.progress_simple "checking specifications" "function welltypedness";
    PmapM.iterM
      (fun fsym (M_funinfo (loc, _attrs, ftyp, _trusted, _has_proto)) ->
        match !only with
        | Some fname when not (String.equal fname (Sym.pp_string fsym)) ->
           return ()
        | _ ->
           let () = debug 2 (lazy (headline ("checking welltypedness of procedure " ^ Sym.pp_string fsym))) in
           let () = debug 2 (lazy (item "type" (AT.pp RT.pp ftyp))) in
           WellTyped.WFT.welltyped "global" loc ftyp
      ) mu_file.mu_funinfo
  in
  let () = Debug_ocaml.end_csv_timing "welltypedness" in

  let check_function =
    fun fsym fn ->
    let@ (loc, ftyp, trusted) = get_fun_decl Locations.unknown fsym in
    let () = Debug_ocaml.begin_csv_timing "functions" in
    let start = time_log_start "function" (CF.Pp_symbol.to_string fsym) in
    let@ () = match trusted, fn with
      | Trusted _, _ -> 
         return ()
      | Checked, M_Fun (rbt, args, body) ->
         check_function loc (Sym.pp_string fsym) args rbt body ftyp
      | Checked, M_Proc (loc', rbt, args, body, labels) ->
         check_procedure loc fsym args rbt body ftyp labels
      | _, (M_ProcDecl _ | M_BuiltinDecl _) -> (* TODO: ? *) 
         return ()
    in
    Debug_ocaml.end_csv_timing "functions";
    time_log_end start;
    return ()
  in

  let () = Debug_ocaml.begin_csv_timing "check stdlib" in
  let@ () = PmapM.iterM check_function mu_file.mu_stdlib in
  let () = Debug_ocaml.end_csv_timing "check stdlib" in
  let () = Debug_ocaml.begin_csv_timing "check functions" in
  let@ () = 
    let number_entries = List.length (Pmap.bindings_list mu_file.mu_funs) in
    let ping = Pp.progress "checking function" number_entries in
    PmapM.iterM (fun fsym fn ->
        match !only with
        | Some fname when not (String.equal fname (Sym.pp_string fsym)) ->
           return ()
        | _ ->
        let@ () = return (ping (Sym.pp_string fsym)) in
        let@ () = check_function fsym fn in
        return ()
      ) mu_file.mu_funs 
  in
  let () = Debug_ocaml.end_csv_timing "check functions" in


  let () = Debug_ocaml.end_csv_timing "total" in

  return ()





(* TODO: 
   - sequencing strength
   - rem_t vs rem_f
   - check globals with expressions
   - inline TODOs
 *)
