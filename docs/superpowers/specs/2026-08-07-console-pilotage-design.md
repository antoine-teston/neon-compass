# Console de pilotage — Supabase, GitHub, et le carnet de hotfix

**Date** : 2026-08-07
**Statut** : validé, non implémenté
**Branche** : `console-pilotage`

## Problème

Le pilotage de Neon Compass est complet en pièces détachées et absent en tant que geste. Chaque
opération existe — un workflow, une commande de `content-cli`, une valeur d'`app_config` — mais
rien ne dit **ce qui attend une décision**, et rien ne déclenche depuis un seul endroit.

L'état au 2026-08-07 donne la mesure :

| Besoin | État |
|---|---|
| Contrôles, publication CDN, modération, coupe-circuit | ✅ `tools/content-cli/ui/`, console locale déjà en place |
| Déclencher un workflow GitHub | ❌ terminal uniquement |
| Lire le **vrai** verdict d'un run | ❌ nulle part |
| Corriger un brouillon d'actu | ❌ éditeur de texte + `git status` |
| Gestes correctifs nommés | ❌ aucun carnet |

Le symptôme qui a déclenché ce travail se lit dans le contenu :

```
news draft = 7   dont rumor = 6   →   retenus par une RÈGLE
                 dont single-source = 1  →  attend une décision
poi  draft = 9
online-events draft = 0
```

Six des sept actus sont retenues **exprès** : `check-publishable` refuse les rumeurs par décision
éditoriale. Une seule attend réellement quelque chose. Le besoin n'est donc pas de compter des
brouillons — c'est de **distinguer « retenu par une règle » de « attend ta décision »**. Un tableau
de bord qui annoncerait « 7 brouillons » produirait du bruit.

C'est la même classe de panne que les deux déjà rencontrées : la chaîne réussit et ne produit rien
(récolte fusionnée invisible, fonction non déployée qui rend l'ancienne réponse). Ce qui manque à
chaque fois est un **regard**, pas un bouton. Le bouton ne sert qu'après.

## Décisions de cadrage

Quatre arbitrages pris le 2026-08-07, et les raisons de ne pas les rejouer.

**Mac uniquement.** Une console hébergée demanderait une authentification à construire, un jeton
GitHub côté serveur, et la clé `service_role` hors de la machine. Un serveur qui déclenche des
déploiements et lit Supabase en `service_role` est une cible. Le gain — agir sans le Mac — ne le
paie pas aujourd'hui.

**Deux portes, deux invariants** — plutôt qu'un seul groupe d'actions. Le modèle actuel est une
liste blanche d'`argv` fixes : « rien de la requête n'atteint une ligne de commande ». Le corps
d'une actu, multi-ligne et apostrophé, n'entre pas dans un `argv` ; faire entrer l'édition dans ce
modèle obligerait à relâcher l'invariant qui fait tenir tout le reste. Faire transiter le texte par
une sous-commande CLI (`edit:set <id> <champ> <valeur>`) finit toujours en fichier temporaire —
c'est-à-dire la même chose, en moins net.

**Pas d'éditeur libre d'`app_config`.** Ses valeurs changent, mais seulement **sous un geste nommé**
du carnet (« couper les contributions », « basculer `contentBaseURL` »). Une valeur ne bouge que
sous un nom qui dit pourquoi.

**Grafana : plus tard, et non modifié.** Le tableau officiel `supabase/supabase-grafana` existe,
apporte plus de 200 graphiques, et s'alimente d'un endpoint Prometheus authentifié en Basic
(`service_role` + clé secrète). La documentation ne mentionne aucune restriction de plan — l'org
est en `free`, donc *a priori* accessible ; **non vérifié en tapant l'endpoint**, à confirmer d'un
`curl`. Mais Grafana est un plan de lecture de séries temporelles : il ne voit pas `content/`
(fichiers git sur le Mac, pas des lignes en base), ne déclenche rien, et n'édite rien — soit les
trois postes de cette v1. Et l'app n'étant pas lancée, ses courbes seraient plates jusqu'en
novembre. Il sera monté **tel quel** en geste de pré-lancement, jamais modifié : un tableau amont
intact se met à jour gratuitement. La console recevra alors — **et pas dans cette v1** — une carte
« santé » qui résume en trois couleurs et **pointe** vers lui, sans rien réimplémenter.

## Architecture

Rien de nouveau n'est hébergé. On étend `tools/content-cli/ui/`, toujours sur `127.0.0.1`, toujours
lancé par `npm run ui`.

### Porte « geste » — `POST /run`

Celle qui existe. Invariant inchangé : *rien du corps de la requête n'atteint une ligne de commande,
hors paramètres validés par motif.* Aujourd'hui le seul paramètre est `id` avec `ID_PATTERN` ; on
généralise en champs typés déclarés à côté de l'action :

```js
recolte: {
  argv: ['gh', 'workflow', 'run', 'recolte.yml'],
  params: { since: /^\d{1,3}$/, max: /^\d{1,3}$/ },
}
```

Un champ sans motif déclaré est un refus, jamais un laissez-passer.

### Porte « édition » — `GET`/`PUT /draft/:kind/:id`

Neuve. Invariant : *elle n'exécute aucun processus.* Aucun `spawn` dans ce chemin, donc aucune
injection possible par construction. Trois contraintes :

- `kind` dans une liste fermée (`news`, `online-events`) ;
- `id` validé par `ID_PATTERN`, ce qui exclut déjà `/` et `.` ;
- **le fichier doit déjà exister**.

L'atelier n'a pas de bouton « créer » : il corrige ce que la veille a produit, la création reste à
`pull-news`. Une porte qui ne sait qu'écraser un fichier existant se raisonne bien mieux qu'une
porte qui sait créer.

### Découpage

`server.mjs` fait 7,6 Ko et ne doit pas devenir le fourre-tout. Chaque fichier une raison d'être :

| Fichier | Rôle |
|---|---|
| `actions.mjs` *(étendu)* | liste blanche + champs typés |
| `hotfix.mjs` *(neuf)* | le carnet, en données pures |
| `drafts.mjs` *(neuf)* | lire / valider / écrire un fichier de contenu |
| `runs.mjs` *(neuf)* | déclencher un workflow, lire son vrai verdict |
| `state.mjs` *(neuf)* | ce que le tableau de bord agrège |
| `server.mjs` *(étendu)* | routage seul |

## Le tableau de bord

Il répond à une seule question : **qu'est-ce qui attend quelque chose de moi ?**

Trois classes de cartes, séparées par leur coût :

- **Instantanées** (disque seul, au chargement) — brouillons triés en trois piles avec l'âge du plus
  ancien, état git, retard des socles embarqués.
- **Réseau** (en arrière-plan, chacune son état) — dernier run de Récolte et son verdict réel,
  valeurs d'`app_config` en production, dérive des edge functions (`tools/edge-functions/drift.mjs`
  existe, on le rebranche).
