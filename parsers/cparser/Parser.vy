%{

Require Import Cabs0.
Require Import List.

%}

%token<atom * cabsloc> VAR_NAME TYPEDEF_NAME OTHER_NAME
%token<constant * cabsloc> CONSTANT
%token<cabsloc> SIZEOF ALIGNOF PTR INC DEC LEFT RIGHT LEQ GEQ EQEQ EQ NEQ LT GT
  ANDAND BARBAR PLUS MINUS STAR TILDE BANG SLASH PERCENT HAT BAR QUESTION
  COLON AND

%token<cabsloc> MUL_ASSIGN DIV_ASSIGN MOD_ASSIGN ADD_ASSIGN SUB_ASSIGN
  LEFT_ASSIGN RIGHT_ASSIGN AND_ASSIGN XOR_ASSIGN OR_ASSIGN

%token<cabsloc> LPAREN RPAREN LBRACK RBRACK LBRACE RBRACE DOT COMMA
  SEMICOLON ELLIPSIS TYPEDEF EXTERN STATIC RESTRICT AUTO THREAD_LOCAL REGISTER INLINE
  CHAR SHORT INT LONG SIGNED UNSIGNED FLOAT DOUBLE CONST VOLATILE ATOMIC VOID STRUCT
  UNION ENUM BOOL LBRACES BARES RBRACES

%token<cabsloc> CASE DEFAULT IF ELSE SWITCH WHILE DO FOR GOTO CONTINUE BREAK
  RETURN BUILTIN_VA_ARG OFFSETOF

%token<cabsloc> C11_ATOMIC_INIT C11_ATOMIC_STORE C11_ATOMIC_LOAD
  C11_ATOMIC_EXCHANGE C11_ATOMIC_COMPARE_EXCHANGE_STRONG C11_ATOMIC_COMPARE_EXCHANGE_WEAK
  C11_ATOMIC_FETCH_KEY

%token EOF

%type<expression * cabsloc> primary_expression atomic_operation postfix_expression
  unary_expression cast_expression multiplicative_expression additive_expression
  shift_expression relational_expression equality_expression AND_expression
  exclusive_OR_expression inclusive_OR_expression logical_AND_expression
  logical_OR_expression conditional_expression assignment_expression
  constant_expression expression
%type<unary_operator * cabsloc> unary_operator
%type<binary_operator> assignment_operator
%type<list expression (* Reverse order *)> argument_expression_list
%type<definition> declaration
%type<list spec_elem * cabsloc> declaration_specifiers
%type<list init_name (* Reverse order *)> init_declarator_list
%type<init_name> init_declarator
%type<storage * cabsloc> storage_class_specifier
%type<typeSpecifier * cabsloc> type_specifier struct_or_union_specifier enum_specifier
%type<typeSpecifier * cabsloc> atomic_type_specifier
%type<(option atom -> option (list field_group) -> list attribute -> typeSpecifier) * cabsloc> struct_or_union
%type<list field_group (* Reverse order *)> struct_declaration_list
%type<field_group> struct_declaration
%type<list spec_elem * cabsloc> specifier_qualifier_list
%type<list (option name * option expression) (* Reverse order *)> struct_declarator_list
%type<option name * option expression> struct_declarator
%type<list (atom * option expression * cabsloc) (* Reverse order *)> enumerator_list
%type<atom * option expression * cabsloc> enumerator
%type<atom * cabsloc> enumeration_constant
%type<cvspec * cabsloc> type_qualifier
%type<cabsloc> function_specifier
%type<name> declarator direct_declarator
%type<(decl_type -> decl_type) * cabsloc> pointer
%type<list cvspec (* Reverse order *)> type_qualifier_list
%type<list parameter * bool> parameter_type_list
%type<list parameter (* Reverse order *)> parameter_list
%type<parameter> parameter_declaration
%type<list spec_elem * decl_type> type_name
%type<decl_type> abstract_declarator direct_abstract_declarator
%type<init_expression> c_initializer
%type<list (list initwhat * init_expression) (* Reverse order *)> initializer_list
%type<list initwhat> designation
%type<list initwhat (* Reverse order *)> designator_list
%type<initwhat> designator
%type<statement> statement_dangerous statement_safe 
  labeled_statement(statement_safe) labeled_statement(statement_dangerous)
  iteration_statement(statement_safe) iteration_statement(statement_dangerous)
  compound_statement
%type<list statement (* Reverse order *)> block_item_list
%type<statement> block_item expression_statement selection_statement_dangerous
  selection_statement_safe jump_statement
