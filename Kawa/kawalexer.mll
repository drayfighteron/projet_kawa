{
  open Lexing
  open Kawaparser

  exception Error of string

  (* Gestion des mots-clés : on associe des chaînes à des tokens.
     Si la chaîne n'est pas un mot-clé connu, on renvoie IDENT(s). *)
  let keyword_or_ident =
    let h = Hashtbl.create 17 in
    List.iter (fun (s, k) -> Hashtbl.add h s k)
      [ "print",    PRINT;
        "main",     MAIN;
        "class",    CLASS;
        "extends",  EXTENDS;
        "var",      VAR;
        "attribute",ATTRIBUTE;
        "method",   METHOD;
        "int",      INT_T;
        "bool",     BOOL_T;
        "void",     VOID_T;
        "if",       IF;
        "else",     ELSE;
        "while",    WHILE;
        "return",   RETURN;
        "new",      NEW;
        "this",     THIS;
        "true",     TRUE;
        "false",    FALSE
      ];
    fun s ->
      try Hashtbl.find h s
      with Not_found -> IDENT(s)
}

(* Définitions de motifs pour les chiffres et les identifiants. *)
let digit  = ['0'-'9']
let alpha  = ['a'-'z' 'A'-'Z']
let ident  = [ 'a'-'z' 'A'-'Z' '_' ] [ 'a'-'z' 'A'-'Z' '0'-'9' '_' ]*

(** 
  Règle principale : on ignore les espaces et commentaires,
  on renvoie un token pour chaque lexème reconnu.
**)
rule token = parse
  (* --- Sauts de ligne (mise à jour de position) --- *)
  | ['\n'] {
      new_line lexbuf; 
      token lexbuf
    }

  (* --- Espaces blancs multiples --- *)
  | [ ' ' '\t' '\r' ]+ {
      token lexbuf
    }

  (* --- Commentaires "ligne" style // --- *)
  | "//" [^ '\n']* {
      token lexbuf
    }

  (* --- Commentaires "bloc" style /* ... */ --- *)
  | "/*" {
      comment lexbuf;
      token lexbuf
    }

  (* --- Constantes entières (positives ou négatives) --- *)
  | ['-']? digit+ as n {
      try
        INT(int_of_string n)
      with Failure _ ->
        raise (Error ("invalid int literal: " ^ n))
    }

  (* --- Identifiants ou mots-clés --- *)
  | ident as id {
      keyword_or_ident id
    }

  (* --- Opérateurs binaires / unaires, symboles ponctuels, etc. --- *)
  | "=="  { EQEQ }
  | "!="  { NEQ }
  | "<="  { LE }
  | "<"   { LT }
  | "&&"  { AND }
  | "||"  { OR }
  | "+"   { PLUS }
  | "-"   { MINUS }
  | "*"   { STAR }
  | "/"   { SLASH }
  | "%"   { PERCENT }
  | "="   { EQ }

  (* -- ICI : ajout pour "!" -> BANG -- *)
  | "!"   { BANG }

  (* --- Parenthèses, accolades, etc. --- *)
  | "("   { LPAR }
  | ")"   { RPAR }
  | "{"   { BEGIN }
  | "}"   { END }
  | ";"   { SEMI }
  | "."   { DOT }
  | ","   { COMMA }

  (* --- Fin de fichier --- *)
  | eof {
      EOF
    }

  (* --- Caractère inconnu --- *)
  | _ as c {
    let s = String.make 1 c in
    raise (Error ("unknown character: " ^ s))
  }


and comment = parse
  (* on s'arrête quand on rencontre "*/" *)
  | "*/"        { () }
  | '\n'        { new_line lexbuf; comment lexbuf }
  | eof         { raise (Error "unterminated comment") }
  (* sinon, on continue de lire la suite du commentaire *)
  | _           { comment lexbuf }