- **Jamais au chargement** — `release --dry-run`. Trop lent, et c'est une décision, pas un état.

**Une carte ne ment jamais par omission.** `gh` non authentifié, credentials absents, réseau
tombé : la carte le dit. Elle n'affiche jamais un zéro. « 0 brouillon en attente » parce qu'un
dossier n'a pas pu être lu est exactement la panne qu'on supprime, pas qu'on déplace.

## La Récolte en un clic

**Déclencher.** `gh workflow run recolte.yml` avec `since` et `max`, motif `/^\d{1,3}$/`, défauts 2
et 15 — ceux du workflow.

**Retrouver le run.** `workflow run` ne rend pas d'identifiant. On le repêche par `gh run list`,
avec un risque réel de tomber sur le run du cron de 1 h 47 : on note l'instant du déclenchement et
on n'accepte qu'un run créé après.

**Le verdict.** Trois sources, dont deux mentent :

| Source | Ce qu'elle vaut |
|---|---|
| `status` du run | dit seulement si c'est fini |
| `conclusion` de l'étape | **ment**. Vérifié le 2026-08-06 : quatre runs `success`, deux avaient échoué. `continue-on-error` fait rapporter `success` à l'étape elle-même ; `outcome`, qui dirait vrai, n'est pas exposé par l'API |
| le journal | la seule autorité |

`runs.mjs` lit `gh run view <id> --log`, retire les codes ANSI, et cherche **des marqueurs
positifs** : nombre de pages rapportées, écriture de `content/inbox/…`, ligne « récolte déposée sur
veille/recolte ». La nuance décide de tout — chercher « pas d'erreur » se fait piéger par un journal
vide ; il faut chercher **ce qui doit être là**.

Quatre verdicts, et le quatrième n'est pas un succès :

- `complète` — tous les marqueurs présents ;
- `partielle — <étape> muette` — le marqueur d'une étape tolérante manque ;
- `échec` — le run a échoué franchement ;
- `indéterminé` — journal illisible ou vide. **Jamais « ok ».**

*Note, corrigée le 2026-08-07 en cours d'implémentation* : cette spec affirmait d'abord que le
`--capture` / `weekly.json` de la branche `veille/hub-verdicts` n'existait nulle part. **C'était
faux** — il est sur `origin/main` et il tourne (visible dans le run 31146819752). L'arbre de travail
était en retard de seize commits, et une branche rebasée depuis a rétabli le fait.

Cela ne change pas la conception : `weekly.json` vit dans l'artefact et sur la branche de transport,
pas dans une API que la console interrogerait. Le journal reste la source, et il porte déjà la
sortie de l'étape (« pas de semaine publiée — la source déclare … »), qui suffit au marqueur.

La leçon, elle, mérite d'être gardée : **une affirmation d'absence tirée d'un arbre local n'est
qu'une affirmation sur l'arbre local.** `git fetch` avant de conclure qu'un travail n'a pas atterri.

