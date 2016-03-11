open Global_ocaml
open Core

open Pp_run

module ND  = Nondeterminism
module SEU = State_exception_undefined

let (>>=) = SEU.bind9


(*
let drive file args =
  let main_body = 
    match Pmap.lookup file.main file.funs with
      | Some (retTy, _, expr_main) ->
          expr_main
      |  _ ->
          Pervasives.output_string stderr "ERROR: couldn't find the Core main function\n";
          exit (-1) in
  
  let file = Core_run.convert_file file in
  let (Nondeterminism.ND vs) = Driver.drive (!!cerb_conf.concurrency) file args in
  
  Debug.print_debug 1 (Printf.sprintf "Number of executions: %d\n" (List.length vs));
  
  let isActive = function
    | ND.Active _ ->
        true
    | _ ->
        false in
  
  if List.length (List.filter isActive vs) = 0 then
    Debug.print_debug 0 "FOUND NO VALID EXECUTION";
  
  let ky = ref [] in
  let str_v = ref "" in
  List.iteri (fun n exec ->
    
    match exec with
      | ND.Active (log, constraints, (stdout, (is_blocked, preEx, value))) ->
          str_v := String_core.string_of_expr value;
          if not (List.mem str_v !ky) && not is_blocked then (
            Debug.print_debug 2 (
              Printf.sprintf "Execution #%d under constraints:\n=====\n%s\n=====\nBEGIN LOG\n%s\nEND LOG"
                n (pp_constraints constraints) (String.concat "\n" (Dlist.toList log)) ^ "\n" ^
              (Pp_cmm.dot_of_pre_execution preEx !str_v (pp_constraints constraints))
            );
            print_string stdout;
          ) else
            Debug.print_debug 2 (
              "SKIPPING: " ^
              if is_blocked then "(blocked)" else "" ^
              "eqs= " ^ pp_constraints constraints
            );
          
          ky := str_v :: !ky
      
      | ND.Killed (ND.Undef0 ubs, _, _) ->
          print_endline (
            Colour.(ansi_format [Red] (Printf.sprintf "UNDEFINED BEHAVIOUR:\n%s\n"
              (String.concat "\n" (List.map (fun ub -> Undefined.pretty_string_of_undefined_behaviour ub) ubs))
            ))
          )
      
      | ND.Killed (ND.Error0 str, _, _) ->
          print_endline (Colour.(ansi_format [Red] ("IMPL-DEFINED STATIC ERROR: " ^ str)))
      
      | ND.Killed (ND.Other reason, log, constraints) ->
          Debug.print_debug 3 (
            Printf.sprintf "Execution #%d (KILLED: %s) under constraints:\n=====\n%s\n=====\nBEGIN LOG\n%s\nEND LOG"
              n reason (pp_constraints constraints) (String.concat "\n" (Dlist.toList log))
          )
  ) vs;
  !str_v
*)

let isActive = function
  | (_, ND.Active _) ->
      true
  | _ ->
      false



type execution_result = (Core.pexpr list, Errors.t6) Exception.t3

