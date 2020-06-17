open Symbol


val to_string: sym -> string
val to_string_pretty: sym -> string

val alt_to_string: sym -> string
val alt_to_string_pretty: sym -> string


val pp_prefix: prefix -> PPrint.document



val pp_identifier: Symbol.identifier -> PPrint.document
