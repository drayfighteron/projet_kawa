
(* The type of tokens. *)

type token = 
  | WHILE
  | VOID_T
  | VAR
  | TRUE
  | THIS
  | STAR
  | SLASH
  | SEMI
  | RPAR
  | RETURN
  | PRINT
  | PLUS
  | PERCENT
  | OR
  | NEW
  | NEQ
  | MINUS
  | METHOD
  | MAIN
  | LT
  | LPAR
  | LE
  | INT_T
  | INT of (int)
  | IF
  | IDENT of (string)
  | FALSE
  | EXTENDS
  | EQEQ
  | EQ
  | EOF
  | END
  | ELSE
  | DOT
  | COMMA
  | CLASS
  | BOOL_T
  | BEGIN
  | BANG
  | ATTRIBUTE
  | AND

(* This exception is raised by the monolithic API functions. *)

exception Error

(* The monolithic API. *)

val program: (Lexing.lexbuf -> token) -> Lexing.lexbuf -> (Kawa.program)
