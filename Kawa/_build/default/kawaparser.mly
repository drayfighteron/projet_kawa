%{
  open Kawa

  (* Pour avoir des messages d’erreurs plus lisibles si besoin. *)
  exception ParseError of string
  let parse_error s = raise (ParseError s)
%}

(**************************************************)
(*               Déclarations de tokens           *)
(**************************************************)

%token <int>     INT          (* une constante entière : 42 *)
%token <string>  IDENT        (* un identifiant : toto, Point, etc. *)

%token CLASS EXTENDS VAR ATTRIBUTE METHOD
%token INT_T BOOL_T VOID_T
%token IF ELSE WHILE RETURN PRINT
%token NEW THIS TRUE FALSE
%token MAIN

(* On déclare un nouveau token BANG pour "!" *)
%token BANG

(* Opérateurs et symboles divers *)
%token EQEQ NEQ LE LT AND OR PLUS MINUS STAR SLASH PERCENT EQ
%token LPAR RPAR BEGIN END SEMI DOT COMMA

%token EOF

(**************************************************)
(*        Déclaration du point d’entrée           *)
(**************************************************)

%start program
%type <Kawa.program> program

(**************************************************)
(*      Règles de priorité pour les opérateurs    *)
(**************************************************)
%left OR
%left AND
%nonassoc EQEQ NEQ LT LE
%left PLUS MINUS
%left STAR SLASH PERCENT
%right UMINUS UNOT     (* UMINUS pour -e, UNOT pour !e par ex. *)

(**************************************************)
(*             Début des règles                   *)
(**************************************************)
%%

(**************************************************)
(*  Programme complet : globales, classes, main   *)
(**************************************************)

program:
  | globals=global_decls classes=class_defs MAIN BEGIN main=seq END EOF
      {
        {
          globals = 
            (* On va convertir (string * typ * expr option) en (string * typ) 
               pour rester compatible avec le squelette. 
               MAIS si vous voulez réellement stocker l'initialisation, 
               il faudra adapter 'program' dans kawa.ml. 
               Pour l'instant, on ne garde que (string, typ) 
               et on ignore l'expression initiale. 
            *)
            List.map (fun (id, t, _init_opt) -> (id, t)) globals;

          classes = classes;     
          main    = main;       
        }
      }

(**************************************************)
(* 1) Déclarations globales : var <type> ... ;    *)
(**************************************************)

global_decls:
  | /* vide */                  
      { [] }
  | global_decls decls=global_decl 
      { $1 @ decls }

(* 
   On accepte la forme :
     var <type> x, y = 42, z ;
   => renvoie une liste de (ident, typ, expr option)
 *)
global_decl:
  | VAR t=type_ decls=decl_init_list SEMI
      { 
        (* decls est une liste de (ident, expr option) 
           -> on convertit en (ident, t, expr option) 
        *)
        List.map (fun (id, initopt) -> (id, t, initopt)) decls
      }
  | VAR t=type_ decls=decl_init_list error
      {
        parse_error "Missing semicolon in global declaration"
      }

decl_init_list:
  | one_decl_init
      { [ $1 ] }                      (* la liste contenant un seul couple *)
  | decl_init_list COMMA one_decl_init
      { $1 @ [ $3 ] }                 (* on concatène la liste existante et le nouvel élément *)


(* (ident, expr option) *)
one_decl_init:
  | id=IDENT eq=maybe_init
      { (id, eq) }

maybe_init:
  | EQ e=expr
      { Some e }
  | /* vide */
      { None }

(**************************************************)
(* 2) Définition de classes                       *)
(**************************************************)

class_defs:
  | /* vide */  
      { [] }
  | class_defs c=class_def 
      { $1 @ [c] }

class_def:
  | CLASS cname=IDENT extends_=opt_extends
         BEGIN attrs=attr_decls methods=method_defs END
      {
        {
          class_name = cname;
          parent     = extends_;
          attributes = 
            (* idem : si on voulait gérer l'init possible, on l'ajouterait. 
               Ici, le squelette reste sur (string * typ). 
            *)
            List.map (fun (id, t, _init_opt) -> (id, t)) attrs;
          methods    = methods;
        }
      }

opt_extends:
  | /* vide */         { None }
  | EXTENDS cname=IDENT { Some cname }

(**************************************************)
(* 3) Déclarations d’attributs                    *)
(**************************************************)

attr_decls:
  | /* vide */                 
      { [] }
  | attr_decls decls=attr_decl 
      { $1 @ decls }

(* On autorise : 
   attribute int x, y = 42; 
   => comme pour var 
*)
attr_decl:
  | ATTRIBUTE t=type_ decls=decl_init_list SEMI
      {
        (* => liste (id, t, init) *)
        List.map (fun (id, initopt) -> (id, t, initopt)) decls
      }
  | ATTRIBUTE t=type_ decls=decl_init_list error
      {
        parse_error "Missing semicolon in attribute declaration"
      }

(**************************************************)
(* 4) Définition de méthodes                      *)
(**************************************************)

method_defs:
  | /* vide */              
      { [] }
  | method_defs m=method_def 
      { $1 @ [m] }

