open Builtins
module CF=Cerb_frontend
module CB=Cerb_backend
open CB.Pipeline
open Setup


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






let frontend incl_dirs incl_files astprints filename state_file =
  let open CF in
  Cerb_global.set_cerb_conf "Cn" false Random false Basic false false false false;
  (* FIXME: make this a global config thing rather than poking state. *)
  C_lexer.set_magic_comment_mode (C_lexer.(Magic_At true));
  Ocaml_implementation.set Ocaml_implementation.HafniumImpl.impl;
  Switches.set ["inner_arg_temps"];
  let@ stdlib = load_core_stdlib () in
  let@ impl = load_core_impl stdlib impl_name in
  let conf = Setup.conf incl_dirs incl_files astprints in
  let@ (_, ail_prog_opt, prog0) = c_frontend_and_elaboration ~cnnames:cn_builtin_fun_names (conf, io) (stdlib, impl) ~filename in
  let markers_env, (_, ail_prog) = Option.get ail_prog_opt in
  Tags.set_tagDefs prog0.Core.tagDefs;
  let prog1 = Remove_unspecs.rewrite_file prog0 in
  let prog2 = Core_peval.rewrite_file prog1 in
  let prog3 = Milicore.core_to_micore__file Locations.update prog2 in
  let prog4 = Milicore_label_inline.rewrite_file prog3 in
  let statement_locs = CStatements.search ail_prog in
  print_log_file ("original", CORE prog0);
  print_log_file ("without_unspec", CORE prog1);
  print_log_file ("after_peval", CORE prog2);
  return (prog4, (markers_env, ail_prog), statement_locs)


let handle_frontend_error = function
  | CF.Exception.Exception err ->
     prerr_endline (CF.Pp_errors.to_string err); exit 2
  | CF.Exception.Result result ->
     result





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
      csv_times
      log_times
      random_seed
      solver_logging
      output_decorated
      astprints
      expect_failure
  =
  if json then begin
      if debug_level > 0 then
        CF.Pp_errors.fatal ("debug level must be 0 for json output");
      if print_level > 0 then
        CF.Pp_errors.fatal ("print level must be 0 for json output");
    end;
  Cerb_debug.debug_level := debug_level;
  Pp.loc_pp := loc_pp;
  Pp.print_level := print_level;
  CF.Pp_symbol.pp_cn_sym_nums := print_sym_nums;
  Pp.print_timestamps := not no_timestamps;
  Option.iter (fun t -> Solver.set_slow_threshold t) slow_threshold;
  Solver.random_seed := random_seed;
  Solver.log_to_temp := solver_logging;
  Check.only := only;
  Diagnostics.diag_string := diag;
  check_input_file filename;
  let (prog4, (markers_env, ail_prog), statement_locs) = 
    handle_frontend_error 
      (frontend incl_dirs incl_files astprints filename state_file)
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
         (* let instrumentation = Core_to_mucore.collect_instrumentation prog5 in *)
         print_log_file ("mucore", MUCORE prog5);
         let@ res = Typing.run Context.empty (Check.check prog5 statement_locs lemmata) in
         begin match output_decorated with
         | None -> ()
         | Some output_filename ->
            let oc = Stdlib.open_out output_filename in
            (* TODO(Rini): example for how to use Source_injection.get_magics_of_statement *)
            (* List.iter (fun (_, (_, _, _, _, stmt)) ->
              List.iteri(fun i xs ->
                List.iteri (fun j (loc, str) ->
                  Printf.fprintf stderr "[%d] [%d] ==> %s -- '%s'\n"
                  i j (Cerb_location.simple_location loc) (String.escaped str)
                ) xs
              ) (Source_injection.get_magics_of_statement stmt)
            ) ail_prog.function_definitions; *)
            begin match
              Source_injection.(output_injections oc
                { filename; sigm= ail_prog
                ; pre_post=[(*TODO(Rini): add here the pprints of functions pre/post conditions*)]
                ; in_stmt=[(*TODO(Rini): add here the pprints of annotations preceding statements *)] }
              )
            with
            | Ok () ->
                ()
            | Error str ->
                (* TODO(Christopher/Rini): maybe lift this error to the exception monad? *)
                prerr_endline str
            end
         end;
         return res
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
  let doc = "only type-check this function" in
  Arg.(value & opt (some string) None & info ["only"] ~doc)

(* TODO(Christopher/Rini): I'm adding a tentative cli option, rename/change it to whatever you prefer *)
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
      csv_times $
      log_times $
      random_seed $
      solver_logging $
      output_decorated $
      astprints $
      expect_failure
  in
  Stdlib.exit @@ Cmd.(eval (v (info "cn") check_t))
