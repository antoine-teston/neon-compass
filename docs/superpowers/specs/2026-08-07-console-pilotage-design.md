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

*Note* : la mémoire projet indique que l'autorité serait `weekly.json`, déposé par `--capture`
depuis la branche `veille/hub-verdicts`. Vérifié le 2026-08-07 : **ce code n'existe nulle part dans
le dépôt**, et la branche n'a rien d'avance sur `main`. Le travail n'a pas atterri. La lecture du
journal reste donc l'autorité ; `weekly.json` deviendra la source bon marché s'il arrive.

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

Deux règles tiennent le carnet :

**Un geste dont on ne sait pas énoncer le retour arrière n'entre pas au carnet** — il reste une
commande au terminal. « Sans objet, l'opération est idempotente » est une réponse valable ; « je ne
sais pas » ne l'est pas. Les migrations sont le cas limite : leur retour arrière est « une migration
inverse à écrire ». C'est honnête, et c'est pourquoi elles gardent `dry-run` à `true`.

**Le défaut de tout champ dangereux est le sûr.** `dry-run: true`, comme dans les workflows. Le
passage au réel est un second clic avec confirmation, comme les actions `destructive` d'aujourd'hui.

## Erreurs

Une défaillance dit **quoi faire**, pas seulement ce qui a raté :

| Défaillance | Message |
|---|---|
| `gh` absent ou non authentifié | le dit, et donne `gh auth login` |
| credentials Supabase absents | réutilise `credentialsPresent()`, étendu aux nouvelles cartes |
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

## Hors périmètre

Nommé pour ne pas y revenir par accident :

- **éditeur libre d'`app_config`** — les valeurs ne changent que sous un geste nommé du carnet ;
- **atelier POI** — second schéma à rendre en formulaire, avec des coordonnées, donc probablement
  une carte pour les vérifier. Élargit sérieusement le chantier ;
- **Grafana** — geste de pré-lancement, monté tel quel, jamais modifié ;
- **tout chemin de commit ou de fusion automatique** — le diff relu est le garde-fou de l'actu.
