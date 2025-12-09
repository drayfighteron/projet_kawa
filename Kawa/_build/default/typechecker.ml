open Kawa

(** Exceptions de typage **)
exception Error of string
let error s = raise (Error s)

let type_error ty_actual ty_expected =
  error (Printf.sprintf "Type error: expected %s, got %s"
           (typ_to_string ty_expected) (typ_to_string ty_actual))

(** Pour signaler qu’une classe est introuvable **)
let class_not_found c =
  error (Printf.sprintf "Class '%s' not found" c)

(** Sous-typage : t1 <: t2 ? 
    Règle: t1 = t2
          ou t1 est sous-classe de t2
    Ici, on suppose l’héritage simple (pas d’interfaces multiples).
**)
let rec is_subtype classmap t1 t2 =
  match t1, t2 with
  (* On n’autorise pas TAny pour l’instant, juste TInt, TBool, TClass. *)
  | _, TVoid ->
     (* "void" n’est pas un vrai type de valeur. 
        On considère qu’un return e; doit avoir e <: ret. 
        Pour ret = void, e doit être un expr "vide" => 
        on gère ça autrement. 
     *)
     false

  | _ , TInt
  | _ , TBool ->
     (* Sous-typage trivial : int <: int, bool <: bool *)
     t1 = t2

  | TClass c1, TClass c2 ->
     if c1 = c2 then true
     else
       (* On remonte la chaîne des parents de c1 *)
       match Hashtbl.find_opt classmap c1 with
       | None -> false
       | Some ci ->
          begin match ci.parent with
          | None -> false
          | Some parent -> is_subtype classmap (TClass parent) t2
          end

  | _ ->
     (* tous les autres cas => false *)
     false

(** Structure pour le stockage des infos de classe **)
type class_info = {
  parent     : string option;                (* nom de la classe parent, si any *)
  attributes : (string * typ) list;          (* liste des (nomAttr, typeAttr)   *)
  methods    : (string, method_def) Hashtbl.t; 
}

(** Construit une map (hashtbl) : className -> class_info 
    à partir de p.classes. 
**)
let build_classmap (p: program) : (string, class_info) Hashtbl.t =
  let cm = Hashtbl.create 17 in
  let add_class cdef =
    if Hashtbl.mem cm cdef.class_name then
      error ("Duplicated class: " ^ cdef.class_name);

    let tbl_methods = Hashtbl.create 17 in
    List.iter (fun m ->
      Hashtbl.add tbl_methods m.method_name m
    ) cdef.methods;

    Hashtbl.add cm cdef.class_name {
      parent     = cdef.parent;
      attributes = cdef.attributes;
      methods    = tbl_methods;
    }
  in
  List.iter add_class p.classes;
  cm

(** Récupère le type d’un attribut "attr" dans la classe "classname" 
    ou l’une de ses super-classes. 
**)
let rec find_attribute_type cm classname attr =
  match Hashtbl.find_opt cm classname with
  | None ->
     class_not_found classname

  | Some ci ->
     begin
       try
         List.assoc attr ci.attributes
       with Not_found ->
         (* chercher dans la super-classe *)
         match ci.parent with
         | None ->
            error (Printf.sprintf "Attribute '%s' not found in class '%s'." 
                     attr classname)
         | Some p -> find_attribute_type cm p attr
     end

(** Récupère la méthode "mname" dans la classe "classname" ou parentée. *)
let rec find_method cm classname mname =
  match Hashtbl.find_opt cm classname with
  | None ->
     class_not_found classname

  | Some ci ->
     begin
       match Hashtbl.find_opt ci.methods mname with
       | Some m -> m
       | None ->
          (* si pas dans cette classe, on regarde la classe mère *)
          match ci.parent with
          | None ->
             error (Printf.sprintf "Method '%s' not found in class '%s'."
                      mname classname)
          | Some p ->
             find_method cm p mname
     end

(** Vérifie que si B extends A, alors A existe, etc. *)
let check_classes (cm: (string, class_info) Hashtbl.t) =
  Hashtbl.iter (fun cname cinfo ->
      match cinfo.parent with
      | None -> ()
      | Some p ->
         if not (Hashtbl.mem cm p) then
           class_not_found p
    ) cm

(***************************************************************)
(** Environnement de typage : map (String -> typ)              *)
(***************************************************************)

module Env = Map.Make(String)
type tenv = typ Env.t

(* Ajout d’une liste (ident, typ) dans l’environnement. *)
let add_env (l: (string * typ) list) (tenv: tenv) : tenv =
  List.fold_left (fun env (x, t) ->
    Env.add x t env
  ) tenv l

(***************************************************************)
(** Fonctions de vérification : type_expr, check_instr, ...     *)
(***************************************************************)