%type<list definition (* Reverse order *)> translation_unit
%type<definition> external_declaration function_definition

%type<statement>par_statement
%type<list statement>par_statement_list



%start<list definition> translation_unit_file
%%

(* Actual grammar *)

(* 6.5.1 *)
primary_expression:
| var = VAR_NAME
    { (VARIABLE (fst var), snd var) }
| cst = CONSTANT
    { (CONSTANT (fst cst), snd cst) }
| loc = LPAREN expr = expression RPAREN
    { (fst expr, loc)}


(* NOTE: this is not present in the actual C11 syntax *)
atomic_operation:
| loc = C11_ATOMIC_INIT LPAREN obj = postfix_expression COMMA value = postfix_expression RPAREN
    { (C11_ATOMIC_INIT (fst obj) (fst value), loc) }
| loc = C11_ATOMIC_STORE LPAREN object_ = postfix_expression COMMA desired = postfix_expression COMMA order = postfix_expression RPAREN
    { (C11_ATOMIC_STORE (fst object_) (fst desired) (fst order), loc) }
| loc = C11_ATOMIC_LOAD LPAREN object_ = postfix_expression COMMA order = postfix_expression RPAREN
    { (C11_ATOMIC_LOAD (fst object_) (fst order), loc) }
| loc = C11_ATOMIC_EXCHANGE LPAREN object_ = postfix_expression COMMA desired = postfix_expression COMMA order = postfix_expression RPAREN
    { (C11_ATOMIC_EXCHANGE (fst object_) (fst desired) (fst order), loc) }
| loc = C11_ATOMIC_COMPARE_EXCHANGE_STRONG LPAREN object_ = postfix_expression COMMA expected = postfix_expression COMMA
  desired = postfix_expression COMMA success = postfix_expression COMMA failure = postfix_expression RPAREN
    { (C11_ATOMIC_COMPARE_EXCHANGE_STRONG (fst object_) (fst expected) (fst desired) (fst success) (fst failure), loc) }
| loc = C11_ATOMIC_COMPARE_EXCHANGE_WEAK LPAREN object_ = postfix_expression COMMA expected = postfix_expression COMMA
  desired = postfix_expression COMMA success = postfix_expression COMMA failure = postfix_expression RPAREN
    { (C11_ATOMIC_COMPARE_EXCHANGE_WEAK (fst object_) (fst expected) (fst desired) (fst success) (fst failure), loc) }


(* 6.5.2 *)
postfix_expression:
| expr = primary_expression
    { expr }
| expr = postfix_expression LBRACK index = expression RBRACK
    { (INDEX (fst expr) (fst index), snd expr) }
(* NOTE: we extend the syntax with builtin C11 atomic operation (the way clang does) *)
| expr = atomic_operation
    { expr }

| expr = postfix_expression LPAREN args = argument_expression_list RPAREN
    { (CALL (fst expr) (rev args), snd expr) }
| expr = postfix_expression LPAREN RPAREN
    { (CALL (fst expr) [], snd expr) }
| loc = BUILTIN_VA_ARG LPAREN expr = assignment_expression COMMA ty = type_name RPAREN
    { (BUILTIN_VA_ARG (fst expr) ty, loc) }
| expr = postfix_expression DOT mem = OTHER_NAME
    { (MEMBEROF (fst expr) (fst mem), snd expr) }
| expr = postfix_expression PTR mem = OTHER_NAME
    { (MEMBEROFPTR (fst expr) (fst mem), snd expr) }
| expr = postfix_expression INC
    { (UNARY POSINCR (fst expr), snd expr) }
| expr = postfix_expression DEC
    { (UNARY POSDECR (fst expr), snd expr) }
| loc = LPAREN typ = type_name RPAREN LBRACE init = initializer_list RBRACE
    { (CAST typ (COMPOUND_INIT (rev init)), loc) }
| loc = LPAREN typ = type_name RPAREN LBRACE init = initializer_list COMMA RBRACE
    { (CAST typ (COMPOUND_INIT (rev init)), loc) }

(* Semantic value is in reverse order. *)
argument_expression_list:
| expr = assignment_expression
    { [fst expr] }
| exprq = argument_expression_list COMMA exprt = assignment_expression
    { fst exprt::exprq }

(* 6.5.3 *)
unary_expression:
| expr = postfix_expression
    { expr }
| loc = INC expr = unary_expression
    { (UNARY PREINCR (fst expr), loc) }
