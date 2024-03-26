open Builtins
module CF=Cerb_frontend
module CB=Cerb_backend
open CB.Pipeline
open Setup
open Executable_spec_utils

module A=CF.AilSyntax 


let return = CF.Exception.except_return
let (let@) = CF.Exception.except_bind



type core_file = (unit,unit) CF.Core.generic_file
type mu_file = unit Mucore.mu_file


type file =
  | CORE of core_file
  | MUCORE of mu_file



let print_file filename file =
  match file with
  | CORE file ->
     Pp.print_file (filename ^ ".core") (CF.Pp_core.All.pp_file file);
  | MUCORE file ->
     Pp.print_file (filename ^ ".mucore")
       (Pp_mucore.Basic.pp_file None file);


module Log : sig
  val print_log_file : (string * file) -> unit
end = struct
  let print_count = ref 0
  let print_log_file (filename, file) =
    if !Cerb_debug.debug_level > 0 then
      begin
        Cerb_colour.do_colour := false;
        let count = !print_count in
        let file_path =
          (Filename.get_temp_dir_name ()) ^
            Filename.dir_sep ^
            (string_of_int count ^ "__" ^ filename)
        in
        print_file file_path file;
        print_count := 1 + !print_count;
        Cerb_colour.do_colour := true;
      end
end

open Log






let frontend incl_dirs incl_files astprints do_peval filename state_file =
  let open CF in
  Cerb_global.set_cerb_conf "Cn" false Random false Basic false false false false false;
  Ocaml_implementation.set Ocaml_implementation.HafniumImpl.impl;
  Switches.set ["inner_arg_temps"; "at_magic_comments"; "warn_mismatched_magic_comments"];
  Core_peval.config_unfold_stdlib := Sym.has_id_with Setup.unfold_stdlib_name;
  let@ stdlib = load_core_stdlib () in
  let@ impl = load_core_impl stdlib impl_name in
  let conf = Setup.conf incl_dirs incl_files astprints in
  let@ (_, ail_prog_opt, prog0) = c_frontend_and_elaboration ~cnnames:cn_builtin_fun_names (conf, io) (stdlib, impl) ~filename in
  let@ () =  begin
    if conf.typecheck_core then
      let@ _ = Core_typing.typecheck_program prog0 in return ()
    else
      return ()
  end in
  let markers_env, (_, ail_prog) = Option.get ail_prog_opt in
  Tags.set_tagDefs prog0.Core.tagDefs;
  let prog1 = Remove_unspecs.rewrite_file prog0 in
  let prog2 = if do_peval then Core_peval.rewrite_file prog1 else prog1 in
  let prog3 = Milicore.core_to_micore__file Locations.update prog2 in
  let prog4 = Milicore_label_inline.rewrite_file prog3 in
  let statement_locs = CStatements.search ail_prog in
  print_log_file ("original", CORE prog0);
  print_log_file ("without_unspec", CORE prog1);
  print_log_file ("after_peval", CORE prog2);
  return (prog4, (markers_env, ail_prog), statement_locs)


let handle_frontend_error = function
  | CF.Exception.Exception ((_, CF.Errors.CORE_TYPING _) as err) ->
     prerr_string (CF.Pp_errors.to_string err);
     prerr_endline @@ Cerb_colour.(ansi_format ~err:true [Bold; Red] "error: ") ^
       "this is likely a bug in the Core elaboration.";
     exit 2
  | CF.Exception.Exception err ->
     prerr_endline (CF.Pp_errors.to_string err); exit 2
  | CF.Exception.Result result ->
     result




let opt_comma_split = function
  | None -> []
  | Some str -> String.split_on_char ',' str

let check_input_file filename =
  if not (Sys.file_exists filename) then
    CF.Pp_errors.fatal ("file \""^filename^"\" does not exist")
  else if not (String.equal (Filename.extension filename) ".c") then
    CF.Pp_errors.fatal ("file \""^filename^"\" has wrong file extension")



