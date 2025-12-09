Note importante : 
Bonjour / bonsoir,

Ce serait juste pour rappeler que j'effectue cette UE en bonus et cette dernière ne compte pas pour 
mon relevé de note, si jamais, je conseille de prioriser les projets des étudiants pour qui l'UE a une réelle 
valeur pour la suite de leur cursus et la validation de leur année.

Cordialement.


                  
Nom : Bentouati
Prenom : Rayan
Statut : Monome

Travail réalisé :

Analyse lexicale (fichier kawalexer.mll) :
but : reconnaissance des différents mots-clés, identifiants, constantes entières, opérateurs, ...

travail réalisé :
	- définition des règles de reconnaissance pour chaque token (ex : class, if, new, BANG pour !, ...)
	- gestion des commentaires (/* ... */, //...), des espaces, des sauts de lignes, ...


Analyse syntaxique (fichier kawaparser.mly) :
but : transformer la suite de tokens en un arbre de syntaxe abstraite

travail réalisé :
	- Définition de la grammaire Kawa, pour reconnaître les déclarations globales, 
	classes, méthodes, instructions (if, while, print, etc.) et expressions 
	(opérateurs arithmétiques, booléens).
	- Gestion des priorités via %left, %right, %nonassoc dans l'optique d'éviter
	de potentiels conflits
	- Autorisation de deux formes de création d'objets : new C(...) ainsi quez new C
	- Gestion de l'erreur "missing semicolon" dans différents contextes via utilisation
	de différentes règles
	...

Vérification des types (fichier typechecker.ml) :
but : valider la cohérence des programmes : par exemple, que les classes, méthodes et accès
mémoire soient corrects, et qure les types soient conformes (pas d'addition de booléens, ...)

travail réalisé :
- construction d'une table des classes (classmap) pour accéder facilement aux attributs et aux
méthodes héritées
- verification du sous-typage, des appels de méthode, et de la cohérence d’instructions (if, while, return).
- Les programmes Kawa ne respectant pas ces règles lèvent une exception Error


Interprétation (fichier interpreter.ml) :
but : exécuter concrètement les instructions d’un programme Kawa, en manipulant l’environnement 
global et local, les objets, etc.

travail réalisé :
- Gestion de la mémoire via des Hashtbl pour l’environnement global (variables globales) 
et local (variables locales de méthode).
- Création d’objets (new C) avec un Hashtbl pour stocker les attributs.
- Appel de méthodes, prise en compte de this, des instructions if/while/return/print, des expressions arithmétiques, booléennes (&&, ||, ==, etc.) et de l’égalité physique sur les objets.


Vérification par rapport aux tests donnés (+ certains ajouts) :

En compilant le projet avec dune build et en executant les différents tests donnés, j'obtiens :
instr.kwa → 512
class.kwa → 10
min.kwa → 42
extend.kwa →
3
12
60
6
arith.kwa → 42
method.kwa → 54
var.kwa → 42
nclass.kwa → 10

de plus, en plus des fichiers initiaux, ont été rajouté :

var_series.kwa pour tester la déclaration de plusieurs variables à la suite : var int x, y, z;

résultat obtenu à l'execution : 5

missingsemi.kwa pour tester la gestion de l'abscense du point virgule en fin de phrase

résultat obtenu : Anomaly: Dune__exe__Kawaparser.ParseError("Missing semicolon in global declaration")

Tests non concluants :
initvar.kwa pour tester l'affectation directe d'une variable.
erreur obtenue : syntax error line 14

bool.kwa pour tester les booléens
syntax error ligne 7

