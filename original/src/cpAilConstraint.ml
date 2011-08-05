open CpPervasives

module BI = BatBig_int

type constant =
  | Name of CpSymbol.t
  | Integer of BI.t
  | Address of CpSymbol.t
  | Null
  | Offset of constant * constant * constant
  | Plus of constant * constant
  | Minus of constant * constant
  | Mod of constant * constant
  | Mult of constant * constant
  | Div of constant * constant
  | Pow of constant
  | BitAnd of constant * constant
  | BitOr of constant * constant
  | BitXor of constant * constant
  | BitComplement of constant
  | Fn of string * constant list

let rec fold_map_const f i const =
  let fm = fold_map_const f in
  match const with
  | Name _ | Integer _ | Address _ | Null -> f i const
  | Offset (c1, c2, c3) ->
      let i, c1 = fm i c1 in
      let i, c2 = fm i c2 in
      let i, c3 = fm i c3 in
      f i (Offset (c1, c2, c3))
  | Plus (c1, c2) ->
      let i, c1 = fm i c1 in
      let i, c2 = fm i c2 in
      f i (Plus (c1, c2))
  | Minus (c1, c2) ->
      let i, c1 = fm i c1 in
      let i, c2 = fm i c2 in
      f i (Minus (c1, c2))
  | Mod (c1, c2) ->
      let i, c1 = fm i c1 in
      let i, c2 = fm i c2 in
      f i (Mod (c1, c2))
  | Mult (c1, c2) ->
      let i, c1 = fm i c1 in
      let i, c2 = fm i c2 in
      f i (Mult (c1, c2))
  | Div (c1, c2) ->
      let i, c1 = fm i c1 in
      let i, c2 = fm i c2 in
      f i (Div (c1, c2))
  | Pow c ->
      let i, c = fm i c in
      f i (Pow c)
  | BitAnd (c1, c2) ->
      let i, c1 = fm i c1 in
      let i, c2 = fm i c2 in
      f i (BitAnd (c1, c2))
  | BitOr (c1, c2) ->
      let i, c1 = fm i c1 in
      let i, c2 = fm i c2 in
      f i (BitOr (c1, c2))
  | BitXor (c1, c2) ->
      let i, c1 = fm i c1 in
      let i, c2 = fm i c2 in
      f i (BitXor (c1, c2))
  | BitComplement c ->
      let i, c = fm i c in
      f i (BitComplement c)
  | Fn (s, cs) ->
      let i, cs = List.fold_left
        (fun (i, cs) c -> let i, c = f i c in i, c::cs) (i, []) cs in
      f i (Fn (s, cs))