**Après la Récolte.** Elle se dépose sur `veille/recolte` ; c'est la Routine cloud qui en fait des
faits. La console ne refait pas ce travail mais doit dire où on en est — « récolte du 07/08 déposée,
en attente de la Routine » plutôt que rien.

## L'atelier des brouillons

### Trois piles, pas une liste

- **Attend ta décision** — schéma valide, `check-publishable` passe. Bouton *Publier* actif.
- **Retenu par une règle** — la règle nommée en clair (« rumeur », « rédaction non faite », « marque
  dans la prose »). Pas de bouton : lever la retenue est une décision qui se prend dans la règle,
  pas dans l'item.
- **Cassé** — ne valide pas le schéma. L'erreur ajv s'affiche telle quelle, sans reformulation :
  elle est plus précise que ce qu'on écrirait.

### L'écran d'un item

Deux colonnes. À gauche `sourceClaim` et `sources`, **non éditables** — ce sont les faits, et ils
citent leurs sources mot pour mot, marques déposées comprises. À droite `title`, `body`, `category`,
`confidence`, éditables. `title` et `body` sont des objets localisés `{en, fr}` — `en` obligatoire,
c'est la langue de base ; ES/IT/DE restent au ressort de `translate`.

La séparation gauche/droite n'est pas cosmétique : elle rend le geste « recopier le fait dans la
prose » impossible par inadvertance, ce que la contrainte IP interdit.

### Le piège du tri — à ne pas découvrir à l'exécution

`checkPublishable(entries)` (`tools/content-cli/cli.js:123`) est une fonction pure sur un tableau
d'`{ kind, file, data }` : elle accepte donc un tableau à un seul élément. Deux obstacles, tous deux
vérifiés le 2026-08-07 :

**Elle n'est pas exportée.** Elle doit être extraite de `cli.js` dans un module importable, à
comportement strictement inchangé, pour que `drafts.mjs` s'en serve. C'est le seul remaniement que
ce chantier s'autorise.

**Toutes ses règles sauf le scan de marques sont conditionnées à `data.status === 'published'`** —
rumeur, `needsRewrite`, cheat non corroboré. Un brouillon passe donc **trivialement**. Le tri doit
l'évaluer **comme s'il était publié** : une copie superficielle avec `status: 'published'`. Sans
cela les 6 rumeurs atterrissent dans « attend ta décision », c'est-à-dire exactement la panne que
toute cette conception existe pour supprimer.

### Écriture

`PUT` → schéma ajv, puis `checkPublishable` sur cet item seul, puis écriture. Un refus n'écrit
rien.

**Concurrence** : le fichier peut avoir bougé au terminal depuis l'ouverture. On lit une empreinte à
l'ouverture, on la renvoie au `PUT`, on refuse si le disque a changé. Sans ça la console écrase une
édition en silence.

### Ce que l'atelier ne fait pas

Pas de création — c'est `pull-news`. Pas de git non plus : il écrit dans l'arbre de travail, commit
et PR restent des gestes explicites. Délibéré, et c'est la contrepartie d'une règle déjà prise : les
actus s'auto-publient au merge sur `main`, donc **le diff relu est le garde-fou**. Une console qui
commiterait seule le supprimerait.

## Le carnet de hotfix

Un geste correctif n'est pas un bouton, c'est une **fiche à quatre champs écrite à froid** : ce que
ça fait, ce que ça coûte, comment savoir que ça a marché, comment revenir en arrière. `hotfix.mjs`
les tient en données pures ; l'interface affiche la fiche à côté du bouton. On les écrit calme, on
les lit à 23 h.

| Geste | Coût | Vérification | Retour arrière |
|---|---|---|---|
| Couper / rouvrir les contributions | immédiat, tous les clients | `kill-switch` sans argument | le geste inverse |
| Republier le contenu | toute collection modifiée est retéléchargée par tous | `cdn-versions.json` + GET sur le fragment | republier depuis le commit d'avant |
| Redéployer une edge function | **une fonction non déployée rend l'ANCIENNE réponse** — invisible | `drift.mjs`, ou la sonde 409 | redéployer le commit précédent |
| Reconstruire les fragments communauté | sans ça, un déploiement qui change la *forme* du fragment ne bouge rien pendant une heure | comparer un fragment | sans objet — idempotent, reconstruit depuis l'état courant de la base |
| Appliquer les migrations | écrit en base | `privileges_test.sql`, lecture pure, sûre en prod | **une migration inverse à écrire** |
| Basculer `contentBaseURL` | sortie de secours vers un autre hébergeur, sans mise à jour de l'app | lire `app_config` | `content-source off` |

**Une bascule d'`app_config` n'est PAS instantanée**, et c'est le pire endroit où se tromper.
Vérifié le 2026-08-07 dans `NeonCompass/Core/Config/SupabaseAppConfig.swift` : les valeurs sont
mémorisées dans `cached`, **sans durée de vie**, et le seul `invalidate()` du fichier **n'a aucun
appelant dans l'app**. Une valeur ne rejoint donc un utilisateur qu'à son **prochain lancement à
froid**. Le coupe-circuit communauté et le basculement de `contentBaseURL` portent cette latence
dans leur fiche ; la présenter comme un coupe-circuit immédiat serait un mensonge utile jusqu'au
jour où il compte.

