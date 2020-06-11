(* Created by Victor Gomes 2017-03-10 *)

open Util
open Cerb_frontend

module M = Impl_mem
module C = Ctype

(* Undefined Behaviour *)
exception Undefined of string
exception Error of string

let (>>=) = M.bind
let return = M.return

(* Keep track of the last memory operation, for error display *)
type memop = Store | Load | Create | Alloc | None
let last_memop = ref None

let show_memop = function
  | Store -> "store"
  | Load -> "load"
  | Create -> "create"
  | Alloc -> "alloc"
  | None -> raise (Error "unknown last memop")

(* Runtime flags *)
let batch =
  try ignore (Sys.getenv "CERB_BATCH"); true
  with _ -> false

(* stdout if in batch mode *)
let stdout = ref ""

let position fname lnum bol cnum = {
  Lexing.pos_fname = fname;
  Lexing.pos_lnum = lnum;
  Lexing.pos_bol = bol;
  Lexing.pos_cnum = cnum;
}

let unknown = Location_ocaml.unknown

(* TODO: digest is wrong *)
let sym (n, s) = Symbol.Symbol ("", n, Some s)
let cabsid pos id =
  let mkloc x = x in
  Symbol.Identifier (mkloc pos, id)

(* Helper Types *)

let char_t = C.Basic (C.Integer C.Char)
let bool_t = C.Basic (C.Integer C.Bool)
let schar_t = C.Basic (C.Integer (C.Signed C.Ichar))
let uchar_t = C.Basic (C.Integer (C.Unsigned C.Ichar))
let int_t = C.Basic (C.Integer (C.Signed C.Int_))
let uint_t = C.Basic (C.Integer (C.Unsigned C.Int_))
let short_t = C.Basic (C.Integer (C.Signed C.Short))
let ushort_t = C.Basic (C.Integer (C.Unsigned C.Short))
let long_t = C.Basic (C.Integer (C.Signed C.Long))
let ulong_t = C.Basic (C.Integer (C.Unsigned C.Long))
let longlong_t = C.Basic (C.Integer (C.Signed C.LongLong))
let ulonglong_t = C.Basic (C.Integer (C.Unsigned C.LongLong))
let size_t = C.Basic (C.Integer C.Size_t)
let ptrdiff_t = C.Basic (C.Integer C.Ptrdiff_t)
let float_t = C.Basic (C.Floating (C.RealFloating C.Float))
let double_t = C.Basic (C.Floating (C.RealFloating C.Double))
let longdouble_t = C.Basic (C.Floating (C.RealFloating C.LongDouble))


let are_compatible _ _ = false

(* Non deterministic choice *)

let nd n xs =
  Random.self_init ();
  Random.int n |> List.nth xs

(* IV wraps *)

let ivctor memf errmsg = function
  | C.Basic (C.Integer it) -> memf it
  | _ -> raise (Error errmsg)

let ivmin   = ivctor M.min_ival "ivmin"
let ivmax   = ivctor M.max_ival "ivmax"
let ivcompl = ivctor M.bitwise_complement_ival "ivcompl"
let ivand   = ivctor M.bitwise_and_ival "ivand"
let ivor    = ivctor M.bitwise_or_ival "ivor"
let ivxor   = ivctor M.bitwise_xor_ival "ivxor"

let fvfromint = M.fvfromint
let ivfromfloat (cty, x) =
  match cty with
  | C.Basic (C.Integer it) -> M.ivfromfloat it x
  | _ -> raise (Error "ivfromfloat")

let intcast_ptrval cty itarget x =
  match itarget with
  | C.Basic (C.Integer it) -> M.intcast_ptrval cty it x
  | _ -> raise (Error "intcast_ptrval")

(* Ail types *)

let ail_qualifier (c, r, v) =
  { C.const = c;
    C.restrict = r;
    C.volatile = v
  }

let is_scalar ty =
  AilTypesAux.is_scalar (Core_aux.unproj_ctype ty)

let is_integer ty =
  AilTypesAux.is_integer (Core_aux.unproj_ctype ty)

let is_signed ty =
  AilTypesAux.is_signed_integer_type (Core_aux.unproj_ctype ty)

let is_unsigned ty =
  AilTypesAux.is_unsigned_integer_type (Core_aux.unproj_ctype ty)

(* Loaded - Specified and unspecified values *)

type 'a loaded =
  | Specified of 'a
  | Unspecified of C.ctype0

let specified x = Specified x
let unspecified x = Unspecified x

let case_loaded f g = function
  | Specified x -> f x
  | Unspecified cty -> g cty

exception Label of string * (M.integer_value) loaded

(* Cast from memory values *)

let get_integer m =
  let terr _ _ = raise (Error "Type mismatch, expecting integer values.") in
  M.case_mem_value m unspecified terr (fun _ -> specified)
    terr terr (terr()) terr terr

let get_float m =
  let terr _ _ = raise (Error "Type mismatch, expecting integer values.") in
  M.case_mem_value m unspecified terr terr (fun _ -> specified)
    terr (terr()) terr terr