let drive sym_supply file args with_concurrency : execution_result =
(*
  let main_body = 
    match Pmap.lookup file.main file.funs with
      | Some (Core.Proc (_, _, e)) ->
          e
      | Some (Core.Fun (_, _, pe)) ->
          Core.Eret pe
      |  _ ->
          Pervasives.output_string stderr "ERROR: couldn't find the Core main function\n";
          exit (-1) in
*)
  
  let file = Core_run.convert_file file in
  let (Nondeterminism.ND vs) = Driver.drive with_concurrency sym_supply file args in 
  (* let vs = [] in
  let _ = Driver.followConcurrencyTrace sym_supply file args [1;3;4;0;2;5] in *)
  
  let n_actives = List.length (List.filter isActive vs) in
  let n_execs   = List.length vs in
  
  Debug.print_debug 1 (Printf.sprintf "Number of executions: %d actives (%d killed)\n" n_actives (n_execs - n_actives));
  
  if n_actives = 0 then begin
    print_endline Colour.(ansi_format [Red]
      (Printf.sprintf "FOUND NO ACTIVE EXECUTION (with %d killed)\n" (n_execs - n_actives))
    );
    List.iteri (fun n (_, ND.Killed (reason, log, constraints)) ->
      let reason_str = match reason with
        | ND.Undef0 (loc, ubs) ->
            "undefined behaviour[" ^ Pp_errors.location_to_string loc ^ "]: " ^ Lem_show.stringFromList Undefined.string_of_undefined_behaviour ubs
        | ND.Error0 (loc , str) ->
            "static error[" ^ Pp_errors.location_to_string loc ^ "]: " ^ str
        | ND.Other str ->
            str in
      print_endline Colour.(ansi_format [Red] 
        (Printf.sprintf "Execution #%d (KILLED: %s) under constraints:\n=====\n%s\n=====\nBEGIN LOG\n%s\nEND LOG"
              n reason_str (Pp_cmm.pp_constraints constraints) (String.concat "\n" (List.rev (Dlist.toList log))))
      )
    ) vs
  end;
  
  let ky  = ref [] in
  let ret = ref [] in
  
  List.iteri (fun n (_, exec) ->
    match exec with
      | ND.Active (log, constraints, (stdout, (is_blocked, conc_st, pe), (dr_steps, coreRun_steps))) ->
          let str_v = String_core.string_of_pexpr
              begin
                match pe with
                  | Pexpr (ty, Core.PEval (Core.Vobject (Core.OVinteger ival))) ->
                      Pexpr (ty, Core.PEval ((match (Mem_aux.integerFromIntegerValue ival) with
                      | None -> Core.Vobject (Core.OVinteger ival) | Some n -> Core.Vobject (Core.OVinteger (Mem.integer_ival0 n))) ))
                  | _ ->
                      pe
              end in
          let str_v_ = str_v ^ stdout in
          if not (List.mem str_v_ !ky) then (
            if Debug.get_debug_level () = 0 then
              (print_string stdout; flush_all());
            
            Debug.print_debug 1 (
              Printf.sprintf "Execution #%d (value = %s) under constraints:\n=====\n%s\n=====\n" n str_v (Pp_cmm.pp_constraints constraints) ^
              Printf.sprintf "BEGIN stdout\n%s\nEND stdout\n" stdout ^
              Printf.sprintf "driver steps: %d, core steps: %d\n" dr_steps coreRun_steps (* ^
              Printf.sprintf "BEGIN LOG\n%s\nEND LOG\n" (String.concat "\n" (List.rev (Dlist.toList log))) *)
            );
          );
          if not (List.mem str_v_ !ky) && not is_blocked then (
            if with_concurrency then
              Debug.print_debug 1 (Pp_cmm.dot_of_exeState conc_st str_v (Pp_cmm.pp_constraints constraints));
(*            print_string stdout; *)
            
            ky := str_v_ :: !ky;
            ret := pe :: !ret;
        ) else
          Debug.print_debug 4 (
            "SKIPPING: " ^ if is_blocked then "(blocked)" else "" ^
            "eqs= " ^ Pp_cmm.pp_constraints constraints
          );

      | ND.Killed (ND.Undef0 (loc, ubs), _, _) ->
          let str_v = Pp_errors.location_to_string loc ^
            (String.concat "\n" (List.map (fun ub -> Undefined.pretty_string_of_undefined_behaviour ub) ubs)) in
          
          if not (List.mem str_v !ky) then (
            print_endline (
              Colour.(ansi_format [Red] ("UNDEFINED BEHAVIOUR[" ^ Pp_errors.location_to_string loc ^ "]:\n" ^
                (String.concat "\n" (List.map (fun ub -> Undefined.pretty_string_of_undefined_behaviour ub) ubs))
              ))
           );
            ky := str_v :: !ky;
          ) else
            ()
      
      | ND.Killed (ND.Error0 (loc, str), _, _) ->
          print_endline (Colour.(ansi_format [Red] ("IMPL-DEFINED STATIC ERROR[" ^ Pp_errors.location_to_string loc ^ "]: " ^ str)))
      
      | ND.Killed (ND.Other reason, log, constraints) ->
          Debug.print_debug 5 (
            Printf.sprintf "Execution #%d (KILLED: %s) under constraints:\n=====\n%s\n=====\nBEGIN LOG\n%s\nEND LOG"
              n reason (Pp_cmm.pp_constraints constraints) (String.concat "\n" (List.rev (Dlist.toList log)))
          )
  ) vs;
  Exception.return2 !ret