Deux règles tiennent le carnet :

**Un geste dont on ne sait pas énoncer le retour arrière n'entre pas au carnet** — il reste une
commande au terminal. « Sans objet, l'opération est idempotente » est une réponse valable ; « je ne
sais pas » ne l'est pas. Les migrations sont le cas limite : leur retour arrière est « une migration
inverse à écrire ». C'est honnête, et c'est pourquoi elles gardent `dry-run` à `true`.

**Le défaut de tout champ dangereux est le sûr.** `dry-run: true`, comme dans les workflows. Le
passage au réel est un second clic avec confirmation, comme les actions `destructive` d'aujourd'hui.

## Erreurs

Une défaillance dit **quoi faire**, pas seulement ce qui a raté :

**Bug trouvé et corrigé en route.** `credentialsPresent()` testait
`FIREBASE_SERVICE_ACCOUNT_PATH`, resté de l'avant-migration : depuis la bascule vers Supabase du
2026-08-02, la CLI lit `SUPABASE_URL` et `SUPABASE_SERVICE_ROLE_KEY`. La console bloquait donc
**toutes** ses actions de production sur une variable que plus rien ne pose, en renvoyant vers une
documentation Firebase. C'était la seule occurrence restante de ce nom dans `tools/`.

| Défaillance | Message |
|---|---|
| `gh` absent ou non authentifié | le dit, et donne `gh auth login` |
| credentials Supabase absents | `credentialsPresent()`, corrigé, étendu aux nouvelles cartes |
| `PUT` refusé par le schéma | l'erreur ajv brute |
| fichier bougé sur le disque | « changé depuis l'ouverture », avec un bouton recharger |
| workflow qui ne part pas | le message de `gh`, tel quel |

## Tests

En `node --test`, comme `actions.test.mjs`.

1. **Champs typés** — `since=2` passe ; `since=2; rm -rf /` refusé ; un champ non déclaré refusé.
2. **Porte édition** — `kind` hors liste, `id` contenant `../`, fichier inexistant, JSON invalide au
   schéma : refusés, et **rien n'est écrit**.
3. **Concurrence** — empreinte périmée, refus.
4. **Verdict de Récolte** — un journal réel où le hub a échoué rend `partielle` ; un journal vide
   rend `indéterminé`, jamais `complète`.
5. **Tri en trois piles** — les 6 rumeurs atterrissent dans « retenu par une règle » avec leur
   motif, jamais dans « attend ta décision ». Ce test échoue si l'évaluation « comme si publié » est
   oubliée : c'est son objet même, et il doit être vu échouer avant d'être cru.

Les tests 2, 4 et 5 ont le même objet : vérifier qu'un contrôle sait **refuser**. Un contrôle qui ne
sait qu'approuver est indiscernable d'un contrôle absent — il doit donc être vu mordre avant qu'on
lui fasse confiance.

## La disposition réarrangeable

*Ajouté le 2026-08-07, après la première livraison.*

Neuf sections, une page de 3 600 px : l'ordre imposé ne convient à personne très longtemps.
L'en-tête de chaque section est sa poignée — on la glisse dans sa colonne ou vers l'autre, on la
clique pour la replier. Ordre, colonne et état replié vivent dans `localStorage`.

### La réconciliation, et pourquoi elle existe

`ui/layout.mjs` ne connaît pas le DOM : il reçoit la liste des sections réellement présentes et rend
un rangement. **Le code fait autorité sur ce qui EXISTE, le rangement mémorisé seulement sur
l'ORDRE.**

Sans cette règle, ajouter une section un jour la rendrait invisible chez quiconque a rangé sa page
une fois — et rien ne le signalerait. Trois garanties, chacune testée : toute section connue
apparaît exactement une fois ; une section absente du mémorisé rejoint **sa colonne d'origine**
plutôt que la fin ; un identifiant inconnu disparaît. Un rangement corrompu retombe sur le défaut
sans chercher à deviner ce qu'il voulait dire.

### Le glisser-déposer HTML5 a été essayé, puis écarté

Trois raisons, dont une seule aurait suffi :

1. **Il n'est pas pilotable.** Sous Chromium, un `dragstart` déclenché par des événements
   synthétiques part puis rend la main à la boucle de glissement de l'OS, qui ne reçoit jamais les
   mouvements : on observe `dragstart` puis `dragend`, sans le moindre `dragover`. `page.dragAndDrop`
   n'amorce même pas le glissement. Un contrôle qu'on ne peut pas exercer est un contrôle auquel on
   ne peut pas se fier.
2. Il oblige à poser puis retirer `draggable` autour de chaque appui, sans quoi le texte des sections
   devient insélectionnable.