method_def:
  | METHOD ret=type_ fname=IDENT LPAR params=param_list_opt RPAR
    BEGIN locals=var_decl_list body=seq END
      {
        {
          method_name = fname;
          return      = ret;
          params      = params;  
          locals      = locals;  
          code        = body;    
        }
      }

param_list_opt:
  | /* vide */        
      { [] }
  | param_list        
      { $1 }

param_list:
  | t=type_ id=IDENT         
      { [ (id, t) ] }
  | param_list COMMA t=type_ id=IDENT
      { $1 @ [ (id, t) ] }

(**************************************************)
(* 5) Déclarations de variables locales           *)
(**************************************************)

var_decl_list:
  | /* vide */  
      { [] }
  | var_decl_list decls=var_decl 
      { $1 @ decls }

(* On autorise ici aussi : 
   var int a = 10, b, c = 2;
   => la syntaxe est la même que global_decl => on factorise 
*)
var_decl:
  | VAR t=type_ decls=decl_init_list SEMI
      {
        (* On stocke ça dans (string * typ) pour le squelette. 
           Si on voulait l'expr option, on devrait changer 
           la structure method_def.locals. 
        *)
        List.map (fun (id, _initopt) -> (id, t)) decls
      }
  | VAR t=type_ decls=decl_init_list error
      {
        parse_error "Missing semicolon in local var declaration"
      }

(**************************************************)
(* 6) Le type : int, bool, void, ou nom de classe *)
(**************************************************)

type_:
  | INT_T      { TInt }
  | BOOL_T     { TBool }
  | VOID_T     { TVoid }
  | id=IDENT   { TClass id }

(**************************************************)
(* 7) Un bloc d’instructions (seq)                *)
(**************************************************)

seq:
  | /* vide */            
      { [] }
  | seq i=instr           
      { $1 @ [i] }

(**************************************************)
(* 8) Instructions                                *)
(**************************************************)

instr:
  | PRINT LPAR e=expr RPAR SEMI
      { Print e }
  | PRINT LPAR e=expr RPAR error
      { parse_error "Missing semicolon after print(...)" }

  | m=mem_access EQ e=expr SEMI
      { Set(m, e) }
  | m=mem_access EQ e=expr error
      { parse_error "Missing semicolon after assignment" }

  | IF LPAR c=expr RPAR BEGIN s1=seq END ELSE BEGIN s2=seq END
      { If(c, s1, s2) }

  | WHILE LPAR c=expr RPAR BEGIN s=seq END
      { While(c, s) }

  | RETURN e=expr SEMI
      { Return e }
  | RETURN e=expr error
      { parse_error "Missing semicolon after return" }

  (* expression seule comme instruction : e ; *)
  | e=expr SEMI
      { Expr e }
  | e=expr error
      { parse_error "Missing semicolon after expression" }

(**************************************************)
(* 9) Expressions                                 *)
(**************************************************)

expr:
  | INT         { Int($1) }
  | TRUE        { Bool(true) }
  | FALSE       { Bool(false) }
  | THIS        { This }

  | MINUS e=expr %prec UMINUS
      { Unop(Opp, e) }

  (* On remplace la ligne `'!' e=expr %prec UNOT` par BANG e=expr %prec UNOT *)
  | BANG e=expr %prec UNOT
      { Unop(Not, e) }

  | LPAR e=expr RPAR
      { e }

  | e1=expr PLUS  e2=expr   { Binop(Add, e1, e2) }
  | e1=expr MINUS e2=expr   { Binop(Sub, e1, e2) }
  | e1=expr STAR  e2=expr   { Binop(Mul, e1, e2) }
  | e1=expr SLASH e2=expr   { Binop(Div, e1, e2) }
  | e1=expr PERCENT e2=expr { Binop(Rem, e1, e2) }

  | e1=expr EQEQ e2=expr    { Binop(Eq,  e1, e2) }
  | e1=expr NEQ  e2=expr    { Binop(Neq, e1, e2) }
  | e1=expr LT   e2=expr    { Binop(Lt,  e1, e2) }
  | e1=expr LE   e2=expr    { Binop(Le,  e1, e2) }
  | e1=expr AND  e2=expr    { Binop(And, e1, e2) }
  | e1=expr OR   e2=expr    { Binop(Or, e1, e2) }

  | NEW cid=IDENT
      {
        (* Pas de parenthères => pas d'arguments => on construit New cid *)
        New cid
      }

  | NEW cid=IDENT LPAR args=arg_list_opt RPAR
      {
        if args = [] then New cid
        else NewCstr(cid, args)
      }


  | e=expr DOT f=IDENT LPAR args=arg_list_opt RPAR
      { MethCall(e, f, args) }

  | mem=mem_access
      { Get(mem) }

(**************************************************)
(* 10) Liste d'arguments : ex: f(e1, e2, ...)     *)
(**************************************************)

arg_list_opt:
  | /* vide */   
      { [] }
  | arg_list     
      { $1 }

arg_list:
  | e=expr           
      { [e] }
  | arg_list COMMA e=expr 
      { $1 @ [e] }

(**************************************************)
(* 11) Accès mémoire (variable ou champ)          *)
(**************************************************)

mem_access:
  | IDENT         
      { Var($1) }
  | e=expr DOT id=IDENT
      { Field(e, id) }