| loc = DEC expr = unary_expression
    { (UNARY PREDECR (fst expr), loc) }
| op = unary_operator expr = cast_expression
    { (UNARY (fst op) (fst expr), snd op) }
| loc = SIZEOF expr = unary_expression
    { (EXPR_SIZEOF (fst expr), loc) }
| loc = SIZEOF LPAREN typ = type_name RPAREN
    { (TYPE_SIZEOF typ, loc) }
| loc = ALIGNOF LPAREN typ = type_name RPAREN
    { (ALIGNOF typ, loc) }
(* K: in truth this is a macro, but we fake it *)
| loc = OFFSETOF LPAREN ty = type_name COMMA member = OTHER_NAME RPAREN
    { (OFFSETOF ty (fst member), loc) }


unary_operator:
| loc = AND
    { (ADDROF, loc) }
| loc = STAR
    { (MEMOF, loc) } 
| loc = PLUS
    { (PLUS, loc) }
| loc = MINUS
    { (MINUS, loc) }
| loc = TILDE
    { (BNOT, loc) }
| loc = BANG
    { (NOT, loc) }

(* 6.5.4 *)
cast_expression:
| expr = unary_expression
    { expr }
| loc = LPAREN typ = type_name RPAREN expr = cast_expression
    { (CAST typ (SINGLE_INIT (fst expr)), loc) }

(* 6.5.5 *)
multiplicative_expression:
| expr = cast_expression
    { expr }
| expr1 = multiplicative_expression STAR expr2 = cast_expression
    { (BINARY MUL (fst expr1) (fst expr2), snd expr1) }
| expr1 = multiplicative_expression SLASH expr2 = cast_expression
    { (BINARY DIV (fst expr1) (fst expr2), snd expr1) }
| expr1 = multiplicative_expression PERCENT expr2 = cast_expression
    { (BINARY MOD (fst expr1) (fst expr2), snd expr1) }

(* 6.5.6 *)
additive_expression:
| expr = multiplicative_expression
    { expr }
| expr1 = additive_expression PLUS expr2 = multiplicative_expression
    { (BINARY ADD (fst expr1) (fst expr2), snd expr1) }
| expr1 = additive_expression MINUS expr2 = multiplicative_expression
    { (BINARY SUB (fst expr1) (fst expr2), snd expr1) }

(* 6.5.7 *)
shift_expression:
| expr = additive_expression
    { expr }
| expr1 = shift_expression LEFT expr2 = additive_expression
    { (BINARY SHL (fst expr1) (fst expr2), snd expr1) }
| expr1 = shift_expression RIGHT expr2 = additive_expression
    { (BINARY SHR (fst expr1) (fst expr2), snd expr1) }

(* 6.5.8 *)
relational_expression:
| expr = shift_expression
    { expr }
| expr1 = relational_expression LT expr2 = shift_expression
    { (BINARY LT (fst expr1) (fst expr2), snd expr1) }
| expr1 = relational_expression GT expr2 = shift_expression
    { (BINARY GT (fst expr1) (fst expr2), snd expr1) }
| expr1 = relational_expression LEQ expr2 = shift_expression
    { (BINARY LE (fst expr1) (fst expr2), snd expr1) }
| expr1 = relational_expression GEQ expr2 = shift_expression
    { (BINARY GE (fst expr1) (fst expr2), snd expr1) }

(* 6.5.9 *)
equality_expression:
| expr = relational_expression
    { expr }
| expr1 = equality_expression EQEQ expr2 = relational_expression
    { (BINARY EQ (fst expr1) (fst expr2), snd expr1) }
| expr1 = equality_expression NEQ expr2 = relational_expression
    { (BINARY NE (fst expr1) (fst expr2), snd expr1) }

(* 6.5.10 *)
AND_expression:
| expr = equality_expression
    { expr }
| expr1 = AND_expression AND expr2 = equality_expression
    { (BINARY BAND (fst expr1) (fst expr2), snd expr1) }

(* 6.5.11 *)
exclusive_OR_expression:
| expr = AND_expression
    { expr }
| expr1 = exclusive_OR_expression HAT expr2 = AND_expression
    { (BINARY XOR (fst expr1) (fst expr2), snd expr1) }

(* 6.5.12 *)
inclusive_OR_expression:
| expr = exclusive_OR_expression
    { expr }
| expr1 = inclusive_OR_expression BAR expr2 = exclusive_OR_expression
    { (BINARY BOR (fst expr1) (fst expr2), snd expr1) }

