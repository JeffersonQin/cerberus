open Core

val pp_core_object_type: core_object_type -> PPrint.document
val pp_core_base_type: core_base_type -> PPrint.document
val pp_object_value: object_value -> PPrint.document
val pp_value: value -> PPrint.document
val pp_params: (Symbol.sym * core_base_type) list -> PPrint.document
val pp_pexpr: ('ty, Symbol.sym) generic_pexpr -> PPrint.document
val pp_expr: 'a expr -> PPrint.document
val pp_file: 'a file -> PPrint.document

val pp_stack: 'a stack -> PPrint.document