3. Il fait dépendre la distinction clic/glissement d'un détail — « aucun `click` n'est émis après un
   `dragstart` » — au lieu d'un seuil qu'on choisit.

Le geste est donc piloté aux **événements de pointeur**, avec un seuil de 5 px : en deçà c'est un
clic, donc un repli ; au-delà c'est un rangement. La règle est explicite, et elle se teste.

### La géométrie sort du navigateur

`colonneSous(x, boites)` et `insertionAvant(y, boites)` prennent des rectangles et rendent des index.
C'est la partie qui décide où une section tombe, donc la plus faillible — et **Playwright n'est pas
une dépendance de ce projet**, ce qui aurait laissé cette logique sans filet. Les deux fonctions sont
couvertes par des tests unitaires ; le câblage des écouteurs, lui, a été vérifié une fois au
navigateur à la main.

### Deux conséquences dans la page

`index.html` ne porte plus que le balisage et le style : les 500 lignes de script sont dans
`ui/console.js`, qui importe `layout.mjs` — pour que la règle de réconciliation n'existe qu'à un seul
endroit. Le serveur les sert par une **liste blanche de fichiers**, jamais par un chemin venu de la
requête : `join(HERE, url.pathname)` aurait suffi et aurait été la porte par laquelle on lit `.env`
un jour.

Et la **Sortie se déplie et vient sous les yeux** quand une commande part. C'était la vraie gêne :
cliquer un bouton dans une colonne et voir le résultat s'écrire dans l'autre, hors écran. Ce dépli
n'est pas mémorisé — montrer un résultat est un geste de la console, pas une préférence de
l'utilisateur.

## Onglets, livraison, graphes

*Ajouté le 2026-08-07, après retour d'usage.*

### La régression du repli, et sa cause

Le repli au clic sur l'en-tête était une faute. Neuf clics suffisaient à escamoter les vingt-sept
boutons de la console — la page tombait à 430 px, sans la moindre erreur. Deux fautes cumulées :
l'en-tête entier déclenchait un geste qui MASQUE, et rien ne signalait que des sections étaient
cachées. C'est la règle appliquée partout ailleurs ici — *une carte ne ment jamais par omission* —
que le repli violait.