let main 
      filename 
      incl_dirs
      incl_files
      loc_pp
      debug_level
      print_level
      print_sym_nums
      slow_threshold
      no_timestamps
      json
      state_file
      diag
      lemmata
      only
      skip
      csv_times
      log_times
      random_seed
      solver_logging
      output_decorated_dir
      output_decorated
      astprints
      expect_failure
      use_vip
      no_use_ity
      use_peval
      batch
  =
  if json then begin
      if debug_level > 0 then
        CF.Pp_errors.fatal ("debug level must be 0 for json output");
      if print_level > 0 then
        CF.Pp_errors.fatal ("print level must be 0 for json output");
    end;
  begin (*flags *)
    Cerb_debug.debug_level := debug_level;
    Pp.loc_pp := loc_pp;
    Pp.print_level := print_level;
    CF.Pp_symbol.pp_cn_sym_nums := print_sym_nums;
    Pp.print_timestamps := not no_timestamps;
    Option.iter (fun t -> Solver.set_slow_threshold t) slow_threshold;
    Solver.random_seed := random_seed;
    Solver.log_to_temp := solver_logging;
    Check.skip_and_only := (opt_comma_split skip, opt_comma_split only);
  IndexTerms.use_vip := use_vip;
    Check.batch := batch;
    Diagnostics.diag_string := diag;
    WellTyped.use_ity := not no_use_ity
  end;
  check_input_file filename;
  let (prog4, (markers_env, ail_prog), statement_locs) =
    handle_frontend_error
      (frontend incl_dirs incl_files astprints use_peval filename state_file)
  in
  Cerb_debug.maybe_open_csv_timing_file ();
  Pp.maybe_open_times_channel
    (match (csv_times, log_times) with
     | (Some times, _) -> Some (times, "csv")
     | (_, Some times) -> Some (times, "log")
     | _ -> None);
  try
      let result =
        let open Resultat in
         let@ prog5 = Core_to_mucore.normalise_file (markers_env, ail_prog) prog4 in
         let (instrumentation, symbol_table) = Core_to_mucore.collect_instrumentation prog5 in
         print_log_file ("mucore", MUCORE prog5);
         Cerb_colour.do_colour := false; (* Needed for executable spec printing *)
         begin match output_decorated with
         | None -> ()
         | Some output_filename ->
            let prefix = match output_decorated_dir with | Some dir_name -> dir_name | None -> "" in
            let oc = Stdlib.open_out (prefix ^ output_filename) in
            (* let dir_name = String.split_on_char '/' output_filename in *)
            (* let rec take_n n list = match list with  *)
              (* | [] -> [] *)
              (* | x :: xs -> if n == 1 then [x] else x :: (take_n (n - 1) xs) *)
            (* in *)
            (* let cn_prefix_list = take_n ((List.length dir_name) - 1) dir_name in *)
            (* let cn_prefix = if (List.length dir_name != 0) then String.concat "/" cn_prefix_list  ^ "/" else "" in *)
            let cn_oc = Stdlib.open_out (prefix ^ "cn.c") in
            let executable_spec = Executable_spec_internal.generate_c_specs_internal instrumentation symbol_table statement_locs ail_prog prog5 in
            let c_datatypes = Executable_spec_internal.generate_c_datatypes ail_prog in
            let (c_function_defs, locs_and_c_function_decls, c_records) = Executable_spec_internal.generate_c_functions_internal ail_prog prog5.mu_logical_predicates in
            let (c_predicate_defs, c_predicate_decls, c_records', ownership_ctypes) = Executable_spec_internal.generate_c_predicates_internal ail_prog prog5.mu_resource_predicates executable_spec.ownership_ctypes in
            let (conversion_function_defs, conversion_function_decls) = Executable_spec_internal.generate_conversion_and_equality_functions ail_prog in 
            let (ownership_function_defs, ownership_function_decls) = Executable_spec_internal.generate_ownership_functions ownership_ctypes ail_prog in
            let c_structs = Executable_spec_internal.print_c_structs ail_prog.tag_definitions in
            let cn_converted_structs = Executable_spec_internal.generate_cn_versions_of_structs ail_prog.tag_definitions in 

            (* TODO: Remove - hacky *)
            let cn_utils_header_pair = ("../../executable-spec/cn_utils.c", false) in
            let cn_utils_header = generate_include_header cn_utils_header_pair in
            
            (* TODO: Topological sort *)
            Stdlib.output_string cn_oc cn_utils_header;
            Stdlib.output_string cn_oc c_structs;
            Stdlib.output_string cn_oc cn_converted_structs;
            Stdlib.output_string cn_oc "\n/* CN DATATYPES */\n\n";
            Stdlib.output_string cn_oc (String.concat "\n" (List.map snd c_datatypes));
            Stdlib.output_string cn_oc c_function_defs;
            Stdlib.output_string cn_oc c_predicate_defs;
            Stdlib.output_string cn_oc conversion_function_defs;
            Stdlib.output_string cn_oc ownership_function_defs;

            let incls = [("assert.h", true); ("stdlib.h", true); ("stdbool.h", true); ("math.h", true); cn_utils_header_pair;] in
            let headers = List.map generate_include_header incls in
            Stdlib.output_string oc (List.fold_left (^) "" headers);
            Stdlib.output_string oc "\n";


            let struct_injs_with_filenames = Executable_spec_internal.generate_struct_injs ail_prog in 

            let filter_injs_by_filename struct_inj_pairs fn = 
              List.filter (fun (loc, inj) -> match Cerb_location.get_filename loc with | Some name -> (String.equal name fn) | None -> false) struct_inj_pairs
            in
            let source_file_struct_injs_with_syms = filter_injs_by_filename struct_injs_with_filenames filename in
            let source_file_struct_injs = List.map (fun (loc, (sym, strs)) -> (loc, strs)) source_file_struct_injs_with_syms in

            let included_filenames = List.map (fun (loc, inj) -> Cerb_location.get_filename loc) struct_injs_with_filenames in 
            let rec open_auxilliary_files included_filenames already_opened_list = match included_filenames with 
              | [] -> []
              | fn :: fns -> 
                (match fn with 
                  | Some fn' -> 
                    if String.equal fn' filename || List.mem String.equal fn' already_opened_list then [] else 
                    let fn_list = String.split_on_char '/' fn' in
                    let output_fn = List.nth fn_list (List.length fn_list - 1) in 
                    let output_fn_with_prefix = prefix ^ output_fn in
                    if Sys.file_exists output_fn_with_prefix then 
                      (Printf.printf "Error in opening file %s as it already exists\n" output_fn_with_prefix;
                      open_auxilliary_files fns (fn' :: already_opened_list))
                    else
                      (Printf.printf "REACHED FILENAME: %s\n" output_fn_with_prefix;
                      let output_channel = Stdlib.open_out output_fn_with_prefix in
                      (fn', output_channel) :: open_auxilliary_files fns (fn' :: already_opened_list))
                  | None -> [])
            in 


            let fns_and_ocs = open_auxilliary_files included_filenames [] in 
            let rec inject_structs_in_header_files = function 
              | [] -> ()
              | (fn', oc') :: xs -> 
                let header_file_injs_with_syms = filter_injs_by_filename struct_injs_with_filenames fn' in
                let header_file_injs = List.map (fun (loc, (sym, strs)) -> (loc, strs)) header_file_injs_with_syms in
                Stdlib.output_string oc' cn_utils_header;
                begin match
                  Source_injection.(output_injections oc'
                    { filename=fn'; sigm= ail_prog
                    ; pre_post=[]
                    ; in_stmt=header_file_injs}
                  )
                with
                | Ok () ->
                    ()
                | Error str ->
                    (* TODO(Christopher/Rini): maybe lift this error to the exception monad? *)
                    prerr_endline str
                end;
                Stdlib.close_out oc';
               inject_structs_in_header_files xs
            in

            let c_datatypes = List.map (fun (loc, strs) -> (loc, [strs])) c_datatypes in

            begin match
              Source_injection.(output_injections oc
                { filename; sigm= ail_prog
                ; pre_post=executable_spec.pre_post
                ; in_stmt=(executable_spec.in_stmt @ c_datatypes @ locs_and_c_function_decls @ source_file_struct_injs)}
              )
            with
            | Ok () ->
                ()
            | Error str ->
                (* TODO(Christopher/Rini): maybe lift this error to the exception monad? *)
                prerr_endline str
            end;
            inject_structs_in_header_files fns_and_ocs;

         end;

        match output_decorated with 
          | None -> 
            let@ res = Typing.run Context.empty (Check.check prog5 statement_locs lemmata) in 
            return res
          | Some _ -> 
            return ()

       in
       Pp.maybe_close_times_channel ();
       match result with
       | Ok () -> exit (if expect_failure then 1 else 0)
       | Error e ->
         if json then TypeErrors.report_json ?state_file e else TypeErrors.report ?state_file e;
         exit (if expect_failure then 0 else 1)
 with
     | exc ->
        Pp.maybe_close_times_channel ();
        Cerb_debug.maybe_close_csv_timing_file_no_err ();
        Printexc.raise_with_backtrace exc (Printexc.get_raw_backtrace ());


open Cmdliner


(* some of these stolen from backend/driver *)
let file =
  let doc = "Source C file" in
  Arg.(required & pos ~rev:true 0 (some string) None & info [] ~docv:"FILE" ~doc)


let incl_dirs =
  let doc = "Add the specified directory to the search path for the\
             C preprocessor." in
  Arg.(value & opt_all string [] & info ["I"; "include-directory"]
         ~docv:"DIR" ~doc)

let incl_files =
  let doc = "Adds  an  implicit  #include into the predefines buffer which is \
             read before the source file is preprocessed." in
  Arg.(value & opt_all string [] & info ["include"] ~doc)

let loc_pp =
  let doc = "Print pointer values as hexadecimal or as decimal values (hex | dec)" in
  Arg.(value & opt (enum ["hex", Pp.Hex; "dec", Pp.Dec]) !Pp.loc_pp &
       info ["locs"] ~docv:"HEX" ~doc)

let debug_level =
  let doc = "Set the debug message level for cerberus to $(docv) (should range over [0-3])." in
  Arg.(value & opt int 0 & info ["d"; "debug"] ~docv:"N" ~doc)

let print_level =
  let doc = "Set the debug message level for the type system to $(docv) (should range over [0-15])." in
  Arg.(value & opt int 0 & info ["p"; "print-level"] ~docv:"N" ~doc)

let print_sym_nums =
  let doc = "Print numeric IDs of Cerberus symbols (variable names)." in
  Arg.(value & flag & info ["n"; "print-sym-nums"] ~doc)

let batch =
  let doc = "Type check functions in batch/do not stop on first type error (unless `only` is used)" in
  Arg.(value & flag & info ["batch"] ~doc)


let slow_threshold =
  let doc = "Set the time threshold (in seconds) for logging to slow_smt.txt temp file." in
  Arg.(value & opt (some float) None & info ["slow-smt"] ~docv:"TIMEOUT" ~doc)

let no_timestamps =
  let doc = "Disable timestamps in print-level debug messages"
 in
  Arg.(value & flag & info ["no_timestamps"] ~doc)


let json =
  let doc = "output in json format" in
  Arg.(value & flag & info["json"] ~doc)


let state_file =
  let doc = "file in which to output the state" in
  Arg.(value & opt (some string) None & info ["state-file"] ~docv:"FILE" ~doc)

let diag =
  let doc = "explore branching diagnostics with key string" in
  Arg.(value & opt (some string) None & info ["diag"] ~doc)

let lemmata =
  let doc = "lemmata generation mode (target filename)" in
  Arg.(value & opt (some string) None & info ["lemmata"] ~docv:"FILE" ~doc)

let csv_times =
  let doc = "file in which to output csv timing information" in
  Arg.(value & opt (some string) None & info ["times"] ~docv:"FILE" ~doc)

let log_times =
  let doc = "file in which to output hierarchical timing information" in
  Arg.(value & opt (some string) None & info ["log_times"] ~docv:"FILE" ~doc)

let random_seed =
  let doc = "Set the SMT solver random seed (default 1)." in
  Arg.(value & opt int 0 & info ["r"; "random-seed"] ~docv:"I" ~doc)

let solver_logging =
  let doc = "Have Z3 log in SMT2 format to a file in a temporary directory." in
  Arg.(value & flag & info ["solver-logging"] ~doc)

let only =
  let doc = "only type-check this function (or comma-separated names)" in
  Arg.(value & opt (some string) None & info ["only"] ~doc)

let skip =
  let doc = "skip type-checking of this function (or comma-separated names)" in
  Arg.(value & opt (some string) None & info ["skip"] ~doc)


let output_decorated_dir =
  let doc = "output a version of the translation unit decorated with C runtime translations of the CN annotations to the provided directory" in
  Arg.(value & opt (some string) None & info ["output_decorated_dir"] ~docv:"FILE" ~doc)
  

let output_decorated =
  let doc = "output a version of the translation unit decorated with C runtime translations of the CN annotations" in
  Arg.(value & opt (some string) None & info ["output_decorated"] ~docv:"FILE" ~doc)

(* copy-pasting from backend/driver/main.ml *)
let astprints =
  let doc = "Pretty print the intermediate syntax tree for the listed languages \
             (ranging over {cabs, ail, core, types})." in
  Arg.(value & opt (list (enum [("cabs", Cabs); ("ail", Ail); ("core", Core); ("types", Types)])) [] &
       info ["ast"] ~docv:"LANG1,..." ~doc)

let expect_failure =
  let doc = "invert return value to 1 if type checks pass and 0 on failure" in
  Arg.(value & flag & info["expect-failure"] ~doc)

(* TODO remove this when VIP impl complete *)
let use_vip =
  let doc = "use experimental VIP rules" in
  Arg.(value & flag & info["vip"] ~doc)

let no_use_ity =
  let doc = "(this switch should go away) in WellTyped.BaseTyping, do not use integer type annotations placed by the Core elaboration" in
  Arg.(value & flag & info["no-use-ity"] ~doc)

let use_peval =
  let doc = "(this switch should go away) run the Core partial evaluation phase" in
  Arg.(value & flag & info["use-peval"] ~doc)




let () =
  let open Term in
  let check_t =
    const main $
      file $
      incl_dirs $
      incl_files $
      loc_pp $
      debug_level $
      print_level $
      print_sym_nums $
      slow_threshold $
      no_timestamps $
      json $
      state_file $
      diag $
      lemmata $
      only $
      skip $
      csv_times $
      log_times $
      random_seed $
      solver_logging $
      output_decorated_dir $
      output_decorated $
      astprints $
      expect_failure $
      use_vip $
      no_use_ity $
      use_peval $
      batch
  in
  Stdlib.exit @@ Cmd.(eval (v (info "cn") check_t))
