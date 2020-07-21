(************************************************************************************)
(*  BSD 2-Clause License                                                            *)
(*                                                                                  *)
(*  Cerberus                                                                        *)
(*                                                                                  *)
(*  Copyright (c) 2011-2020                                                         *)
(*    Kayvan Memarian                                                               *)
(*    Victor Gomes                                                                  *)
(*    Justus Matthiesen                                                             *)
(*    Peter Sewell                                                                  *)
(*    Kyndylan Nienhuis                                                             *)
(*    Stella Lau                                                                    *)
(*    Jean Pichon-Pharabod                                                          *)
(*    Christopher Pulte                                                             *)
(*    Rodolphe Lepigre                                                              *)
(*    James Lingard                                                                 *)
(*                                                                                  *)
(*  All rights reserved.                                                            *)
(*                                                                                  *)
(*  Redistribution and use in source and binary forms, with or without              *)
(*  modification, are permitted provided that the following conditions are met:     *)
(*                                                                                  *)
(*  1. Redistributions of source code must retain the above copyright notice, this  *)
(*     list of conditions and the following disclaimer.                             *)
(*                                                                                  *)
(*  2. Redistributions in binary form must reproduce the above copyright notice,    *)
(*     this list of conditions and the following disclaimer in the documentation    *)
(*     and/or other materials provided with the distribution.                       *)
(*                                                                                  *)
(*  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"     *)
(*  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE       *)
(*  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE  *)
(*  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE    *)
(*  FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL      *)
(*  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR      *)
(*  SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER      *)
(*  CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,   *)
(*  OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE   *)
(*  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.            *)
(************************************************************************************)

open Cerb_frontend

(* §6.4 Lexical elements *)
type token =
  | EOF

  (* §6.4.1 Keywords *)
  | AUTO
  | BREAK
  | CASE
  | CHAR
  | CONST
  | CONTINUE
  | DEFAULT
  | DO
  | DOUBLE
  | ELSE
  | ENUM
  | EXTERN
  | FLOAT
  | FOR
  | GOTO
  | IF
  | INLINE
  | INT
  | LONG
  | REGISTER
  | RESTRICT
  | RETURN
  | SHORT
  | SIGNED
  | SIZEOF
  | STATIC
  | STRUCT
  | SWITCH
  | TYPEDEF
  | UNION
  | UNSIGNED
  | VOID
  | VOLATILE
  | WHILE
  | ALIGNAS
  | ALIGNOF
  | ATOMIC
  | BOOL
  | COMPLEX
  | GENERIC
  | IMAGINARY
  | NORETURN
  | STATIC_ASSERT
  | THREAD_LOCAL

  (* §6.4.2 Identifiers *)
  | NAME of string
  | VARIABLE
  | TYPE

  (* §6.4.4 Constants *)
  | CONSTANT of Cabs.cabs_constant

  (* §6.4.5 String Literals *)
  | STRING_LITERAL of Cabs.cabs_string_literal

  (* §6.4.6 Punctuators *)
  | LBRACK
  | RBRACK
  | LPAREN
  | RPAREN
  | LBRACE
  | RBRACE
  | DOT
  | MINUS_GT
  | PLUS_PLUS
  | MINUS_MINUS
  | AMPERSAND
  | STAR
  | PLUS
  | MINUS
  | TILDE
  | BANG
  | SLASH
  | PERCENT
  | LT_LT
  | GT_GT
  | LT
  | GT
  | LT_EQ
  | GT_EQ
  | EQ_EQ
  | BANG_EQ
  | CARET
  | PIPE
  | AMPERSAND_AMPERSAND
  | PIPE_PIPE
  | QUESTION
  | COLON
  | SEMICOLON
  | COLON_COLON
  | ELLIPSIS
  | EQ
  | STAR_EQ
  | SLASH_EQ
  | PERCENT_EQ
  | PLUS_EQ
  | MINUS_EQ
  | LT_LT_EQ
  | GT_GT_EQ
  | AMPERSAND_EQ
  | CARET_EQ
  | PIPE_EQ
  | COMMA
  | LBRACK_LBRACK
  | RBRACK_RBRACK

  (* NON-STD *)
  | ASSERT
  | OFFSETOF
  | LBRACES
  | PIPES
  | RBRACES
  | VA_START
  | VA_COPY
  | VA_ARG
  | VA_END
  | BMC_ASSUME
  | PRINT_TYPE

let string_of_token = function
  | AUTO -> "AUTO"
  | BREAK -> "BREAK"
  | CASE -> "CASE"
  | CHAR -> "CHAR"
  | CONST -> "CONST"
  | CONTINUE -> "CONTINUE"
  | DEFAULT -> "DEFAULT"
  | DO -> "DO"
  | DOUBLE -> "DOUBLE"
  | ELSE -> "ELSE"
  | ENUM -> "ENUM"
  | EXTERN -> "EXTERN"
  | FLOAT -> "FLOAT"
  | FOR -> "FOR"
  | GOTO -> "GOTO"
  | IF -> "IF"
  | INLINE -> "INLINE"
  | INT -> "INT"
  | LONG -> "LONG"
  | REGISTER -> "REGISTER"
  | RESTRICT -> "RESTRICT"
  | RETURN -> "RETURN"
  | SHORT -> "SHORT"
  | SIGNED -> "SIGNED"
  | SIZEOF -> "SIZEOF"
  | STATIC -> "STATIC"
  | STRUCT -> "STRUCT"
  | SWITCH -> "SWITCH"
  | TYPEDEF -> "TYPEDEF"
  | UNION -> "UNION"
  | UNSIGNED -> "UNSIGNED"
  | VOID -> "VOID"
  | VOLATILE -> "VOLATILE"
  | WHILE -> "WHILE"
  | ALIGNAS -> "ALIGNAS"
  | ALIGNOF -> "ALIGNOF"
  | ATOMIC -> "ATOMIC"
  | BOOL -> "BOOL"
  | COMPLEX -> "COMPLEX"
  | GENERIC -> "GENRIC"
  | IMAGINARY -> "IMAGINARY"
  | NORETURN -> "NORETURN"
  | STATIC_ASSERT -> "STATIC_ASSERT"
  | THREAD_LOCAL -> "THREAD_LOCAL"
  | NAME s -> "NAME(" ^ s ^ ")"
  | VARIABLE -> "VARIABLE"
  | TYPE -> "TYPE"
  | CONSTANT _ -> "CONSTANT"
  | STRING_LITERAL _ -> "STRING_LITERAL"
  | LBRACK -> "LBRACK"
  | RBRACK -> "RBRACK"
  | LBRACK_LBRACK -> "LBRACK_LBRACK"
  | RBRACK_RBRACK -> "RBRACK_RBRACK"
  | LPAREN -> "LPAREN"
  | RPAREN -> "RPAREN"
  | LBRACE -> "LBRACE"
  | RBRACE -> "RBRACE"
  | DOT -> "DOT"
  | MINUS_GT -> "MINUS_GT"
  | PLUS_PLUS -> "PLUS_PLUS"
  | MINUS_MINUS -> "MINUS_MINUS"
  | AMPERSAND -> "AMPERSAND"
  | STAR -> "STAR"
  | PLUS -> "PLUS"
  | MINUS -> "MINUS"
  | TILDE -> "TILDE"
  | BANG -> "BANG"
  | SLASH -> "SLASH"
  | PERCENT -> "PERCENT"
  | LT_LT -> "LT_LT"
  | GT_GT -> "GT_GT"
  | LT -> "LT"
  | GT -> "GT"
  | LT_EQ -> "LT_EQ"
  | GT_EQ -> "GT_EQ"
  | EQ_EQ -> "EQ_EQ"
  | BANG_EQ -> "BANG_EQ"
  | CARET -> "CARET"
  | PIPE -> "PIPE"
  | AMPERSAND_AMPERSAND -> "AMPERSAND_AMPERSAND"
  | PIPE_PIPE -> "PIPE_PIE"
  | QUESTION -> "QUESTION"
  | COLON -> "COLON"
  | COLON_COLON -> "COLON_COLON"
  | SEMICOLON -> "SEMICOLON"
  | ELLIPSIS -> "ELLIPSIS"
  | EQ -> "EQ"
  | STAR_EQ -> "STAR_EQ"
  | SLASH_EQ -> "SLASH_EQ"
  | PERCENT_EQ -> "PERCENT_EQ"
  | PLUS_EQ -> "PLUS_EQ"
  | MINUS_EQ -> "MINUS_EQ"
  | LT_LT_EQ -> "LT_LT_EQ"
  | GT_GT_EQ -> "GT_GT_EQ"
  | AMPERSAND_EQ -> "AMPERSAND_EQ"
  | CARET_EQ -> "CARET_EQ"
  | PIPE_EQ -> "PIPE_EQ"
  | COMMA -> "COMMA"
  | ASSERT -> "ASSERT"
  | OFFSETOF -> "OFFSETOF"
  | LBRACES -> "LBRACES"
  | PIPES -> "PIPES"
  | RBRACES -> "RBRACES"
  | VA_START -> "__cerbvar_va_start"
  | VA_ARG -> "__cerbvar_va_arg"
  | VA_COPY -> "__cerbvar_va_copy"
  | VA_END -> "__cerbvar_va_end"
  | BMC_ASSUME -> "__bmc_assume"
  | PRINT_TYPE -> "__cerb_printtype"
  | EOF -> "EOF"