(* 6.5.13 *)
logical_AND_expression:
| expr = inclusive_OR_expression
    { expr }
| expr1 = logical_AND_expression ANDAND expr2 = inclusive_OR_expression
    { (BINARY AND (fst expr1) (fst expr2), snd expr1) }

(* 6.5.14 *)
logical_OR_expression:
| expr = logical_AND_expression
    { expr }
| expr1 = logical_OR_expression BARBAR expr2 = logical_AND_expression
    { (BINARY OR (fst expr1) (fst expr2), snd expr1) }

(* 6.5.15 *)
conditional_expression:
| expr = logical_OR_expression
    { expr }
| expr1 = logical_OR_expression QUESTION expr2 = expression COLON expr3 = conditional_expression
    { (QUESTION (fst expr1) (fst expr2) (fst expr3), snd expr1) }

(* 6.5.16 *)
assignment_expression:
| expr = conditional_expression
    { expr }
| expr1 = unary_expression op = assignment_operator expr2 = assignment_expression
    { (BINARY op (fst expr1) (fst expr2), snd expr1) }

assignment_operator:
| EQ
    { ASSIGN  }
| MUL_ASSIGN
    { MUL_ASSIGN }
| DIV_ASSIGN
    { DIV_ASSIGN }
| MOD_ASSIGN
    { MOD_ASSIGN }
| ADD_ASSIGN
    { ADD_ASSIGN }
| SUB_ASSIGN
    { SUB_ASSIGN }
| LEFT_ASSIGN
    { SHL_ASSIGN }
| RIGHT_ASSIGN
    { SHR_ASSIGN }
| XOR_ASSIGN
    { XOR_ASSIGN }
| OR_ASSIGN
    { BOR_ASSIGN }
| AND_ASSIGN
    { BAND_ASSIGN }

(* 6.5.17 *)
expression:
| expr = assignment_expression
    { expr }
| expr1 = expression COMMA expr2 = assignment_expression
    { (BINARY COMMA (fst expr1) (fst expr2), snd expr1) }


(* 6.6 *)
constant_expression:
| expr = conditional_expression
    { expr }

(* 6.7 *)
declaration:
| decspec = declaration_specifiers decls = init_declarator_list SEMICOLON
    { DECDEF (fst decspec, rev decls) (snd decspec) }
| decspec = declaration_specifiers SEMICOLON
    { DECDEF (fst decspec, []) (snd decspec) }
(* TODO
| static_assert_declaration
    {}
*)


declaration_specifiers:
| storage = storage_class_specifier rest = declaration_specifiers
    { (SpecStorage (fst storage)::fst rest, snd storage) }
| storage = storage_class_specifier
    { ([SpecStorage (fst storage)], snd storage) }
| typ = type_specifier rest = declaration_specifiers
    { (SpecType (fst typ)::fst rest, snd typ) }
| typ = type_specifier
    { ([SpecType (fst typ)], snd typ) }
| qual = type_qualifier rest = declaration_specifiers
    { (SpecCV (fst qual)::fst rest, snd qual) }
| qual = type_qualifier
    { ([SpecCV (fst qual)], snd qual) }
| loc = function_specifier rest = declaration_specifiers
    { (SpecInline::fst rest, loc) }
| loc = function_specifier
    { ([SpecInline], loc) }

init_declarator_list:
| init = init_declarator
    { [init] }
| initq = init_declarator_list COMMA initt = init_declarator
    { initt::initq }

init_declarator:
| name = declarator
    { Init_name name NO_INIT }
| name = declarator EQ init = c_initializer
    { Init_name name init }

(* 6.7.1 *)
storage_class_specifier:
| loc = TYPEDEF
    { (TYPEDEF, loc) }
| loc = EXTERN
    { (EXTERN, loc) }
| loc = STATIC
    { (STATIC, loc) }
| loc = AUTO
    { (AUTO, loc) } 
| loc = THREAD_LOCAL
    { (THREAD_LOCAL, loc) } 
| loc = REGISTER
    { (REGISTER, loc) }

(* 6.7.2 *)
type_specifier:
| loc = VOID
    { (Tvoid, loc) }
| loc = CHAR
    { (Tchar, loc) }
| loc = SHORT
    { (Tshort, loc) }
| loc = INT
    { (Tint, loc) }
| loc = LONG
    { (Tlong, loc) }
| loc = FLOAT
    { (Tfloat, loc) }