let rec compare_const const1 const2 =
  let (++) n p = if n = 0 then p else n in
  match const1, const2 with
  | Integer i1, Integer i2 ->
      BI.compare i1 i2
  | Offset (c1, c2, c3), Offset (c1', c2', c3') ->
      compare_const c1 c1'
      ++ compare_const c2 c2'
      ++ compare_const c3 c3'
  | Plus (c1, c2), Plus (c1', c2') ->
      compare_const c1 c1'
      ++ compare_const c2 c2'
  | Minus (c1, c2), Minus (c1', c2') ->
      compare_const c1 c1'
      ++ compare_const c2 c2'
  | Mod (c1, c2), Mod (c1', c2') ->
      compare_const c1 c1'
      ++ compare_const c2 c2'
  | Mult (c1, c2), Mult (c1', c2') ->
      compare_const c1 c1'
      ++ compare_const c2 c2'
  | Div (c1, c2), Div (c1', c2') ->
      compare_const c1 c1'
      ++ compare_const c2 c2'
  | Pow c1, Pow c2 ->
      compare_const c1 c2
  | BitAnd (c1, c2), BitAnd (c1', c2') ->
      compare_const c1 c1'
      ++ compare_const c2 c2'
  | BitOr (c1, c2), BitOr (c1', c2') ->
      compare_const c1 c1'
      ++ compare_const c2 c2'
  | BitXor (c1, c2), BitXor (c1', c2') ->
      compare_const c1 c1'
      ++ compare_const c2 c2'
  | BitComplement c1, BitComplement c2 ->
      compare_const c1 c2
  | Fn (n1, cs1), Fn (n2, cs2) ->
      List.fold_left2
        (fun r c1 c2 -> r ++ compare_const c1 c2) (compare n1 n2) cs1 cs2
  | _ -> compare const1 const2

type constr =
  | True
  | False
  | Eq of constant * constant
  | Le of constant * constant
  | Lt of constant * constant
  | Not of constr
  | Or of constr * constr
  | And of constr * constr
  | Implies of constr * constr
  | If of constr * constr * constr
  | ConvInt of CpRange.range * constr * constant

let rec fold_constr f_c i constr =
  let f = fold_constr f_c in
  match constr with
  | True -> i
  | False -> i
  | Eq (c1, c2) -> f_c (f_c i c1) c2
  | Le (c1, c2) -> f_c (f_c i c1) c2
  | Lt (c1, c2) -> f_c (f_c i c1) c2
  | Not c -> f i c
  | Or (c1, c2) -> f (f i c1) c2
  | And (c1, c2) -> f (f i c1) c2
  | Implies (c1, c2) -> f (f i c1) c2
  | If (c1, c2, c3) -> f (f (f i c1) c2) c3
  | ConvInt (_, c1, c2) -> f (f_c i c2) c1

let rec fold_map_constr f f_c i constr =
  let fm = fold_map_constr f f_c in
  match constr with
  | Eq (c1, c2) ->
      let i, c1 = f_c i c1 in
      let i, c2 = f_c i c2 in
      f i (Eq (c1, c2))
  | Le (c1, c2) ->
      let i, c1 = f_c i c1 in
      let i, c2 = f_c i c2 in
      f i (Le (c1, c2))
  | Lt (c1, c2) ->
      let i, c1 = f_c i c1 in
      let i, c2 = f_c i c2 in
      f i (Lt (c1, c2))
  | Not c ->
      let i, c = fm i c in
      f i (Not c)
  | Or (c1, c2) ->
      let i, c1 = fm i c1 in
      let i, c2 = fm i c2 in
      f i (Or (c1, c2))
  | And (c1, c2) ->
      let i, c1 = fm i c1 in
      let i, c2 = fm i c2 in
      f i (And (c1, c2))
  | Implies (c1, c2) ->
      let i, c1 = fm i c1 in
      let i, c2 = fm i c2 in
      f i (Implies (c1, c2))
  | If (c1, c2, c3) ->
      let i, c1 = fm i c1 in
      let i, c2 = fm i c2 in
      let i, c3 = fm i c3 in
      f i (If (c1, c2, c3))
  | ConvInt (r, c1, c2) ->
      let i, c1 = fm  i c1 in
      let i, c2 = f_c i c2 in
      f i (ConvInt (r, c1, c2))
  | _ -> f i constr

let rec compare_constr constr1 constr2 =
  let (++) n p = if n = 0 then p else n in
  match constr1, constr2 with
  | Eq (c1, c2), Eq (c1', c2') ->
      compare_const c1 c1'
      ++ compare_const c2 c2'
  | Le (c1, c2), Le (c1', c2') ->
      compare_const c1 c1'
      ++ compare_const c2 c2'
  | Lt (c1, c2), Lt (c1', c2') ->
      compare_const c1 c1'
      ++ compare_const c2 c2'
  | Not c1, Not c2 ->
      compare_constr c1 c2
  | Or (c1, c2), Or (c1', c2') ->
      compare_constr c1 c1'
      ++ compare_constr c2 c2'
  | And (c1, c2), And (c1', c2') ->
      compare_constr c1 c1'
      ++ compare_constr c2 c2'
  | Implies (c1, c2), Implies (c1', c2') ->
      compare_constr c1 c1'
      ++ compare_constr c2 c2'
  | If (c1, c2, c3), If (c1', c2', c3') ->
      compare_constr c1 c1'
      ++ compare_constr c2 c2'
      ++ compare_constr c3 c3'
  | ConvInt (_, c1, _), ConvInt (_, c1', _) ->
      compare_constr c1 c1'
  | _ -> compare constr1 constr2

module S = BatSet.Make(struct
  type t = constr
  let compare = compare_constr
end)

type t = S.t

let compare t1 t2 = S.compare t1 t2

let symbol_set = CpSymbol.make ()
let fresh () = CpSymbol.fresh symbol_set

let empty = S.empty
let make c = S.singleton c
let from_list cs = List.fold_left (fun t c -> S.add c t) S.empty cs

let tt = True

let neq c1 c2 = Not (Eq (c1, c2))
let eq c1 c2 = Eq (c1, c2)
let le c1 c2 = Le (c1, c2)
let lt c1 c2 = Lt (c1, c2)
let ge c1 c2 = Le (c2, c1)
let gt c1 c2 = Lt (c2, c1)

let union t1 t2 = S.union t1 t2
let add t c = S.add c t

let fresh_name () = Name (fresh ())
let fresh_named s = Name (CpSymbol.fresh_name symbol_set s)
let fresh_address () = Address (fresh ())

let const i = Integer i
let fn name args = Fn (name, args)

let zero = const (BatBig_int.zero)
let one  = const (BatBig_int.one)

let null = Null

let offset c1 c2 c3 = Offset (c1, c2, c3)

let plus  c1 c2 = Plus  (c1, c2)
let minus c1 c2 = Minus (c1, c2)
let mult  c1 c2 = Mult  (c1, c2)
let div   c1 c2 = Div   (c1, c2)
let pow c = Pow c

let modulo c1 c2 = Mod (c1, c2)

let bit_and c1 c2 = BitAnd (c1, c2)
let bit_or  c1 c2 = BitOr  (c1, c2)
let bit_xor c1 c2 = BitXor (c1, c2)

let neg c = Not c
let conj c1 c2 = And (c1, c2)
let disj c1 c2 = Or (c1, c2)
let implies c1 c2 = Implies (c1, c2)
let case c c1 c2 = If (c, c1, c2)

let conv_int r c1 c2 = ConvInt (r, c1, c2)

let undef = eq (fresh_named "UNDEFINED") one

let mem c t = S.mem c t

module Print = struct
  module S = S
  module P = Pprint
  module U = P.Unicode

  open Pprint.Operators

  let nbraces d = P.lbrace ^^ P.group2 (P.break0 ^^ d) ^/^ P.rbrace

  let rec pp_constant_inner f_s const =
    let f = P.parens -| pp_constant_inner f_s in
    let fp = pp_constant_inner f_s in
    match const with
    | Null -> U.null
    | Name s -> !^ (f_s s)
    | Integer i -> !^ (BatBig_int.to_string i)
    | Address s ->
        !^ "addr" ^^^ P.parens (!^ (f_s s))
    | Offset (base, offset, size) ->
        !^ "offset" ^^^ P.parens (fp base ^^ P.comma ^^^ fp offset ^^^ P.star ^^^ fp size)
    | Plus (c1, c2) -> f c1 ^^^ P.plus ^^^ f c2
    | Minus (c1, c2) -> f c1 ^^^ P.minus ^^^ f c2
    | Mult (c1, c2) -> f c1 ^^^ P.star ^^^ f c2
    | Mod (c1, c2) -> f c1 ^^^ P.percent ^^^ f c2
    | Div (c1, c2) -> f c1 ^^^ P.slash ^^^ f c2
    | Pow c -> !^ "2" ^^ P.caret ^^ f c
    | BitAnd (c1, c2) -> !^ "bitand" ^^^ P.parens (f c1 ^^ P.comma ^^^ f c2)
    | BitOr (c1, c2) -> !^ "bitor" ^^^ P.parens (f c1 ^^ P.comma ^^^ f c2)
    | BitXor (c1, c2) -> !^ "xor" ^^^ P.parens (f c1 ^^ P.comma ^^^ f c2)
    | BitComplement c -> !^ "compl" ^^^ P.parens (f c)
    | Fn (name, args) -> !^ name ^^^ P.parens (P.comma_list f args)

  let rec pp_constr_inner f_s constr =
    let f = P.parens -| pp_constr_inner f_s in
    let f_c = pp_constant_inner f_s in
    match constr with
    | True -> !^ "true"
    | False -> !^ "false"
    | Eq (c1, c2) -> f_c c1 ^^^ P.equals ^^^ f_c c2
    | Le (c1, c2) -> f_c c1 ^^^ U.le ^^^ f_c c2
    | Lt (c1, c2) -> f_c c1 ^^^ P.langle ^^^ f_c c2
    | Or  (c1, c2) -> f c1 ^^^ U.disj ^^^ f c2
    | And (c1, c2) -> f c1 ^^^ U.conj ^^^ f c2
    | Implies (c1, c2) -> f c1 ^^^ U.implies ^^^ f c2
    | Not c -> U.compl ^^^ f c
    | If (c1, c2, c3) ->
        !^ "if" ^^^ f c1 ^^^ !^ "then" ^^^ f c2 ^^^ !^ "else" ^^^ f c3
    | ConvInt (_, c1, _) -> pp_constr_inner f_s c1

  let pp_constant_latex = pp_constant_inner CpSymbol.to_string_latex
  let pp_constant = pp_constant_inner CpSymbol.to_string_pretty
  let pp_constr = pp_constr_inner CpSymbol.to_string_pretty

  let rec pp t = U.conj ^^ nbraces (P.comma_list pp_constr (S.elements t))

  let pp_set ts = P.sepmap P.break1 pp (BatSet.elements ts)
end

module Process = struct
  module M = BatMap
  module S = S
  module CC = CpCongruenceClosure

  exception Invalid
  exception Partial of t

  let null = 0
  let offset = 1
  let plus = 2
  let minus = 3
  let modulo = 4
  let mult = 5
  let div = 6
  let pow = 7
  let bitand = 8
  let bitor = 9
  let bitxor = 10
  let bitcomplement = 11
  let fn = 12

  type p = {
    t : t;
    eqs : t;
    cc : CC.t;
    counter : int;
    int_map : (BI.t, int) M.t;
    name_map : (CpSymbol.t, int) M.t;
    const_map : (int, constant) M.t;
    apply_map : (int * int, int) M.t;
    fn_map : (string, int) M.t
  }

  let fresh p =
    let n = p.counter + 1 in
    if n + 1 < CC.size p.cc then
      {p with counter = n}, n
    else 
      {p with counter = n; cc = CC.grow p.cc (CC.size p.cc)}, n

  let convert_name p s =
    try
      p, M.find s p.name_map
    with Not_found ->
      let p, n = fresh p in
      {p with name_map = M.add s n p.name_map}, n

  let convert_addr p a =
    try
      p, M.find a p.name_map
    with Not_found ->
      let p, n = fresh p in
      {p with
        name_map = M.add a n p.name_map;
        const_map = M.add n (Address a) p.const_map
      }, n

  let convert_int p i =
    try
      p, M.find i p.int_map
    with Not_found ->
      let p, n = fresh p in
      {p with
        int_map = M.add i n p.int_map;
        const_map = M.add n (Integer i) p.const_map
      }, n

  let convert_fn p s =
    try
      p, M.find s p.fn_map
    with Not_found ->
      let p, n = fresh p in
      {p with fn_map = M.add s n p.fn_map}, n

  let apply p n1 n2 =
    try
      p, M.find (n1, n2) p.apply_map
    with Not_found ->
      let p, n = fresh p in
      {p with
        apply_map = M.add (n1, n2) n p.apply_map;
        cc = CC.merge p.cc (CC.Apply (n1, n2)) n
      }, n

  let rec convert_const p c =
    let f = convert_const in
    let f_a = apply in
    let chain i cs = List.fold_left
      (fun (p, n) c ->
        let p', n' = f p c in
        f_a p' n n'
      ) i cs in
    let f1 n c = chain (p, n) [c] in
    let f2 n c1 c2 = chain (p, n) [c1; c2] in
    let f3 n c1 c2 c3 = chain (p, n) [c1; c2; c3] in
    match c with
    | Name n -> convert_name p n
    | Integer i -> convert_int p i
    | Address a -> convert_addr p a
    | Null -> p, null
    | Offset (c1, c2, c3) ->
        let p, n = f3 offset c1 c2 c3 in
        if M.mem n p.const_map then
          p, n
        else
          {p with const_map = M.add n (Offset (c1, c2, c3)) p.const_map}, n
    | Plus (c1, c2) -> f2 plus c1 c2
    | Minus (c1, c2) -> f2 minus c1 c2
    | Mod (c1, c2) -> f2 modulo c1 c2
    | Mult (c1, c2) -> f2 mult c1 c2
    | Div (c1, c2) -> f2 div c1 c2
    | Pow c -> f1 pow c
    | BitAnd (c1, c2) -> f2 bitand c1 c2
    | BitOr (c1, c2) -> f2 bitor c1 c2
    | BitXor (c1, c2) -> f2 bitxor c1 c2
    | BitComplement c -> f1 bitcomplement c
    | Fn (s, cs) -> chain (convert_fn p s) cs

  let lift p f = S.fold (fun c p -> f p c) p.t p
  let lift_const p f = lift p (fold_constr f)

  let init_convert p = lift_const p (fun p c -> fst (convert_const p c))

  let collect p b constr =
    match constr with
    | Eq (c1, c2) ->
        let p1, n1 = convert_const p  c1 in
        let p2, n2 = convert_const p1 c2 in
        {p2 with
          cc = CC.merge_constants p2.cc n1 n2;
          eqs = S.add constr p.eqs
        }, true
    | _ -> p, b

  let collect_eqs p = S.fold (fun c (p, b) -> collect p b c) p.t (p, false)

  let check_unsat p = if mem False p.t then (raise Invalid) else p

  let normalise_const p c =
    let p, n = convert_const p c in
    p, CC.normalise_constant p.cc n

  let simplify_const p const =
    let simplify p const =
      let replace c =
        let p1, n1 = normalise_const p const in
        let p2, n2 = normalise_const p1 c in
        {p2 with cc = CC.merge_constants p.cc n1 n2}, c in
      match const with
      | Offset (a, Integer i, _) when BI.(=) i BI.zero ->
          replace a
      | Offset (Offset (a, o1, s1), o2, s2)
          when compare_const s1 s2 = 0 ->
          replace (Offset (a, Plus (o1, o2), s1))
      | Plus (Integer i1, Integer i2) ->
          let open BatBig_int in
          replace (Integer (i1 + i2))
      | Minus (Integer i1, Integer i2) ->
          let open BatBig_int in
          replace (Integer (i1 - i2))
      | Mult (Integer i1, Integer i2) ->
          let open BatBig_int in
          replace (Integer (i1 * i2))
      | Mod (Integer i1, Integer i2) when BI.(<>) i2 BI.zero ->
          let open BatBig_int in
          replace (Integer (modulo i1 i2))
      | Div (Integer i1, Integer i2) when BI.(<>) i2 BI.zero ->
          let open BatBig_int in
          replace (Integer (i1 / i2))
      | Pow (Integer i) ->
          let open BatBig_int in
          let two = one + one in
          replace (Integer (pow two i))
      | Name _ ->
          let p, n = normalise_const p const in
          p, (try M.find n p.const_map with Not_found -> const)
      | _ -> p, const in
    fold_map_const simplify p const

  let simplify p =
    let simplify_constr p constr =
      let merge c1 c2 =
        let p1, n1 = normalise_const p c1 in
        let p2, n2 = normalise_const p1 c2 in
        {p2 with cc = CC.merge_constants p.cc n1 n2} in
      match constr with
      | Not (False) -> p, True
      | Not (True)  -> p, False
      | Or (True, _) -> p, True
      | Or (_, True) -> p, True
      | Or (False, False) -> p, False
      | Or (c1, False) -> p, c1
      | Or (False, c2) -> p, c2
      | And (False, _) -> p, False
      | And (_, False) -> p, False
      | And (True, True) -> p, True
      | And (c1, True) -> p, c1
      | And (True, c2) -> p, c2
      | Implies (False, _) -> p, True
      | Implies (True, c2) -> p, c2
      | Implies (c1, True) -> p, True
      | Implies (c1, False) -> p, Not c1
      | If (True, c2, _) -> p, c2
      | If (False, _, c3) -> p, c3
      | Le (Integer i1, Integer i2) ->
          let open BatBig_int in
          p, if i1 <= i2 then True else False
      | Lt (Integer i1, Integer i2) ->
          let open BatBig_int in
          p, if i1 < i2 then True else False
      | Lt (a1, Offset (a2, Integer i2, _)) when compare_const a1 a2 = 0 ->
          if BI.(<) BI.zero i2 then
            p, True
          else
            p, False
      | Lt (Offset (a1, Integer i1, s1), Offset (a2, Integer i2, s2))
          when compare_const a1 a2 = 0 && compare_const s1 s2 = 0 ->
          if BI.(<) i1 i2 then
            p, True
          else
            p, False
      | Eq (c1, c2) when compare_const c1 c2 = 0 -> merge c1 c2, True
      | Eq (Integer _, Integer _) -> p, False
      | Eq (Address _, Address _) -> p, False
      | Eq (c1, c2) | Le (c1, c2) ->
          let p1, n1 = normalise_const p  c1 in
          let p2, n2 = normalise_const p1 c2 in
          if CC.congruent_constants p.cc n1 n2 then
            p2, True
          else p2, constr
      | ConvInt (r, If (_, c2, _), Integer i) when CpRange.in_range r i ->
          p, c2
      | _ -> p, constr in
    let simplify_all = fold_map_constr simplify_constr simplify_const in
    let p, t = S.fold_map simplify_all p.t p in
    {p with t = t}

  let normalise_const_map p =
    let norm p m n c =
      let p, c = match c with
        | Offset _ -> simplify_const p c
        | _ -> p, c in
      p, M.add (CC.normalise_constant p.cc n) c m in
    let p, m = List.fold_left
      (fun (p, m) (n, c) -> norm p m n c)
      (p, M.empty)
      (M.bindings p.const_map) in
    {p with const_map = m}

  let convert = fold_constr (fun p c -> fst (convert_const p c))

  let rec simplify_loop p =
    let rewrite p = 
      normalise_const_map p
      |> simplify
      |> check_unsat in
    match collect_eqs (rewrite p) with
    | p, true  -> simplify_loop p
    | p, false -> p

  let conj p constr =
    let p = convert p constr in
    fst (collect_eqs ({p with t = add p.t constr}))

  let make t =
    let p = {
      t = t;
      eqs = empty;
      cc = CC.create 2048;
      counter = fn;
      int_map = M.create BI.compare;
      name_map = M.empty;
      const_map = M.empty;
      apply_map = M.empty;
      fn_map = M.empty
    } in
    simplify_loop (init_convert p)

  let complete p =
    let p = simplify_loop p in
    union p.t p.eqs

  let union p c = S.fold (fun constr p -> conj p constr) c p

  let rewrite p const = simplify_const (fst (convert_const p const)) const

  type address =
    | Base of CpSymbol.t
    | Displaced of CpSymbol.t * int * constant
    | NullAddress

  exception Simplify

  let address_aux p const =
    p, match const with
    | Address a -> Base a
    | Offset (Address a, Integer i, Name n) ->
        Displaced (a, BI.to_int i, Name n)
    | Null -> NullAddress
    | _ -> raise Simplify

  let address p const =
    let p, const = rewrite p const in
    try
      address_aux p const
    with Simplify ->
      let p, const = rewrite (simplify_loop p) const in
      try
        address_aux p const
      with Simplify ->
        CpDocument.print (Print.pp_constant const);
        raise (Partial (complete p))
end
