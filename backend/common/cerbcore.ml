open Cerb_frontend
open Global_ocaml

module Mem = Naive_memory


(* command-line options *)
let impl_file        = ref ""

let print_version    = ref false
let print_core       = ref false
let execute          = ref false
(* TODO: let execution_mode   = ref Core_run2.E.Exhaustive *)
let sb_graph         = ref false
let skip_core_tcheck = ref false (* TODO: this is temporary, until I fix the typechecker (...) *)
let regression_test  = ref false

let print_trace = ref false


(* command-line handler *)
let options = Arg.align [
  ("--impl",    Arg.Set_string impl_file          , "<name> Select an implementation definition");
  ("--debug",   Arg.Set_int Debug.debug_level, "       Set the debug noise level (default: 0 = nothing)");
  
  (* Core backend options *)
  ("--skip-core-tcheck", Arg.Set skip_core_tcheck,                                  "       Do not run the Core typechecker");
  ("--execute",          Arg.Set execute,                                           "       Execute the Core program");
(* TODO:   ("-r",                 Arg.Unit (fun () -> execution_mode := Core_run2.E.Random ), "       Randomly choose a single execution path");  *)
  ("--sb-graph",         Arg.Set sb_graph,                                          "       Generate dot graphs of the sb orders");
  
  (* printing options *)
  ("--version", Arg.Set print_version, "       Print the mercurial version id");
  ("--pcore",   Arg.Set print_core   , "       Pretty-print the Code generated program");
  ("--trace",   Arg.Set print_trace  , "       Print the execute trace at the end");

  (* Regression test *)
  ("--regression-test",   Arg.Set regression_test  , "       Runs the regression tests")
]
let usage = "Usage: cerbcore [OPTIONS]... [FILE]...\n"




(* some block functions used by the pipeline *)
let pass_through        f = Exception.fmap (fun v ->           f v        ; v)
let pass_through_test b f = Exception.fmap (fun v -> if b then f v else (); v)
let pass_message      msg = Exception.fmap (fun v -> Debug.print_success msg; v)
let return_none m         = Exception.bind0 m (fun _ -> Exception.return0 None)
let return_empty m        = Exception.bind0 m (fun _ -> Exception.return0 [])

let return_value m        = Exception.bind0 m (fun _ -> Exception.return0 [])


let catch_result m =
  match m with
  | Exception.Result [[(Undefined.Defined (Core.Econst (Mem.MV_integer (Symbolic.SYMBconst n)), _), _)]] ->
      exit (Nat_big_num.to_int n)
  | Exception.Result _ ->
     Debug.print_debug 2 "[Main.catch_result] returning a fake return code";
     exit 0
  | Exception.Exception msg ->
      print_endline (Colour.ansi_format [Colour.Red] (Pp_errors.to_string msg))


(* use this when calling a pretty printer *)
let run_pp =
    PPrint.ToChannel.pretty 40.0 80 Stdlib.stdout




let core_sym_counter = ref 0




(* load the Core standard library *)
let load_stdlib corelib_path =
  let fname = Filename.concat corelib_path "/std.core" in
  if not (Sys.file_exists fname) then
    error ("couldn't find the Core standard library file\n (looked at: `" ^ fname ^ "'.")
  else
    Debug.print_debug 5 ("reading Core stdlib from `" ^ fname ^ "'.");
    (* An preliminary instance of the Core parser *)
    let module Core_std_parser_base = struct
      include Core_parser.Make (struct
                                 let sym_counter = core_sym_counter
                                 let std = Pmap.empty compare
                               end)
      type token = Core_parser_util.token
      type result = Core_parser_util.result
    end in
    let module Core_std_parser =
      Parser_util.Make (Core_std_parser_base) (Lexer_util.Make (Core_lexer)) in
    (* TODO: yuck *)
    match Core_std_parser.parse (Input.file fname) with
      | Exception.Result (Core_parser_util.Rstd z) -> z
      | _ -> error "(TODO_MSG) found an error while parsing the Core stdlib."