| loc = DOUBLE
    { (Tdouble, loc) }
| loc = SIGNED
    { (Tsigned, loc) }
| loc = UNSIGNED
    { (Tunsigned, loc) }
| loc = BOOL
    { (T_Bool, loc) }
| spec = atomic_type_specifier
    { spec }
| spec = struct_or_union_specifier
    { spec }
| spec = enum_specifier
    { spec }
| id = TYPEDEF_NAME
    { (Tnamed (fst id), snd id) }

(* 6.7.2.1 *)
struct_or_union_specifier:
| str_uni = struct_or_union id = OTHER_NAME LBRACE decls = struct_declaration_list RBRACE
    { ((fst str_uni) (Some (fst id)) (Some (rev decls)) [], snd str_uni) }
| str_uni = struct_or_union LBRACE decls = struct_declaration_list RBRACE
    { ((fst str_uni) None (Some (rev decls)) [],            snd str_uni) }
| str_uni = struct_or_union id = OTHER_NAME
    { ((fst str_uni) (Some (fst id)) None [],         snd str_uni) }

struct_or_union:
| loc = STRUCT
    { (Tstruct, loc) }
| loc = UNION
    { (Tunion, loc) }

struct_declaration_list:
| decl = struct_declaration
    { [decl] }
| qdecls = struct_declaration_list tdecls = struct_declaration
    { tdecls::qdecls }

struct_declaration:
| decspec = specifier_qualifier_list decls = struct_declarator_list SEMICOLON
    { Field_group (fst decspec) (rev decls) (snd decspec) }
(* Extension to C99 grammar needed to parse some GNU header files. *)
| decspec = specifier_qualifier_list SEMICOLON
    { Field_group (fst decspec) [] (snd decspec) }
(* TODO
| static_assert_declaration
    {}
*)

(* 6.7.2.4 *)
atomic_type_specifier:
| loc = ATOMIC LPAREN ty = type_name RPAREN
    { (Tatomic ty, loc) }

specifier_qualifier_list:
| typ = type_specifier rest = specifier_qualifier_list
    { (SpecType (fst typ)::fst rest, snd typ) }
| typ = type_specifier
    { ([SpecType (fst typ)], snd typ) }
| qual = type_qualifier rest = specifier_qualifier_list
    { (SpecCV (fst qual)::fst rest, snd qual) }
| qual = type_qualifier
    { ([SpecCV (fst qual)], snd qual) }

struct_declarator_list:
| decl = struct_declarator
    { [decl] }
| declq = struct_declarator_list COMMA declt = struct_declarator
    { declt::declq }

struct_declarator:
| decl = declarator
    { (Some decl, None) }
| decl = declarator COLON expr = constant_expression
    { (Some decl, Some (fst expr)) }
| COLON expr = constant_expression
    { (None, Some (fst expr)) }

(* 6.7.2.2 *)
enum_specifier:
| loc = ENUM name = OTHER_NAME LBRACE enum_list = enumerator_list RBRACE
    { (Tenum (Some (fst name)) (Some (rev enum_list)) [], loc) }
| loc = ENUM LBRACE enum_list = enumerator_list RBRACE
    { (Tenum None (Some (rev enum_list)) [], loc) }
| loc = ENUM name = OTHER_NAME LBRACE enum_list = enumerator_list COMMA RBRACE
    { (Tenum (Some (fst name)) (Some (rev enum_list)) [], loc) }
| loc = ENUM LBRACE enum_list = enumerator_list COMMA RBRACE
    { (Tenum None (Some (rev enum_list)) [], loc) }
| loc = ENUM name = OTHER_NAME
    { (Tenum (Some (fst name)) None [], loc) }

enumerator_list:
| enum = enumerator
    { [enum] }
| enumsq = enumerator_list COMMA enumst = enumerator
    { enumst::enumsq }

enumerator:
| atom = enumeration_constant
    { (fst atom, None, snd atom) }
| atom = enumeration_constant EQ expr = constant_expression
    { (fst atom, Some (fst expr), snd atom) }

enumeration_constant:
| loc = VAR_NAME
    { loc }

(* 6.7.3 *)
type_qualifier:
| loc = CONST
    { (CV_CONST, loc) }
| loc = RESTRICT
    { (CV_RESTRICT, loc) }
| loc = VOLATILE
    { (CV_VOLATILE, loc) }
| loc = ATOMIC
    { (CV_ATOMIC, loc) }

(* 6.7.4 *)
function_specifier:
| loc = INLINE
    { loc }

