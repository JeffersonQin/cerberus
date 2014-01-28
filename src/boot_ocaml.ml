open Global

let assert_false str =
  Pervasives.failwith ("[Impossible error>\n" ^ str)

let debug_level = ref 0

let print_debug str k =
  if !debug_level > 0 then
    let _ = Pervasives.print_endline ("\x1b[31mDEBUG: " ^ str ^ "\x1b[0m") in k
  else
    k

let pickList = function
  | []  -> failwith ""
  | [x] -> ([], x, [])
  | xs  -> let l = List.length xs in
           let (ys,z::zs) = Lem_list.split_at (Random.int l) xs in
           (ys, z, zs)

(* Pretty printing *)
let to_plain_string d =
  let buf = Buffer.create 50 in
  PPrint.ToBuffer.compact buf d;
  let str = Buffer.contents buf in
  Buffer.clear buf;
  str


let pp_ail_ctype ty = to_plain_string (Pp_ail.pp_ctype ty)
let pp_ail_expr e = to_plain_string (Pp_ail.pp_expression e)
let pp_core_expr e = to_plain_string (Pp_core.pp_expr e)