Réparé en trois points : **le chevron seul** replie (l'en-tête reste la poignée de glissement, et un
clic sec n'y fait plus rien) ; un bandeau **« N sections repliées — tout déplier »** apparaît dès
qu'il y en a une ; et chaque onglet porte une pastille comptant ses sections masquées, sans quoi une
section cachée dans un onglet qu'on ne regarde pas resterait invisible.

### Quatre onglets, et la Sortie qui n'en fait pas partie

Le découpage suit ce qu'on **fait**, pas ce que les sections sont : **Revue** (atelier + graphes),
**Veille** (récolte + écritures locales), **Contrôles**, **Pilotage** (carnet + production +
modération). Glisser une section sur un onglet l'y déménage.

La **Sortie vit hors des onglets**, tout en bas : elle porte le résultat de ce qu'on vient de lancer,
et la faire disparaître en changeant d'onglet reprendrait d'une main ce qu'on venait de corriger.

Le modèle de disposition passe donc en `v2` — clé de stockage comprise, sinon un rangement v1 serait
relu comme un v2. `formeValide` rejette la forme v1 même si elle se présentait quand même : deux
garde-fous plutôt qu'un, parce que le premier est une convention et le second une vérification.

### Livrer en un clic

`deliver.mjs` : branche, commit, push, PR ouverte. Ce qui rend la chose compatible avec l'invariant
de la porte « geste » : **la console appelle la commande sans le moindre paramètre.** Titre, message
et corps de PR sont **composés depuis le diff réel** — pas saisis. Un titre libre serait du texte
arbitraire dans un `argv`, sans motif capable de le valider.

Et c'est un meilleur message : il nomme ce qui a réellement changé, y compris ce qu'on avait oublié
avoir touché. Le corps **avertit** quand le merge publiera tout seul (`news`, `online-events`), et
prévient qu'un lot mixte fait refuser `publish-news` en entier — le garde-fou de périmètre est
global, un POI dans le lot et l'actu ne part pas non plus.

La PR **n'est pas fusionnée**. Pour l'actu, le merge publie ; le diff relu reste donc le dernier
garde-fou avant les utilisateurs, et rien ici ne le contourne.

*Panne trouvée en écrivant* : `git()` faisait `.trim()` sur la sortie de `git status --porcelain`, ce
qui **mangeait l'espace de tête** de la colonne d'état (` M chemin`). Les colonnes glissaient d'un
cran et la livraison annonçait « rien à livrer » avec des fichiers modifiés sous les yeux. Corrigé à
la cause, et le parseur ancre désormais sur le chemin plutôt que sur des positions.

#### Une section à elle, et ce qu'elle ne prend pas *(2026-08-08)*

Les deux boutons vivaient dans « Écritures locales », entre un ré-import de carte de référence et un
bundle. Le geste le plus conséquent de la console, rangé comme un utilitaire — et donc introuvable.
Ils ont maintenant leur section, **dans l'onglet Revue, au-dessus de l'atelier**. Au-dessus, alors
que le flux se lit « relire puis livrer » : l'atelier est une liste longue qu'on parcourt, la
livraison un résumé court qu'on consulte. Sous l'atelier, elle tombait 1 400 px plus bas.

La section **montre ce que le bouton ferait**, en permanence, via `GET /api/livraison` — une lecture
pure (`git status`, `git log`). Une répétition n'est utile qu'à qui pense à la lancer ; la question
« qu'est-ce qui partirait ? » doit se lire sans appuyer sur quoi que ce soit.

**Le défaut de fond, corrigé le même jour.** `main()` ne demandait à git que l'état de `content/`.
Une modification de code en attente restait donc dans l'arbre de travail **sans qu'une seule ligne
le dise** : on ouvrait une pull request en croyant l'arbre propre. C'est mentir par omission — la
panne que cette console existe pour supprimer — dans son geste le plus conséquent.

`resteDeCote` répond désormais, en distinguant deux choses qui ne se lisent pas pareil : `content/inbox/`
est **exclu à dessein** (du texte tiers, jamais commité — une règle tenue), tout le reste est
**laissé de côté** et peut être un oubli. Les mélanger apprendrait à ignorer l'avertissement.

Trois lignes puis un décompte, et non la liste entière : le signal est « il en reste », pas les
noms — huit lignes repoussaient le bouton sous la ligne de flottaison d'un portable, ce qui rendait
la section moins utile que le détail qu'elle affichait. La liste complète reste dans la répétition.

*Deuxième panne trouvée en écrivant* : le test « les groupes déclarés sont ceux que la page sait
afficher » lisait une **liste écrite à la main** tout en affirmant, dans son message d'échec,
vérifier `index.html`. Il ne le faisait pas. Il lit maintenant les deux fichiers — la boucle de
rendu dans `console.js`, les conteneurs dans `index.html` — donc il attrape le cas réel : un groupe
dont les boutons n'apparaîtraient nulle part, sans erreur ni avertissement.

### Les graphes de la file de revue

Quatre éléments, et la forme suit le **travail** de la donnée :

| Question | Forme | Couleur |
|---|---|---|
| Combien attendent ? | **nombre**, ≥ 48 px, un seul par vue — pas un graphe à une barre | — |
| Comment ça se répartit ? | barre empilée (part-à-tout) | **statut** : attend / retenu / cassé |
| Depuis quand ? | colonnes sur tranches d'âge | **ordinale** : une seule teinte, rampe monotone |
| Pourquoi retenus ? | barres horizontales (noms longs) | **nominale** : toutes la même teinte |

Deux décisions qui se **calculent** plutôt qu'elles ne s'apprécient :

- Les tranches d'âge sont **ordinales**, pas nominales : leur ordre porte du sens. Elles prennent
  donc une rampe à une seule teinte, validée par `validate_palette.js --ordinal` contre le fond
  `#141a28`. Le premier jet échouait à 1,91:1 sur le pas le plus sombre ; la rampe retenue
  (`#256976 → #3aeaf4`) passe à 2,78:1, monotone, écarts ΔL ≥ 0,06.
- Les motifs de retenue sont **nominaux** : tous la même teinte. Les colorer par leur valeur
  dépenserait le canal d'identité pour redire ce que la longueur de la barre montre déjà.

Et une contrainte d'accessibilité qui n'est pas négociable : les trois couleurs de statut déjà en
place dans la console sont à **ΔE 6,6 en deutéranopie** (amber ↔ lime), soit dans la bande plancher
6–8 — autorisée *uniquement* avec encodage secondaire. **Les étiquettes chiffrées de la légende sont
donc obligatoires, pas décoratives** : sans elles, la répartition serait illisible pour un lecteur
deutéranope.

L'étiquette d'axe est courte ; le message exact du validateur part dans l'infobulle. L'axe a besoin
d'être lisible, le diagnostic d'être précis — les deux, pas l'un ou l'autre. Aucune valeur n'est
lisible *seulement* au survol.

## Les métriques Supabase, et le moniteur du Raspberry Pi

*Ajouté le 2026-08-08.* Deux demandes qui n'en font qu'une : voir la production en graphes, et
pouvoir regarder ces graphes ailleurs que devant le Mac.

### Le conflit qu'il fallait résoudre d'abord

Le cadrage du 2026-08-07 disait « Mac uniquement », et toute la sécurité de la console en découle :
elle n'a **aucune authentification** parce qu'elle écoute sur `127.0.0.1`. La porte « geste » lance
`gh workflow run`, `git push` et des migrations ; sur un Pi, elle devient joignable par tout ce qui
traîne sur le LAN.

Décision : **couper en deux, pas assouplir.** Le moniteur est un service séparé, en lecture pure ;
la console d'écriture ne bouge pas. Un *mode* de la console aurait laissé le code d'écriture présent
dans l'image, à un `if` de distance.

La phrase qui remplace « personne ne peut appeler » est donc **« il n'y a rien à appeler »**, et
c'est un test : `tools/monitor/imports.test.mjs` échoue si une source du dossier importe
`child_process`, `@supabase/supabase-js`, ou `../content-cli` ; si elle appelle une écriture
disque ; ou si le serveur mentionne autre chose qu'un GET. Les quatre mutations ont été jouées.

### La porte des nombres

Trois façons de donner des chiffres au Pi, et la troisième est la seule qui tienne :

1. `service_role` sur la carte SD — contourne RLS, donc perdre le Pi c'est perdre la base ;
2. un rôle Postgres en SELECT — mieux, mais il lit des **lignes** : titres, pseudonymes, uid ;
3. une Edge Function `metrics` qui agrège côté serveur et ne rend que des **décomptes**.

Le Pi ne détient donc qu'un jeton dont tout le pouvoir est de demander « combien ». La promesse est
tenue par un test, pas par une intention : `fuitesDe` parcourt un instantané complet et échoue si
une chaîne apparaît là où on attendait un nombre. Mutation jouée — le type refuse d'abord le champ
en trop, et le test l'attrape même quand on le force par un `as unknown`.

Deux serrures sur la fonction : `verify_jwt` **reste activé** (le trafic anonyme n'atteint jamais
notre code) et `X-Monitor-Token`, comparé en temps constant. La clé publiable étant dans le binaire
de l'app, la première ne prouve rien seule. Secret absent ⇒ **503**, jamais un 200 permissif.

### La console passe par le même chemin

Elle a pourtant `service_role` sous la main. Elle appelle quand même la fonction, pour que **le
chemin du Pi soit exercé tous les jours depuis le Mac** au lieu d'être découvert cassé sur une
étagère. Le coût est une dépendance de déploiement ; le bénéfice est qu'une régression a un endroit
où se voir.

### Les graphes retenus

Le critère est celui du tableau de bord : *qu'est-ce qui attend quelque chose de moi ?*

- **la file de modération** — décompte en tête, ancienneté par tranches (rampe ordinale, réutilisée
  telle quelle de l'atelier), répartition par catégorie. Les **signalées** sont comptées à part :
  le suivi de vélocité les marque sans bloquer personne, donc elles restent visibles des joueurs
  pendant qu'elles attendent — les noyer dans le total reviendrait à ne pas les avoir marquées ;
- **arrivées et approbations sur trente jours** — la seule vraie série temporelle disponible, parce
  que `created_at` et `approved_at` existent. Deux courbes, **un seul axe** ;
- **ce qui est bloqué** — fragments communautaires périmés, file de notifications coincée. Des
  pannes qui ne cassent rien : elles servent l'ancienne réponse ;
- **les totaux** — cinq tuiles, pas des barres : comparer des votes à des profils ne veut rien dire.

Un compteur qui n'a pas répondu s'affiche `—`, jamais `0`.

### Ce que la courbe ne dit pas, et qui est écrit à côté

Un refus ne laisse **aucune date** en base : `contributions` porte `approved_at`, il n'y a pas de
`rejected_at`. La courbe compte donc les approbations, pas les décisions, et sous-estime le travail
fait. Le sous-titre du graphe le dit ; le décompte en attente, lui, est exact et fait foi. Un
`rejected_at` réglerait la question — non fait, et volontairement pas glissé dans ce chantier.

Toujours pas d'évolution du backlog **éditorial** : rien ne journalise les transitions des
brouillons, et une courbe serait inventée.

### Les couleurs, encore une fois calculées

Le couple de départ — le cyan et le magenta de la console — **échouait** à la bande de clarté du
mode sombre (L 0,845 et 0,697 pour une bande 0,48–0,67). Un premier candidat corrigé, `#b8006d`,
donnait le meilleur écart CVD (15,1) mais tombait à **2,7:1** de contraste : un avertissement qui ne
se congédie pas. Retenu : `#00a9b4` / `#ac3b73`, six contrôles au vert, ΔE 13,6 en deutéranopie.

### Le durcissement du conteneur n'est pas décoratif

Ce service écoute sur le LAN sans authentification. `read_only`, `cap_drop: ALL`,
`no-new-privileges`, uid 1000, plafonds mémoire et pids, journaux plafonnés — chaque ligne retire
une capacité dont il n'a aucun usage. Cinq fichiers copiés **un par un** : un `COPY . .` embarquerait
tout ce que quelqu'un déposerait un jour dans le dossier, `.env` compris. Aucune dépendance npm,
donc rien à auditer côté chaîne d'approvisionnement. Vérifié en exécution : écriture refusée, `git`
absent, sonde `healthy`.

La sonde interroge le **processus**, pas Supabase : un conteneur qui redémarrerait en boucle parce
que le réseau est tombé remplacerait un tableau de bord qui dit « injoignable » par un écran noir.

Et l'âge du dernier relevé **réussi** est affiché en permanence, parce qu'un tableau de bord figé et
un tableau de bord calme ont exactement la même tête.

## La CLI, et le bouton Fermer *(2026-08-08)*

### La régression, et sa cause exacte

Passer la boîte d'édition en colonne flex pour réparer son défilement a cassé sa fermeture.
La feuille du navigateur ferme un `<dialog>` avec `dialog:not([open]) { display: none }` — mais
**une règle d'auteur l'emporte sur celle du navigateur, quelle que soit sa spécificité**. Le
`display: flex` annulait donc la fermeture : « Fermer » mettait bien `open` à faux, et la boîte
restait à l'écran. Elle était même visible avant la première ouverture.

Deuxième défaut du même changement : « Écarter », posé juste avant « Fermer », tombait
exactement là où « Fermer » se trouvait la veille. **Le geste irréversible héritait de la
position du geste inoffensif.** Il vit maintenant avant le message, qui l'écarte des trois
autres — et les trois retrouvent leurs abscisses d'origine (986, 1071, 1179 px).

Le CSS n'a pas de suite de tests ici, donc deux tests lisent la feuille : l'un exige la règle de
fermeture dès qu'un `display` est imposé à `dialog`, l'autre vérifie l'ordre du pied.

**Le piège, rencontré deux fois dans la même journée** : un test qui cherche une règle dans le
texte brut est satisfait par le COMMENTAIRE qui l'explique. La première version du test passait
alors même qu'on retirait la ligne de code — c'est ma propre documentation qui la désarmait. Les
deux tests retirent maintenant les commentaires avant de chercher, comme
`tools/monitor/imports.test.mjs` avait déjà dû le faire.

### La CLI : une aide qui ne peut plus mentir

La ligne d'usage était une chaîne de 400 caractères recopiée à deux endroits, et **elle était
fausse** : elle proposait `deploy-rules`, disparu quand les règles d'accès sont devenues des
politiques RLS, et taisait `bundle`, `check-seeds`, `release`, `deploy-cdn`. Une aide fausse est
pire qu'une aide absente — l'absence envoie lire le code, le mensonge envoie taper une commande
qui n'existe pas.

La liste vit maintenant dans `commands.mjs`, une seule fois, et `commands.test.mjs` la compare
aux `case` du `switch` **dans les deux sens** : une commande sans traitement échoue, un
traitement non déclaré aussi. Les deux mutations correspondantes ont été jouées.

Ce qui change à l'usage : `cli.js help` groupe les commandes par moment de la journée (regarder,
récolter, contrôler, publier, modérer) ; `cli.js help <commande>` donne la forme, les pièges et
des exemples ; une faute de frappe propose la commande la plus proche, et **ne propose rien**
quand rien n'est assez proche — envoyer sur une fausse piste coûte plus cher que se taire.

### `news` — voir avant de vérifier

Il n'existait aucun moyen de REGARDER le contenu en ligne de commande : `validate` dit si c'est
valide, `check-publishable` si c'est publiable, rien ne disait « qu'est-ce qu'il y a ».

```
cli.js news --days 7
cli.js news --since 2026-08-01 --status draft
cli.js news --json | jq -r '.[].id'
```

Les dates portent sur `publishedAt`, jamais sur la date du fichier. `--days N` compte
**aujourd'hui comme premier jour** : `--days 1` rend les actus du jour, sinon on lirait « aucune
actu » le jour où l'on vient d'en publier trois.

Trois refus plutôt que trois silences : une date mal formée, un intervalle inversé et un
`--days` absurde sont des erreurs. Chacun, ignoré, aurait rendu une liste qui ment — et le pire
est l'intervalle inversé, qui rendrait « aucune actu » sur une simple inversion de saisie.

`news` et `help` s'exécutent **avant** le chargement de `content/` : c'est précisément quand un
fichier est cassé qu'on a besoin de lister le contenu et de lire l'aide.

## Hors périmètre

Nommé pour ne pas y revenir par accident :

- **éditeur libre d'`app_config`** — les valeurs ne changent que sous un geste nommé du carnet ;
- **atelier POI** — second schéma à rendre en formulaire, avec des coordonnées, donc probablement
  une carte pour les vérifier. Élargit sérieusement le chantier ;
- **Grafana** — geste de pré-lancement, monté tel quel, jamais modifié ;
- **tout chemin de commit ou de fusion automatique** — le diff relu est le garde-fou de l'actu ;
- **la console d'écriture sur le Pi** — écarté le 2026-08-08 : il faudrait construire une
  authentification qui n'existe pas, et la carte SD deviendrait l'endroit le plus sensible de
  l'installation (`service_role`, jeton GitHub, clone avec droit de push) ;
- **`rejected_at`** — réglerait la sous-estimation de la courbe d'approbations. Une migration, donc
  un chantier à part.