(* 6.7.5 *)
declarator:
| decl = direct_declarator
    { decl }
| pt = pointer decl = direct_declarator
    { match decl with Name name typ attr _ => 
	Name name ((fst pt) typ) attr (snd pt) end }

direct_declarator:
| id = VAR_NAME
    { Name (fst id) JUSTBASE [] (snd id) }
| LPAREN decl = declarator RPAREN
    { decl }
| decl = direct_declarator LBRACK quallst = type_qualifier_list expr = assignment_expression RBRACK
    { match decl with Name name typ attr loc =>
	Name name (ARRAY typ (rev quallst) [] (Some (fst expr))) attr loc end }
| decl = direct_declarator LBRACK expr = assignment_expression RBRACK
    { match decl with Name name typ attr loc =>
	Name name (ARRAY typ [] [] (Some (fst expr))) attr loc end }
| decl = direct_declarator LBRACK quallst = type_qualifier_list RBRACK
    { match decl with Name name typ attr loc =>
	Name name (ARRAY typ (rev quallst) [] None) attr loc end }
| decl = direct_declarator LBRACK RBRACK
    { match decl with Name name typ attr loc =>
	Name name (ARRAY typ [] [] None) attr loc end }
(*| direct_declarator LBRACK ... STATIC ... RBRACK
| direct_declarator LBRACK STAR RBRACK*)
| decl = direct_declarator LPAREN params = parameter_type_list RPAREN
    { match decl with Name name typ attr loc =>
	Name name (PROTO typ params) attr loc end }
| decl = direct_declarator LPAREN RPAREN
    { match decl with Name name typ attr loc =>
        Name name (PROTO typ ([],false)) attr loc end }
(* TODO : K&R *)
(*| direct_declarator LPAREN identifier_list RPAREN
    {}*)

pointer:
| loc = STAR
    { (PTR [] [], loc) }
| loc = STAR quallst = type_qualifier_list
    { (PTR (rev quallst) [], loc) }
| loc = STAR pt = pointer
    { (fun typ => PTR [] [] ((fst pt) typ), loc) }
| loc = STAR quallst = type_qualifier_list pt = pointer
    { (fun typ => PTR (rev quallst) [] ((fst pt) typ), loc) }

type_qualifier_list:
| qual = type_qualifier
    { [fst qual] }
| qualq = type_qualifier_list qualt = type_qualifier
    { fst qualt::qualq }

parameter_type_list:
| lst = parameter_list
    { (rev lst, false) }
| lst = parameter_list COMMA ELLIPSIS
    { (rev lst, true) }

parameter_list:
| param = parameter_declaration
    { [param] }
| paramq = parameter_list COMMA paramt = parameter_declaration
    { paramt::paramq }

parameter_declaration:
| specs = declaration_specifiers decl = declarator
    { match decl with Name name typ attr _ =>
        PARAM (fst specs) (Some name) typ attr (snd specs) end }
| specs = declaration_specifiers decl = abstract_declarator
    { PARAM (fst specs) None decl [] (snd specs) }
| specs = declaration_specifiers
    { PARAM (fst specs) None JUSTBASE [] (snd specs) }

(* TODO : K&R *)
(*
identifier_list:
| VAR_NAME
| identifier_list COMMA idt = VAR_NAME
    {}
*)

(* 6.7.6 *)
type_name:
| specqual = specifier_qualifier_list
    { (fst specqual, JUSTBASE) }
| specqual = specifier_qualifier_list typ = abstract_declarator
    { (fst specqual, typ) }

abstract_declarator:
| pt = pointer
    { (fst pt) JUSTBASE }
| pt = pointer typ = direct_abstract_declarator
    { (fst pt) typ }
| typ = direct_abstract_declarator
    { typ }

direct_abstract_declarator:
| LPAREN typ = abstract_declarator RPAREN
    { typ }
| typ = direct_abstract_declarator LBRACK cvspec = type_qualifier_list expr = assignment_expression RBRACK
    { ARRAY typ cvspec [] (Some (fst expr)) }
| LBRACK cvspec = type_qualifier_list expr = assignment_expression RBRACK
    { ARRAY JUSTBASE cvspec [] (Some (fst expr)) }
| typ = direct_abstract_declarator LBRACK expr = assignment_expression RBRACK
    { ARRAY typ [] [] (Some (fst expr)) }
| LBRACK expr = assignment_expression RBRACK
    { ARRAY JUSTBASE [] [] (Some (fst expr)) }
