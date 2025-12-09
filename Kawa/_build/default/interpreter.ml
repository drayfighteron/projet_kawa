open Kawa

(** Valeurs à l’exécution **)
type value =
  | VInt  of int
  | VBool of bool
  | VObj  of obj
  | Null

(** Représentation d’un objet en mémoire : 
    - le nom de sa classe 
    - un hashtable "fields" pour ses attributs 
**)
and obj = {
  cls:    string;
  fields: (string, value) Hashtbl.t;
}

(** Exceptions possibles pendant l’interprétation **)
exception Error of string
exception Return of value  (* Pour gérer le 'return' dans un appel de méthode *)

(** Petit raccourci pour lever une erreur d’interprétation. *)
let error msg = raise (Error msg)

(***********************************************************************)
(**  Fonction principale : exécuter un programme Kawa                  *)
(***********************************************************************)

let exec_prog (p: program): unit =

  (** 1) Construire un environnement global "env" pour les variables globales  **)
  let env = Hashtbl.create 16 in

  (* Ici, on associe chaque variable globale à Null par défaut.
     Si vous gérez la "déclaration avec valeur initiale" et 
     stockez cette info dans p.globals, c’est ici qu’il faudrait 
     évaluer l’expression et mettre la valeur réelle. 
  *)
  List.iter (fun (x, _) ->
      Hashtbl.add env x Null
    ) p.globals;

  (** 2) Construire une table (hashtable) pour retrouver rapidement 
         la définition de chaque classe par son nom.
   **)
  let classmap = Hashtbl.create 16 in
  List.iter (fun cdef ->
      Hashtbl.add classmap cdef.class_name cdef
    ) p.classes;

  (*********************************************************************)
  (**   Recherche d’une méthode dans une classe ou sa super-classe    **)
  (*********************************************************************)
  let rec find_method (clsname: string) (mname: string) : method_def =
    match Hashtbl.find_opt classmap clsname with
    | None ->
       error ("Unknown class: " ^ clsname)
    | Some cdef ->
       (* Chercher la méthode mname dans cdef.methods *)
       match List.find_opt (fun m -> m.method_name = mname) cdef.methods with
       | Some m -> m
       | None ->
         (* Si pas trouvée, on regarde dans la super-classe, si elle existe *)
         begin match cdef.parent with
         | None ->
            error (Printf.sprintf "Method '%s' not found in class '%s'"
                     mname clsname)
         | Some parentname ->
            find_method parentname mname
         end
  in

  (*********************************************************************)
  (**   Création d’un nouvel objet de classe clsname                  **)
  (*********************************************************************)
  let create_object (clsname: string) : value =
    match Hashtbl.find_opt classmap clsname with
    | None ->
       error ("Cannot instantiate unknown class " ^ clsname)
    | Some cdef ->
       let fields = Hashtbl.create 16 in
       (* Pour chaque attribut de la classe (et éventuellement de ses parents),
          on initialise la valeur de l'attribut à Null 
          (il sera éventuellement modifié ensuite, par un "constructor" ou un set). *)
       let rec collect_attrs (c: class_def) =
         (* ajouter les attributs de c *)
         List.iter (fun (attr_name, _typ) ->
             Hashtbl.add fields attr_name Null
           ) c.attributes;
         match c.parent with
         | None -> ()
         | Some p -> 
           (match Hashtbl.find_opt classmap p with
            | None -> error ("Parent class not found: " ^ p)
            | Some pc -> collect_attrs pc)
       in
       collect_attrs cdef;
       VObj { cls = clsname; fields }
  in

  (*********************************************************************)
  (**   Évaluation d’un appel de méthode sur un objet                 **)
  (*********************************************************************)
  let rec eval_call (mname: string) (this: value) (args: value list) : value =
    match this with
    | VObj o ->
       (* Récupérer la définition de la méthode mname dans o.cls *)
       let mdef = find_method o.cls mname in

       (* Construire un environnement local lenv pour cette exécution de méthode :
          - "this" -> this
          - chaque paramètre pi <- args_i
          - chaque variable locale de la méthode initialisée à Null
       *)
       let lenv = Hashtbl.create 16 in
       Hashtbl.add lenv "this" this;

       (* Paramètres formels *)
       let params = mdef.params in
       if List.length params <> List.length args then
         error (Printf.sprintf 
                  "Method %s in class %s called with %d arguments, expected %d"
                  mname o.cls (List.length args) (List.length params));

       List.iter2 (fun (pname, _ptyp) arg_val ->
           Hashtbl.add lenv pname arg_val
         ) params args;

       (* Variables locales : initialisées à Null *)
       List.iter (fun (localname, _ltyp) ->
           Hashtbl.add lenv localname Null
         ) mdef.locals;

       (* On exécute le corps mdef.code dans lenv. 
          Si on rencontre Return v, on renvoie v ; 
          sinon on renvoie Null (pour une méthode void qui n’a pas de return explicite)
       *)
       (try
          exec_seq mdef.code lenv;
          Null
        with
        | Return v -> v)

    | _ ->
       error "Method call on a non-object value"

  (** 3) Fonctions locales pour exécuter un bloc d’instructions (seq) 
         avec un environnement local "lenv".
   **)
  and exec_seq (s: seq) (lenv: (string, value) Hashtbl.t) : unit =
    List.iter (fun i -> exec_instr i lenv) s

  and exec_instr (i: instr) (lenv: (string, value) Hashtbl.t) : unit =
    match i with
    | Print e ->
       let v = eval_expr e lenv in
       (match v with
        | VInt n   -> Printf.printf "%d\n" n
        | VBool b  -> Printf.printf "%b\n" b
        | VObj _   -> Printf.printf "<object>\n"
        | Null     -> Printf.printf "null\n");
       flush stdout

    | Set(mem, e) ->
       let v = eval_expr e lenv in
       set_mem mem v lenv

    | If(cond, s1, s2) ->
       (match eval_expr cond lenv with
        | VBool true  -> exec_seq s1 lenv
        | VBool false -> exec_seq s2 lenv
        | _ -> error "if condition is not a boolean")

    | While(cond, body) ->
       let rec loop () =
         match eval_expr cond lenv with
         | VBool true  -> exec_seq body lenv; loop ()
         | VBool false -> ()
         | _ -> error "while condition is not a boolean"
       in
       loop ()

    | Return e ->
       let v = eval_expr e lenv in
       raise (Return v)

    | Expr e ->
       (* on évalue l’expression, mais on ignore le résultat *)
       ignore (eval_expr e lenv)

  (** 4) Fonctions pour évaluer une expression. **)
  and eval_expr (e: expr) (lenv: (string, value) Hashtbl.t) : value =
    match e with
    | Int n  -> VInt n
    | Bool b -> VBool b

    | This ->
       (match Hashtbl.find_opt lenv "this" with
        | Some v -> v
        | None   -> error "Use of 'this' outside of any object context")

    | Unop(Opp, e1) ->
       (match eval_expr e1 lenv with
        | VInt n -> VInt (-n)
        | _      -> error "unary minus on a non-integer")

    | Unop(Not, e1) ->
       (match eval_expr e1 lenv with
        | VBool b -> VBool (not b)
        | _       -> error "logical not on a non-boolean")

    | Binop(op, e1, e2) ->
       let v1 = eval_expr e1 lenv in
       let v2 = eval_expr e2 lenv in
       eval_binop op v1 v2

    | Get mem ->
       eval_mem mem lenv

    | New cname ->
       create_object cname

    | NewCstr(cname, expr_args) ->
       (* 1) Créer l’objet *)
       let o = create_object cname in
       (* 2) Appeler o.constructor(...) *)
       let argvals = List.map (fun ex -> eval_expr ex lenv) expr_args in
       ignore (eval_call "constructor" o argvals);
       (* 3) Retourne l’objet créé *)
       o

    | MethCall(obj_exp, mname, expr_args) ->
       let obj_val = eval_expr obj_exp lenv in
       let argvals = List.map (fun ex -> eval_expr ex lenv) expr_args in
       eval_call mname obj_val argvals

  (** 5) Évaluation d’un accès mémoire (variable ou champ) **)
  and eval_mem (m: mem_access) (lenv: (string, value) Hashtbl.t) : value =
    match m with
    | Var x ->
       begin match Hashtbl.find_opt lenv x with
       | Some v -> v
       | None ->
         (* si la variable n’est pas locale, on teste l’environnement global *)
         (match Hashtbl.find_opt env x with
          | Some vg -> vg
          | None -> error ("Undefined variable: " ^ x))
       end

    | Field(e, attr) ->
       (match eval_expr e lenv with
        | VObj o ->
           (match Hashtbl.find_opt o.fields attr with
            | Some v -> v
            | None   ->
               error (Printf.sprintf 
                        "Unknown field '%s' in object of class '%s'" 
                        attr o.cls))
        | _ -> error "Field access on a non-object expression")

  (** 6) Affectation d’un accès mémoire (mem_access) **)
  and set_mem (m: mem_access) (v: value) (lenv: (string, value) Hashtbl.t) : unit =
    match m with
    | Var x ->
       if Hashtbl.mem lenv x then
         Hashtbl.replace lenv x v
       else if Hashtbl.mem env x then
         Hashtbl.replace env x v
       else
         error ("Cannot set unknown variable: " ^ x)

    | Field(e, attr) ->
       (match eval_expr e lenv with
        | VObj o ->
           if Hashtbl.mem o.fields attr then
             Hashtbl.replace o.fields attr v
           else
             error (Printf.sprintf
                      "Cannot set unknown field '%s' in class '%s'"
                      attr o.cls)
        | _ -> error "Cannot set a field on a non-object expression")

  (** 7) Évaluation d’un opérateur binaire (arithmétique, logique, etc.) **)
  and eval_binop (op: binop) (v1: value) (v2: value) : value =
    match op with
    | Add -> 
       (match v1, v2 with
        | VInt a, VInt b -> VInt (a + b)
        | _ -> error "Addition on non-integers")
    | Sub ->
       (match v1, v2 with
        | VInt a, VInt b -> VInt (a - b)
        | _ -> error "Subtraction on non-integers")
    | Mul ->
       (match v1, v2 with
        | VInt a, VInt b -> VInt (a * b)
        | _ -> error "Multiplication on non-integers")
    | Div ->
       (match v1, v2 with
        | VInt _, VInt 0 -> error "Division by zero"
        | VInt a, VInt b -> VInt (a / b)
        | _ -> error "Division on non-integers")
    | Rem ->
       (match v1, v2 with
        | VInt _, VInt 0 -> error "Modulo by zero"
        | VInt a, VInt b -> VInt (a mod b)
        | _ -> error "Modulo on non-integers")

    | Lt ->
       (match v1, v2 with
        | VInt a, VInt b -> VBool (a < b)
        | _ -> error "Comparison < on non-integers")
    | Le ->
       (match v1, v2 with
        | VInt a, VInt b -> VBool (a <= b)
        | _ -> error "Comparison <= on non-integers")
    (* Gt, Ge éventuels *)
    | Eq ->
       (* == : test l’égalité "physique" 
          (même valeur pour int/bool, ou même référence pour objets)
       *)
       VBool (eq_value v1 v2)
    | Neq ->
       VBool (not (eq_value v1 v2))

    | And ->
       (match v1 with
        | VBool false -> VBool false
        | VBool true ->
           (match v2 with
            | VBool b2 -> VBool b2
            | _ -> error "Right operand of && is not a bool")
        | _ -> error "Left operand of && is not a bool")

    | Or ->
       (match v1 with
        | VBool true -> VBool true
        | VBool false ->
           (match v2 with
            | VBool b2 -> VBool b2
            | _ -> error "Right operand of || is not a bool")
        | _ -> error "Left operand of || is not a bool")

  (** Test d’égalité physique. 
      - Deux entiers (VInt) sont égaux s’ils ont la même valeur 
      - Deux booléens (VBool) idem 
      - Null == Null
      - Deux objets => vrai si c’est la même référence
      - Sinon false
   **)
  and eq_value (v1: value) (v2: value) : bool =
    match v1, v2 with
    | VInt  a, VInt  b  -> a = b
    | VBool a, VBool b -> a = b
    | Null, Null       -> true
    | VObj o1, VObj o2 -> o1 == o2
    | _                -> false
  in

  (*********************************************************************)
  (** 4) Exécuter le bloc principal p.main avec un env local vide      **)
  (*********************************************************************)
  let lenv_main = Hashtbl.create 16 in
  exec_seq p.main lenv_main;