let typecheck_prog (p: program) =
  (* 1) Construire la table des classes *)
  let classmap = build_classmap p in

  (* 2) Vérifier la cohérence de l’héritage *)
  check_classes classmap;

  (* 3) Construire l’environnement global pour p.globals *)
  let global_env = add_env p.globals Env.empty in

  (***************************************************************)
  (* type_expr e tenv : renvoie le type statique de e            *)
  (***************************************************************)
  let rec type_expr (e: expr) (tenv: tenv) : typ =
    match e with
    | Int _   -> TInt
    | Bool _  -> TBool
    | This    ->
       begin match Env.find_opt "this" tenv with
       | Some t -> t
       | None   -> error "Use of 'this' outside of a method"
       end

    | Unop(Opp, e1) ->
       let t1 = type_expr e1 tenv in
       if t1 <> TInt then type_error t1 TInt;
       TInt

    | Unop(Not, e1) ->
       let t1 = type_expr e1 tenv in
       if t1 <> TBool then type_error t1 TBool;
       TBool

    | Binop(op, e1, e2) ->
       let t1 = type_expr e1 tenv in
       let t2 = type_expr e2 tenv in
       begin match op with
       | Add | Sub | Mul | Div | Rem ->
          if t1 <> TInt then type_error t1 TInt;
          if t2 <> TInt then type_error t2 TInt;
          TInt
       | Lt | Le | Gt | Ge ->
          if t1 <> TInt then type_error t1 TInt;
          if t2 <> TInt then type_error t2 TInt;
          TBool
       | Eq | Neq ->
          (* e1 == e2 : polymorphe, mais t1 et t2 doivent être 
             sous-types réciproques. 
          *)
          if not (is_subtype classmap t1 t2 && is_subtype classmap t2 t1) then
            error (Printf.sprintf 
                     "Equality operator used on incompatible types %s and %s"
                     (typ_to_string t1) (typ_to_string t2));
          TBool
       | And | Or ->
          if t1 <> TBool then type_error t1 TBool;
          if t2 <> TBool then type_error t2 TBool;
          TBool
       end

    | Get m ->
       type_mem_access m tenv

    | New cname ->
       if not (Hashtbl.mem classmap cname) then class_not_found cname;
       TClass cname

    | NewCstr(cname, args) ->
       if not (Hashtbl.mem classmap cname) then class_not_found cname;
       let constructor_m = find_method classmap cname "constructor" in
       if constructor_m.return <> TVoid then
         error ("constructor method must have type void in class " ^ cname);
       let expected_params = constructor_m.params in
       let nb_exp = List.length expected_params in
       let nb_got = List.length args in
       if nb_exp <> nb_got then
         error (Printf.sprintf
                  "Wrong number of arguments in new %s(...): expected %d, got %d"
                  cname nb_exp nb_got);
       List.iter2 (fun (_, ptyp) earg ->
         let targ = type_expr earg tenv in
         if not (is_subtype classmap targ ptyp) then
           type_error targ ptyp
       ) expected_params args;
       TClass cname

    | MethCall(obj_exp, mname, args) ->
       let tobj = type_expr obj_exp tenv in
       begin match tobj with
       | TClass c ->
          let mdef = find_method classmap c mname in
          let expected_params = mdef.params in
          let nb_exp = List.length expected_params in
          let nb_got = List.length args in
          if nb_exp <> nb_got then
            error (Printf.sprintf 
                     "Method %s in class %s expects %d arguments, got %d"
                     mname c nb_exp nb_got);
          List.iter2 (fun (_, ptyp) earg ->
            let targ = type_expr earg tenv in
            if not (is_subtype classmap targ ptyp) then
              type_error targ ptyp
          ) expected_params args;
          mdef.return
       | _ ->
          error (Printf.sprintf 
                   "Cannot call method %s on non-object type %s"
                   mname (typ_to_string tobj))
       end

  and type_mem_access (m: mem_access) (tenv: tenv) : typ =
    match m with
    | Var x ->
       begin match Env.find_opt x tenv with
       | Some t -> t
       | None   -> error ("Unknown variable: " ^ x)
       end
    | Field(e, attr) ->
       let te = type_expr e tenv in
       match te with
       | TClass c ->
          find_attribute_type classmap c attr
       | _ ->
          error (Printf.sprintf 
                   "Cannot access field '%s' on non-object type %s"
                   attr (typ_to_string te))
  in

  (***************************************************************)
  (* check_instr i ret tenv : vérifie la cohérence d’une instr. *)
  (***************************************************************)
  let rec check_instr (i: instr) (ret: typ) (tenv: tenv) : unit =
    match i with
    | Print e ->
       let t = type_expr e tenv in
       if t <> TInt then type_error t TInt

    | Set(mem, e) ->
       let tmem = type_mem_access mem tenv in
       let te   = type_expr e tenv in
       if not (is_subtype classmap te tmem) then
         type_error te tmem

    | If(cond, s1, s2) ->
       let tc = type_expr cond tenv in
       if tc <> TBool then type_error tc TBool;
       check_seq s1 ret tenv;
       check_seq s2 ret tenv

    | While(cond, s) ->
       let tc = type_expr cond tenv in
       if tc <> TBool then type_error tc TBool;
       check_seq s ret tenv

    | Return e ->
       let te = type_expr e tenv in
       if not (is_subtype classmap te ret) then
         type_error te ret

    | Expr e ->
       ignore (type_expr e tenv)

  and check_seq (s: seq) (ret: typ) (tenv: tenv) : unit =
    List.iter (fun i -> check_instr i ret tenv) s
  in

  (***************************************************************)
  (** Vérification de chaque classe, chaque méthode              *)
  (***************************************************************)
  List.iter (fun cdef ->
    let this_typ = TClass cdef.class_name in
    let cinfo = Hashtbl.find classmap cdef.class_name in
    (* Pour chaque méthode *)
    Hashtbl.iter (fun _ (mdef: method_def) ->
      let lenv =
        Env.empty
        |> Env.add "this" this_typ
        |> add_env mdef.params
        |> add_env mdef.locals
      in
      check_seq mdef.code mdef.return lenv
    ) cinfo.methods
  ) p.classes;

  (***************************************************************)
  (** Type-check du bloc main                                    *)
  (***************************************************************)
  check_seq p.main TVoid global_env;

  (* OK si pas d’exception levée. *)
  ()