| typ = direct_abstract_declarator LBRACK cvspec = type_qualifier_list RBRACK
    { ARRAY typ cvspec [] None }
| LBRACK cvspec = type_qualifier_list RBRACK
    { ARRAY JUSTBASE cvspec [] None }
| typ = direct_abstract_declarator LBRACK RBRACK
    { ARRAY typ [] [] None }
| LBRACK RBRACK
    { ARRAY JUSTBASE [] [] None }
(*| direct_abstract_declarator? LBRACK STAR RBRACK*)
(*| direct_abstract_declarator? LBRACK ... STATIC ... RBRACK*)
| typ = direct_abstract_declarator LPAREN params = parameter_type_list RPAREN
    { PROTO typ params }
| LPAREN params = parameter_type_list RPAREN
    { PROTO JUSTBASE params }
| typ = direct_abstract_declarator LPAREN RPAREN
    { PROTO typ ([], false) }
| LPAREN RPAREN
    { PROTO JUSTBASE ([], false) }

(* 6.7.8 *)
c_initializer:
| expr = assignment_expression
    { SINGLE_INIT (fst expr) }
| LBRACE init = initializer_list RBRACE
    { COMPOUND_INIT (rev init) }
| LBRACE init = initializer_list COMMA RBRACE
    { COMPOUND_INIT (rev init) }

initializer_list:
| design = designation init = c_initializer
    { [(design, init)] }
| init = c_initializer
    { [([], init)] }
| initq = initializer_list COMMA design = designation init = c_initializer
    { (design, init)::initq }
| initq = initializer_list COMMA init = c_initializer
    { ([], init)::initq }

designation:
| design = designator_list EQ
    { rev design }

designator_list:
| design = designator
    { [design] }
| designq = designator_list designt = designator
    { designt::designq }

designator:
| LBRACK expr = constant_expression RBRACK
    { ATINDEX_INIT (fst expr) }
| DOT id = OTHER_NAME
    { INFIELD_INIT (fst id) }

(* 6.8 *)
statement_dangerous:
| stmt = labeled_statement(statement_dangerous)
| stmt = compound_statement
| stmt = expression_statement
| stmt = selection_statement_dangerous
| stmt = iteration_statement(statement_dangerous)
| stmt = jump_statement
| stmt = par_statement
    { stmt }

statement_safe:
| stmt = labeled_statement(statement_safe)
| stmt = compound_statement
| stmt = expression_statement
| stmt = selection_statement_safe
| stmt = iteration_statement(statement_safe)
| stmt = jump_statement
| stmt = par_statement
    { stmt }

(* 6.8.1 *)
labeled_statement(last_statement):
| lbl = OTHER_NAME COLON stmt = last_statement
    { LABEL (fst lbl) stmt (snd lbl) }
| loc = CASE expr = constant_expression COLON stmt = last_statement
    { CASE (fst expr) stmt loc }
| loc = DEFAULT COLON stmt = last_statement
    { DEFAULT stmt loc }

(* 6.8.2 *)
compound_statement:
| loc = LBRACE lst = block_item_list RBRACE
    { BLOCK (rev lst) loc }
| loc = LBRACE RBRACE
    { BLOCK [] loc }

block_item_list:
| stmt = block_item
    { [stmt] }
| stmtq = block_item_list stmtt = block_item
    { stmtt::stmtq }

block_item:
| decl = declaration
    { DEFINITION decl }
| stmt = statement_dangerous
    { stmt }

(* 6.8.3 *)
expression_statement:
| expr = expression SEMICOLON
    { COMPUTATION (fst expr) (snd expr) }
| loc = SEMICOLON
    { NOP loc }

(* 6.8.4 *)
selection_statement_dangerous:
| loc = IF LPAREN expr = expression RPAREN stmt = statement_dangerous
    { If0 (fst expr) stmt None loc }
| loc = IF LPAREN expr = expression RPAREN stmt1 = statement_safe ELSE stmt2 = statement_dangerous
    { If0 (fst expr) stmt1 (Some stmt2) loc }
| loc = SWITCH LPAREN expr = expression RPAREN stmt = statement_dangerous
    { SWITCH (fst expr) stmt loc }

selection_statement_safe:
| loc = IF LPAREN expr = expression RPAREN stmt1 = statement_safe ELSE stmt2 = statement_safe
    { If0 (fst expr) stmt1 (Some stmt2) loc }