let get_pointer m =
  let terr _ _ = raise (Error "Type mismatch, expecting pointer values.") in
  M.case_mem_value m unspecified terr terr terr (fun _ p -> specified p)
    (terr()) terr terr

let get_array m =
  let terr _ _ = raise (Error "Type mismatch, expecting array.") in
  M.case_mem_value m unspecified terr terr terr terr
    specified terr terr

let get_struct m =
  let terr _ _ = raise (Error "Type mismatch, expecting struct.") in
  M.case_mem_value m unspecified terr terr terr terr (terr())
    (fun _ -> specified) terr

let get_union m =
  let terr _ _ = raise (Error "Type mismatch, expecting union.") in
  M.case_mem_value m unspecified terr terr terr terr (terr())
    terr (fun _ cid m -> Specified (cid, m))

(* Cast to memory values *)

let case_loaded_mval f = case_loaded f M.unspecified_mval

let mk_int s = M.integer_ival (Nat_big_num.of_string s)
let mk_float s = M.str_fval s
let mk_array xs = (*M.array_mval*) (List.map (case_loaded_mval id) xs)

let mk_pointer alloc_id addr =
  M.concrete_ptrval (Nat_big_num.of_string alloc_id)
                    (Nat_big_num.of_string addr)

let mk_null cty = M.null_ptrval cty
let mk_null_void = mk_null C.Void0

(* Binary operations wrap *)

let add = M.op_ival Mem_common.IntAdd
let sub = M.op_ival Mem_common.IntSub
let mul = M.op_ival Mem_common.IntMul
let div = M.op_ival Mem_common.IntDiv
let remt = M.op_ival Mem_common.IntRem_t
let remf = M.op_ival Mem_common.IntRem_f
let exp = M.op_ival Mem_common.IntExp

let addf = M.op_fval Mem_common.FloatAdd
let subf = M.op_fval Mem_common.FloatSub
let mulf = M.op_fval Mem_common.FloatMul
let divf = M.op_fval Mem_common.FloatDiv

let eq n m = Option.get (M.eq_ival (Some M.initial_mem_state) n m)
let lt n m = Option.get (M.lt_ival (Some M.initial_mem_state) n m)
let gt n m = Option.get (M.lt_ival (Some M.initial_mem_state) m n)
let le n m = Option.get (M.le_ival (Some M.initial_mem_state) n m)
let ge n m = Option.get (M.le_ival (Some M.initial_mem_state) m n)

let valid_for_deref_ptrval p = return @@ M.validForDeref_ptrval p
let memcmp p q r = return @@ M.memcmp p q r
let memcpy p q r = return @@ M.memcpy p q r
let realloc al p size  = return @@ M.realloc 0 al p size

(* Memory actions wrap *)

let ptr_well_aligned = M.isWellAligned_ptrval

let create pre al ty x_opt =
  last_memop := Create;
  M.allocate_object 0 pre al ty
    (Option.case (fun x -> Some (case_loaded_mval id x))
       (fun () -> None) x_opt)

let alloc pre al n =
  last_memop := Alloc;
  M.allocate_region 0 pre al n

let load cty ret e =
  last_memop := Load;
  M.load Location_ocaml.unknown cty e >>= return % ret % snd

let load_integer ity =
  load (C.Basic (C.Integer ity)) get_integer

let load_float fty =
  load (C.Basic (C.Floating fty)) get_float

let load_pointer q cty =
  load (C.Pointer0 (q, cty)) get_pointer

let load_array q cty size =
  load (C.Array0 (cty, size)) get_array

let load_struct s =
  load (C.Struct0 s) get_struct

let load_union s =
  load (C.Union0 s) get_union

let store f ty b e1 e2 =
  last_memop := Store;
  M.store Location_ocaml.unknown ty b e1 @@ case_loaded_mval f e2

let store_integer ity =
  store (M.integer_value_mval ity) (C.Basic (C.Integer ity))

let store_pointer q cty =
  store (M.pointer_mval cty) (C.Pointer0 (q, cty))

let store_struct s =
  store (M.struct_mval s) (C.Struct0 s)

let store_union s cid =
  store (M.union_mval s cid) (C.Union0 s)

let store_array_of conv cty size =
  let array_mval e = M.array_mval (List.map (case_loaded_mval conv) e)
  in store array_mval (C.Array0 (cty, size))

let store_array_of_int ity =
  store_array_of (M.integer_value_mval ity) (C.Basic (C.Integer ity))

let store_array_of_float fty =
  store_array_of (M.floating_value_mval fty) (C.Basic (C.Floating fty))

let store_array_of_ptr q cty =
  store_array_of (M.pointer_mval cty) (C.Pointer0 (q, cty))

let store_array_of_struct s =
  store_array_of (M.struct_mval s) (C.Struct0 s)

(* Printf wrap *)

