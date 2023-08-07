open Cerb_frontend
open Cerb_backend
open Pipeline

let (>>=) = Exception.except_bind
let _return = Exception.except_return

let io = Pipeline.default_io_helpers

let impl_name = "gcc_4.9.0_x86_64-apple-darwin10.8.0"

let frontend cpp_str filename =
  let conf = {
      debug_level= 0
    ; pprints= []
    ; astprints= []
    ; ppflags= []
    ; typecheck_core= false
    ; rewrite_core= false
    ; sequentialise_core= false
    ; cpp_cmd= cpp_str
    ; cpp_stderr= true
  } in
  Cerb_global.(set_cerb_conf "Playground" false Random false Basic false false false false);
  load_core_stdlib ()                                  >>= fun stdlib ->
  load_core_impl stdlib impl_name                      >>= fun impl   ->
  c_frontend_and_elaboration (conf, io) (stdlib, impl) ~filename


let cpp_str =
    "cc -std=c11 -E -C -Werror -nostdinc -undef -D__cerb__"
  ^ " -I/Users/catzilla/rems-project/cerberus-private/runtime/libc/include"
  ^ " -I/Users/catzilla/github/hafnium/inc"
  ^ " -I/Users/catzilla/github/hafnium/inc/vmapi"
  ^ " -I/Users/catzilla/github/hafnium/src/arch/aarch64/inc"
  ^ " -DDEBUG"
  ^ " -DMAX_CPUS=4"
  ^ " -DMAX_VMS=2"
  ^ " -DHEAP_PAGES=10"


[@@@warning "-unused-value-declaration"]
let playground_core filename =
  let frontend cpp_str filename =
    let conf = {
        debug_level= 0
      ; pprints= []
      ; astprints= []
      ; ppflags= []
      ; typecheck_core= false
      ; rewrite_core= false
      ; sequentialise_core= false
      ; cpp_cmd= cpp_str
      ; cpp_stderr= true
    } in
    Cerb_global.(set_cerb_conf "Playground" false Random false Basic false false false false);
    load_core_stdlib ()                                  >>= fun stdlib ->
    load_core_impl stdlib impl_name                      >>= fun impl   ->
    core_frontend (conf, io) (stdlib, impl) ~filename in
  match frontend cpp_str filename with
    | Exception.Exception err ->
        prerr_endline (Pp_errors.to_string err)
    | Exception.Result file ->
        begin match file.Core.main with
          | None ->
              assert false
          | Some sym ->
              begin match Pmap.lookup sym file.funs with
                | Some (Core.Proc (_, _, _, _, e)) ->
(*
                    print_endline "===== BEFORE =====";
                    PPrint.ToChannel.pretty 1.0 80 Stdlib.stdout 
                      (Pp_core.Basic.pp_pexpr pe);
                    print_endline "\n===== AFTER =====";
                    Core_peval.foo (fun z -> PPrint.ToChannel.pretty 1.0 80 Stdlib.stdout z) pe
*)
                    let rec loop e =
                      print_endline "===== BEFORE =====";
                      PPrint.ToChannel.pretty 1.0 80 Stdlib.stdout 
                        (Pp_core.Basic.pp_expr e);
                      flush_all ();
                      let e' = Core_peval.step_peval_expr file e in
                      print_endline "\n===== AFTER =====";
                      PPrint.ToChannel.pretty 1.0 80 Stdlib.stdout 
                        (Pp_core.Basic.pp_expr e');
                      flush_all ();
                      Scanf.scanf "%s\n" (fun _ ->
                        loop e'
                      )
                    in loop e

                | _ ->
                    assert false
              end
        end


let playground filename =
  match frontend cpp_str filename with
    | Exception.Exception err ->
        prerr_endline (Pp_errors.to_string err)
    | Exception.Result (_, _, file) ->
        begin match file.Core.main with
          | None ->
              assert false
          | Some sym ->
              Tags.set_tagDefs file.tagDefs;
              begin match Pmap.lookup sym file.funs with
                | Some (Core.Proc (_, _, _, _, e)) ->
                    let rec loop e =
                      print_endline "===== BEFORE =====";
                      PPrint.ToChannel.pretty 1.0 80 Stdlib.stdout 
                        (Pp_core.Basic.pp_expr e);
                      flush_all ();
                      let e' = Core_peval.step_peval_expr file e in
                      print_endline "\n===== AFTER =====";
                      PPrint.ToChannel.pretty 1.0 80 Stdlib.stdout 
                        (Pp_core.Basic.pp_expr e');
                      flush_all ();
                      Scanf.scanf "%s\n" (fun _ ->
                        loop e'
                      )
                    in loop e
                | _ ->
                    assert false
              end
(*              Core_peval.boom file *)
              
        end


open Cmdliner

let file =
  let doc = "source Core file" in
  Arg.(required & pos ~rev:true 0 (some string) None & info [] ~docv:"FILE" ~doc)


let () =
  let playground_t = Term.(const playground(*_core*) $ file) in
  Stdlib.exit @@ Cmd.eval (Cmd.(v (info "Core playground") playground_t))