let load_impl core_parse corelib_path =
    if !impl_file = "" then 
      error "expecting an implementation to be specified (using --impl <name>)."
    else
      let iname = Filename.concat corelib_path ("impls/" ^ !impl_file ^ ".impl") in
      if not (Sys.file_exists iname) then
        error ("couldn't find the implementation file\n (looked at: `" ^ iname ^ "'.")
      else
      (* TODO: yuck *)
        match core_parse (Input.file iname) with
          | Exception.Result (Core_parser_util.Rimpl z) -> z
          | Exception.Exception err -> error ("[Core parsing error: impl-file]" ^ Pp_errors.to_string err)


let pipeline stdlib impl core_parse file_name : Exhaustive_driver.execution_result =
  file_name
  |> Input.file
  |> core_parse
  |> Exception.fmap (function
       | Core_parser_util.Rfile (a_main, funs) ->
           (Symbol.Symbol (!core_sym_counter, None),
            { Core.main= a_main; Core.stdlib= stdlib; Core.impl= impl; Core.globs= [(* TODO *)];Core.funs= funs })
       | _ -> assert false)
  |> pass_message "1-4. Parsing completed!"
  |> pass_through_test !print_core (fun (_, f) -> run_pp (Pp_core.pp_file f))
(*
  |> pass_message "6. Enumerating indet orders:"
  |> Exception.rbind Core_indet.order
*)
  |> pass_message "7. Now running:"
  |> Exception.rbind
  (*    (Exception.mapM0
	 (fun (n,file) -> *)
           (fun (sym_supply, file) -> Exhaustive_driver.drive sym_supply file [] true)
(*         )
      ) *)


let run_test (run:string->Exhaustive_driver.execution_result) (test:Tests.test) = 
  let ex_result = run test.Tests.file_name in
  let test_result = Tests.compare_results test.Tests.expected_result ex_result in
  match test_result with
  | Exception.Result _      -> 
      print_endline (Colour.ansi_format [Colour.Green] 
                                        ("Test succeeded (" ^ test.Tests.file_name ^ ")"))
  | Exception.Exception msg -> 
      print_endline (Colour.ansi_format [Colour.Red]   
                                        ("Test failed    (" ^ test.Tests.file_name ^ "): " ^ msg))

(* the entry point *)
let () =
  (* this is for the random execution selection mode *)
  Random.self_init ();
  
  (* TODO: yuck *)
  let file = ref "" in
  Arg.parse options (fun z -> file := z) usage;
  
  if !print_version then print_endline "cerbcore (hg version: <<HG-IDENTITY>>)"; (* this is "sed-out" by the Makefile *)
  
  
  let corelib_path =
    try
      Sys.getenv "CORELIB_PATH"
    with Not_found ->
      error "expecting the environment variable CORELIB_PATH set to point to the location of std.core." in
  
  (* Looking for and parsing the core standard library *)
  let stdlib = load_stdlib corelib_path in
  Debug.print_success "0.1. - Core standard library loaded.";
  
  (* An instance of the Core parser knowing about the stdlib functions we just parsed *)
  let module Core_parser_base = struct
    include Core_parser.Make (struct
        let sym_counter = core_sym_counter
        let std = List.fold_left (fun acc ((Symbol.Symbol (_, Some fname)) as fsym, _) ->
          Pmap.add fname fsym acc
        ) (Pmap.empty compare) (Pmap.bindings_list stdlib)
      end)
    type token = Core_parser_util.token
    type result = Core_parser_util.result
  end in
  let module Core_parser =
    Parser_util.Make (Core_parser_base) (Lexer_util.Make (Core_lexer)) in
  
  (* Looking for and parsing the implementation file *)
  let impl = load_impl Core_parser.parse corelib_path in
  Debug.print_success "0.2. - Implementation file loaded.";
  let run = pipeline stdlib impl Core_parser.parse in
  (if !regression_test then
     let tests = Tests.get_tests in
     List.iter (run_test run) tests
   else  
     let result = run !file in
     ()
  )