let printf (conv : C.ctype0 -> M.integer_value -> M.integer_value)
    (xs:M.integer_value list)
    (args:(C.ctype0 * M.pointer_value) list) =
  let encode ival = match Mem_aux.integerFromIntegerValue ival with
    | Some n -> Decode_ocaml.encode_character_constant n
    | None -> Debug_ocaml.error
                "Printf: one of the element of the format array was invalid"
  in
  let eval_conv cty x =
    let terr _ _ = raise (Error "Rt_ocaml.printf: expecting an integer") in
    let n = M.case_mem_value x (terr()) terr (fun _ -> conv cty)
        terr terr (terr()) terr terr
    in Nondeterminism.nd_return (Either.Right (Undefined.Defined
                       (Core.Vloaded (Core.LVspecified (Core.OVinteger n)))))
  in
  Output.printf eval_conv (List.rev (List.map encode xs)) args
  >>= begin function
    | Either.Right (Undefined.Defined xs) ->
      let n = List.length xs in
      let output = String.init n (List.nth xs) in
      if batch then stdout := !stdout ^ String.escaped output
      else print_string output;
      return (Specified (M.integer_ival (Nat_big_num.of_int n)))
      (*return (M.integer_ival (Nat_big_num.of_int n))*)
    | Either.Right (Undefined.Undef (_, xs) ) ->
      raise (Error (String.concat "," 
                      (List.map Undefined.stringFromUndefined_behaviour xs)))
    | Either.Right (Undefined.Error (_, m) ) -> raise (Error m)
    | Either.Left z -> raise (Error (Pp_errors.to_string z))
  end

let sprintf _ = failwith "No support for sprintf"
let snprintf _ = failwith "No support for snprintf"

(* Exit *)

exception Exit of (M.integer_value loaded)

let print_batch i res =
  Printf.printf "Defined {value: \"%s\", stdout: \"%s\", stderr: \"\", blocked: \"false\"}\n" res !stdout

let print_err_batch e =
  let err = match e with
    (*| Mem_common.MerrUnitialised str -> "MerrUnitialised \"" ^  (str ^ "\"")*)
    | Mem_common.MerrInternal str -> "MerrInternal \"" ^  (str ^ "\"")
    | Mem_common.MerrOther str -> "MerrOther \"" ^  (str ^ "\"")
    (*| Mem_common.MerrReadFromDead -> "MerrReadFromDead"*)
    | Mem_common.MerrWIP str -> "Memory WIP: " ^ str
    | _ -> "memory error"
  in
  Printf.sprintf "Killed {msg: memory layout error (%s seq) ==> %s}" (show_memop !last_memop) err

let string_of_specified n =
  Printf.sprintf "Specified(%s)" (Nat_big_num.to_string n)

let string_of_unspec cty =
  Printf.sprintf "Unspecified(\"%s\")" (String_core_ctype.string_of_ctype cty)

let dummy_file = 
  let cmp = Symbol.instance_Basic_classes_Ord_Symbol_sym_dict.Lem_basic_classes.compare_method in
  let impl_cmp = Implementation_.instance_Basic_classes_SetType_Implementation__implementation_constant_dict.Lem_pervasives.setElemCompare_method in
  Core.{
    main    = None;
    tagDefs = Pmap.empty cmp;
    stdlib  = Pmap.empty cmp;
    globs   = [];
    funs    = Pmap.empty cmp;
    impl    = Pmap.empty impl_cmp;
    funinfo = Pmap.empty cmp;
    extern  = Pmap.empty compare;
  }

let quit f =
  try
    let initial_state = Driver.initial_driver_state dummy_file
        Sibylfs.fs_initial_state in
    match Smt2.runND Random Impl_mem.cs_module (Driver.liftMem (f (fun x -> raise (Exit x)) ())) initial_state with
    | _ -> raise (Error "continuation not raised")
  with
  | Exit x ->
    (match x with
     | Specified x ->
       let n = M.eval_integer_value x |> Option.get in
       if batch then print_batch 0 (string_of_specified n);
       exit (Nat_big_num.to_int n)
     | Unspecified cty ->
       if batch then print_batch 0 (string_of_unspec cty);
       exit(-1)
    )

(* Start *)

let set_global (f, x) =
  f return () >>= fun y -> x := y; return ()

let init_globals glbs =
  List.fold_left
    (fun acc (f, x) -> acc >>= fun _ -> set_global (f, x))
    (return ()) glbs

let create_tag_defs_map defs =
  List.fold_left
    (fun m (s, xs) -> Pmap.add s xs m)
    (Pmap.empty Symbol.symbol_compare) defs

let run tags gls main =
  begin fun cont args ->
    Tags.set_tagDefs (create_tag_defs_map tags);
    init_globals gls
    >>= fun _ -> main cont args
  end |> quit

(* Conv loaded mem value *)

let conv_int_mval it =
  case_loaded_mval (M.integer_value_mval it)

let conv_float_mval ft =
  case_loaded_mval (M.floating_value_mval ft)

let conv_ptr_mval cty =
  case_loaded_mval (M.pointer_mval cty)

let conv_struct_mval s =
  case_loaded_mval (M.struct_mval s)