| loc = SWITCH LPAREN expr = expression RPAREN stmt = statement_safe
    { SWITCH (fst expr) stmt loc }

(* 6.8.5 *)
iteration_statement(last_statement):
| loc = WHILE LPAREN expr = expression RPAREN stmt = last_statement
    { WHILE (fst expr) stmt loc }
| loc = DO stmt = statement_dangerous WHILE LPAREN expr = expression RPAREN SEMICOLON
    { DOWHILE (fst expr) stmt loc }
| loc = FOR LPAREN expr1 = expression SEMICOLON expr2 = expression SEMICOLON expr3 = expression RPAREN stmt = last_statement
    { FOR (Some (FC_EXP (fst expr1))) (Some (fst expr2)) (Some (fst expr3)) stmt loc }
| loc = FOR LPAREN decl1 = declaration expr2 = expression SEMICOLON expr3 = expression RPAREN stmt = last_statement
    { FOR (Some (FC_DECL decl1)) (Some (fst expr2)) (Some (fst expr3)) stmt loc }
| loc = FOR LPAREN SEMICOLON expr2 = expression SEMICOLON expr3 = expression RPAREN stmt = last_statement
    { FOR None (Some (fst expr2)) (Some (fst expr3)) stmt loc }
| loc = FOR LPAREN expr1 = expression SEMICOLON SEMICOLON expr3 = expression RPAREN stmt = last_statement
    { FOR (Some (FC_EXP (fst expr1))) None (Some (fst expr3)) stmt loc }
| loc = FOR LPAREN decl1 = declaration SEMICOLON expr3 = expression RPAREN stmt = last_statement
    { FOR (Some (FC_DECL decl1)) None (Some (fst expr3)) stmt loc }
| loc = FOR LPAREN SEMICOLON SEMICOLON expr3 = expression RPAREN stmt = last_statement
    { FOR None None (Some (fst expr3)) stmt loc }
| loc = FOR LPAREN expr1 = expression SEMICOLON expr2 = expression SEMICOLON RPAREN stmt = last_statement
    { FOR (Some (FC_EXP (fst expr1))) (Some (fst expr2)) None stmt loc }
| loc = FOR LPAREN decl1 = declaration expr2 = expression SEMICOLON RPAREN stmt = last_statement
    { FOR (Some (FC_DECL decl1)) (Some (fst expr2)) None stmt loc }
| loc = FOR LPAREN SEMICOLON expr2 = expression SEMICOLON RPAREN stmt = last_statement
    { FOR None (Some (fst expr2)) None stmt loc }
| loc = FOR LPAREN expr1 = expression SEMICOLON SEMICOLON RPAREN stmt = last_statement
    { FOR (Some (FC_EXP (fst expr1))) None None stmt loc }
| loc = FOR LPAREN decl1 = declaration SEMICOLON RPAREN stmt = last_statement
    { FOR (Some (FC_DECL decl1)) None None stmt loc }
| loc = FOR LPAREN SEMICOLON SEMICOLON RPAREN stmt = last_statement
    { FOR None None None stmt loc }

(* 6.8.6 *)
jump_statement:
| loc = GOTO id = OTHER_NAME SEMICOLON
    { GOTO (fst id) loc }
| loc = CONTINUE SEMICOLON
    { CONTINUE loc }
| loc = BREAK SEMICOLON
    { BREAK loc }
| loc = RETURN expr = expression SEMICOLON
    { RETURN (Some (fst expr)) loc }
| loc = RETURN SEMICOLON
    { RETURN None loc }

(* TODO[non-standard] cppmem thread notation *)
par_statement:
| loc = LBRACES ss = par_statement_list RBRACES
    { PAR ss loc }

par_statement_list:
| s = statement_dangerous
    { [s] }
| s = statement_dangerous BARES ss = par_statement_list
    { s :: ss }


(* 6.9 *)
translation_unit_file:
| lst = translation_unit EOF
    { rev lst }

translation_unit:
| def = external_declaration
    { [def] }
| defq = translation_unit deft = external_declaration
    { deft::defq }

external_declaration:
| def = function_definition
| def = declaration
    { def }

(* 6.9.1 *)
function_definition:
(* TODO : K&R *)
(*| declaration_specifiers declarator declaration_list compound_statement
    {}*)
| specs = declaration_specifiers decl = declarator stmt = compound_statement
    { FUNDEF (fst specs) decl stmt (snd specs) }

(* TODO : K&R 
declaration_list:
| declaration
| declaration_list declaration
    {}
*)
