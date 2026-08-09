# Console de pilotage — référence des fonctions

Ce document décrit **ce que fait chaque fonction** de la console : les 29 actions,
les 13 sections, les 4 onglets, les 10 routes HTTP. Il complète deux textes qui
existent déjà et ne les répète pas :

- **Comment la lancer** → `docs/ops/2026-08-08-console-en-conteneur.md`
- **Pourquoi elle est faite ainsi** → `docs/superpowers/specs/2026-08-07-console-pilotage-design.md`

Adresse : <http://127.0.0.1:4321>, en conteneur (`neon-console`) comme en local
(`cd tools/content-cli && npm run ui`).

---

## 1. Le modèle de sécurité, en deux phrases

Tout le reste du document en découle, et aucune fonction n'y échappe.

**Porte « geste » — `POST /api/run`.** Rien du corps de la requête n'atteint une
ligne de commande, hors **paramètres déclarés** validés par motif. Un paramètre
non déclaré est un refus, jamais un laissez-passer. `spawn` est appelé **sans
shell**, et le binaire vient de la déclaration de l'action, jamais de la requête.

**Porte « édition » — `/api/draft/:kind/:id`.** Elle n'exécute **aucun
processus** : ni `spawn`, ni `execFile`, ni ici ni dans ce qu'elle importe. Il n'y
a donc rien à injecter — pas « rien d'exploitable », rien du tout, par
construction.

Trois garde-fous, par ordre d'importance : l'écoute sur `127.0.0.1` ; les deux
invariants ci-dessus ; la confirmation explicite exigée des actions de
production. La console **n'a aucune authentification** — le préfixe d'écoute est
tout ce qui la protège.

---

## 2. Les quatre onglets

Le découpage suit ce qu'on **fait**, pas ce que les sections sont : on ouvre la
console pour relire des brouillons, ou pour lancer une récolte, ou pour éteindre
un incendie — rarement pour les trois.

| Onglet | Colonne 1 | Colonne 2 |
|---|---|---|
| **Revue** | Livraison, Atelier des brouillons | File de revue, File communautaire |
| **Veille** | Récolte | Écritures locales |
| **Contrôles** | Contrôles, Santé de la production | Inventaire |
| **Pilotage** | Carnet de hotfix | Production, Modération |

La section **Sortie** vit hors des onglets, tout en bas : elle porte le résultat
de ce qu'on vient de lancer, et la faire disparaître en changeant d'onglet
reprendrait d'une main ce qu'on venait de corriger.

Les sections se déplacent au glisser-déposer, entre colonnes et entre onglets, et
se replient. Le rangement est mémorisé (`localStorage`, clé versionnée
`…-disposition-v2`), avec une règle qui évite la panne silencieuse habituelle :
**le code fait autorité sur ce qui existe, le rangement mémorisé seulement sur
l'ordre.** Une section ajoutée au code apparaît donc chez qui a déjà rangé sa
page ; un identifiant devenu inconnu disparaît. « Tout déplier » existe parce
qu'une section repliée est une omission, et qu'une omission doit avoir une sortie
visible.

### L'indicateur d'onglet

Chaque onglet affiche ce qu'il a à dire sans qu'on l'ouvre, sur cinq niveaux
(`bon`, `neutre`, `inconnu`, `attention`, `grave`), et selon trois règles :

1. **Aucun indicateur ne ment par omission.** Une donnée absente donne `inconnu`
   et un `?`, jamais un zéro.
2. **Le sens ne repose jamais sur la couleur** — les trois teintes de statut sont
   à ΔE 6,6 en deutéranopie. Chaque indicateur porte un chiffre ou un mot ; le
   niveau ne fait que le teinter.
3. **Une file n'est pas une alerte.** Treize actus à relire, c'est du travail.
   Ce qui mérite l'ambre, c'est l'**ancienneté** (seuil : 14 jours) ou une panne
   franche. Alerter sur le volume apprendrait à ignorer l'alerte.

Un onglet qui n'a rien à dire n'affiche **rien**, plutôt qu'un « OK » qui
ajouterait du bruit à une barre qu'on lit en diagonale.

---

## 3. Les 29 actions

Colonnes : **Prod** = écrit en ligne, exige une confirmation explicite ;
**Cred** = exige `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` ; **Dépôt** = écrit
dans les fichiers du dépôt.

### Contrôles — aucune écriture (6)

| Action | Ce qu'elle fait |
|---|---|
| `validate` | Valide tous les fichiers de contenu contre leurs schémas |
| `check-publishable` | Règles éditoriales : marques déposées, cheats corroborés par deux sources |
| `check-seeds` | Détecte un `seed-poi.json` en retard sur `content/` — invisible autrement |
| `translate-dry` | Liste les champs ES/IT/DE absents |
| `release-dry` | Tous les contrôles, plus le diff qui partirait. N'écrit rien |
| `tests` | Tests de frappe des identifiants de POI — un id publié ne doit jamais désigner un autre POI |

### Écritures locales — le dépôt, pas la production (5)

| Action | Ce qu'elle fait | Dépôt | Cred |
|---|---|:-:|:-:|
| `bundle` | Régénère `collections.json` depuis `content/collections` | ✓ | |
| `pull-drafts` | Matérialise en fichiers `content/poi` ce qui a été posé au doigt dans l'éditeur | ✓ | ✓ |
| `pull-news` | Transforme les faits de `content/inbox` en squelettes à rédiger. **Idempotent** | ✓ | |
| `pull-online-events` | Idem pour les événements en ligne | ✓ | |
| `import` | Ré-importe la carte de référence depuis les dumps amont. **Long, et réseau** — les ids existants sont réutilisés | ✓ | |

### Livraison (2)

| Action | Ce qu'elle fait | Dépôt |
|---|---|:-:|
| `deliver-dry` | Montre la branche, le titre et les fichiers qui partiraient. N'écrit rien | |
| `deliver` | Branche, commite, ouvre la PR. Titre et corps **composés depuis le diff** — rien de saisi. **La PR n'est pas fusionnée** | ✓ |

### GitHub (1)

| Action | Ce qu'elle fait | Paramètres |
|---|---|---|
| `recolte` | Déclenche le workflow de Récolte sur `main` | `since` (défaut 2), `max` (défaut 15) — entiers, 3 chiffres max |

La Récolte **ne peut pas tourner en local** : la passerelle de sortie des sessions
d'agent refuse le CONNECT sur les quatre sources du registre. Le runner CI est le
seul endroit d'où elles répondent. **Son verdict se lit dans le journal, pas dans
le statut** — voir §6.

### Production — écrit en ligne (3)

| Action | Ce qu'elle fait | Prod | Cred |
|---|---|:-:|:-:|
| `release` | Contrôles, construction du site, téléversement CDN. Toute collection modifiée est retéléchargée par les clients | ✓ | ✓ |
| `kill-switch-status` | Lit l'état du coupe-circuit communauté | | ✓ |
| `content-source-status` | Lit `contentBaseURL` dans `app_config` | | ✓ |

Il n'existe **pas** d'action de déploiement des règles d'accès : les politiques
RLS sont versionnées dans `supabase/migrations/`, appliquées par `supabase db
push` et relues en pull request. Une console web n'a pas à pouvoir les remplacer
d'un clic.

### Carnet de hotfix (7)

Détaillé en §4 — chaque geste y porte sa fiche.

### Modération (5)

La vraie plus-value d'une interface : lister puis agir sur une ligne, au lieu de
recopier des identifiants dans un terminal.

| Action | Ce qu'elle fait | Prod | Cred | Id |
|---|---|:-:|:-:|:-:|
| `moderate:list` | Liste les contributions en attente | | ✓ | |
| `moderate:approve` | Approuve une contribution | ✓ | ✓ | ✓ |
| `moderate:reject` | Rejette une contribution | ✓ | ✓ | ✓ |
| `shadow-ban` | Masque aussi les spots **déjà approuvés** de cet auteur | ✓ | ✓ | ✓ |
| `lift-shadow-ban` | Lève le shadow-ban | ✓ | ✓ | ✓ |

L'identifiant passe `^[A-Za-z0-9_-]{1,128}$` — assez permissif pour un UUID de
contribution comme pour un uid de compte, assez strict pour exclure tout ce qui
ressemble à un chemin, un espace ou un métacaractère. Il part dans son propre
élément d'`argv`, donc reste inoffensif même s'il contenait des métacaractères.

### La règle des credentials, qui surprend une fois

Les actions qui passent par `gh` — `recolte`, `deploy-function`,
`republish-bundles`, `migrations-*` — **n'exigent pas** les credentials Supabase,
même quand elles sont marquées production. Leur pouvoir est celui du jeton
GitHub ; exiger une clé sans rapport ferait échouer un correctif pour une
mauvaise raison.

---

## 4. Le carnet de hotfix

Un geste correctif n'est pas un bouton : c'est une fiche à quatre champs — **quoi,
coûte, vérifier, revenir** — écrite à froid et lue à 23 h. La règle qui tient le
carnet : **un geste dont on ne sait pas énoncer le retour arrière n'y entre pas.**
« Sans objet, l'opération est idempotente » est une réponse valable ; « je ne sais
pas » ne l'est pas.

L'ordre n'est pas alphabétique — c'est celui dans lequel on tend la main pendant
un incident : arrêter l'hémorragie, puis réparer, puis republier.

| # | Geste | Action | Coûte | Vérifier | Revenir |
|:-:|---|---|---|---|---|
| 1 | **Couper les contributions** | `kill-switch-off` | Les spots déjà approuvés restent visibles ⚠️ | « État du coupe-circuit » → `DISABLED` | Le geste inverse |
| 2 | **Rouvrir les contributions** | `kill-switch-on` | ⚠️ | « État du coupe-circuit » → `ENABLED` | Le geste inverse |
| 3 | **Redéployer une edge function** | `deploy-function` | Une fonction non déployée ne casse rien — elle rend l'**ancienne** réponse, invisible tant qu'on ne compare pas. Le déploiement lit `config.toml`, donc les `verify_jwt = false` survivent | `tools/edge-functions/drift.mjs` ne la signale plus. Sonde sans écriture : resoumettre à la même position donne un 409 dont on lit le corps — `code` absent = ancienne version | Redéployer depuis le commit précédent |
| 4 | **Reconstruire les fragments communauté** | `republish-bundles` | À faire après un déploiement qui change la **forme** du fragment. Sans lui, la reconstruction n'agit que sur changement d'une contribution ou après une heure : le déploiement paraît sans effet, indéfiniment | Comparer un fragment publié au champ attendu | Sans objet — idempotent |
| 5 | **Migrations — lister sans appliquer** | `migrations-dry` | Aucun. C'est la répétition, à faire avant l'autre | La sortie liste les migrations en attente | Sans objet — n'écrit rien |
| 6 | **Migrations — appliquer** | `migrations-apply` | Écrit en base. Une migration appliquée ne se retire pas | `supabase/tests/privileges_test.sql` — lecture pure, sûr contre la production ; le workflow le lance lui-même après | **Une migration inverse à écrire, relire et appliquer.** Il n'y a pas de bouton — c'est précisément pourquoi la répétition existe |
| 7 | **Basculer la source de contenu** | `content-source` | « off » rend l'app à son socle embarqué, donc au contenu figé du binaire ⚠️ | « Source de contenu actuelle » → la nouvelle valeur | Reposer l'ancienne valeur, ou « off » |

⚠️ **Ce que la latence d'`app_config` change à tout ce tableau.** Les valeurs sont
mises en cache côté app **sans durée de vie**, et le seul `invalidate()` du
fichier n'a aucun appelant. Conséquence à ne pas découvrir pendant un incident :
**une bascule d'`app_config` n'atteint un utilisateur qu'à son prochain lancement
à froid.** Ce n'est pas un coupe-circuit instantané, et le présenter comme tel
serait le pire endroit où se tromper. Cela vaut pour les gestes 1, 2 et 7.

Le paramètre du geste 7 n'accepte que `off` ou une URL **HTTPS** (300 caractères
max) — surtout pas `http`, qui ferait servir du contenu en clair à tous les
clients. Le geste 3 n'accepte qu'un nom de dossier `^[a-z0-9-]{1,64}$`.

---

## 5. L'atelier des brouillons

Ouvre `news` et `online-events`. **Les POI n'y sont pas** : leur schéma demande
des coordonnées, donc une carte pour les vérifier — nommé hors périmètre plutôt
que laissé à demi fait.

### Trois piles, et non une liste

| Pile | Ce qu'elle contient |
|---|---|
| **Attend ta décision** | Publiable en l'état — rien ne s'y oppose |
| **Retenu par une règle** | Une règle éditoriale s'y oppose, et la règle est **nommée** |
| **Cassé** | JSON illisible, ou schéma non respecté |

**Le piège du tri, à ne pas resimplifier.** Presque toutes les règles de
`problemsFor` ne mordent que sur `status === 'published'` : interroger un
**brouillon** avec elles le déclare publiable à tous les coups. Le tri appelle
donc `problemsIfPublished`, qui les évalue *comme si* l'item l'était. Remplacer
l'un par l'autre range les rumeurs dans « attend ta décision » — c'est-à-dire
exactement le bruit que cette console existe pour supprimer. Deux tests tombent,
exprès.

Chaque ligne porte sa date, son titre et **sa première source**, cliquable :
relire une actu, c'est presque toujours la comparer à ce dont elle sort.

### L'écran d'un item

À gauche, les **faits** — `sourceClaim`, `sources`, `processedFrom` — **jamais
éditables**. Ce n'est pas de la mise en page : le fait cite ses sources mot pour
mot, marques déposées comprises, et la contrainte IP du projet interdit qu'il se
retrouve recopié dans la prose. Les rendre non éditables rend le geste impossible
par inadvertance.

À droite, les champs en formulaire — `title`, `body`, `category`, `confidence`,
`status` pour une actu ; `title`, `confidence`, `status` pour un événement. Les
valeurs des énumérations sont **lues dans le schéma**, jamais recopiées, sinon
elles divergeraient au premier ajout. Tout le reste reste éditable en JSON brut,
validé par le même schéma.

### Publier, dépublier, écarter

**La publication n'a pas de chemin à part** : il suffit de passer `status:
"published"`. Les règles s'appliquent alors pour de bon et refusent une rumeur ou
un squelette non rédigé. Un seul chemin d'écriture signifie un seul endroit où se
tromper. Le sélecteur de statut rend le geste **réversible** — avant son ajout, le
seul geste possible était le bouton « Publier », donc un aller sans retour.

**Écarter** supprime le fichier, avec trois refus, dont le premier est le seul qui
compte vraiment :

1. **jamais un `published`** — son fragment vit déjà sur le CDN. Supprimer le
   fichier ne le retire pas de chez les clients, ça retire seulement la trace de
   ce qui a été publié. Pour retirer une actu en ligne : la repasser en `draft`,
   **republier**, puis écarter ;
2. l'empreinte doit correspondre ;
3. le fichier doit exister.

La suppression n'est pas silencieuse : elle apparaît dans `git status`, donc dans
le panneau Livraison, donc dans une PR relue.

### L'empreinte, qui évite de perdre du travail

Toute écriture et toute suppression portent l'empreinte SHA-256 du fichier tel
qu'il était **à l'ouverture**. Si le disque a changé depuis, la console refuse
(409) au lieu d'écraser une édition faite au terminal entre-temps.

Deux autres refus : l'identifiant **ne peut pas changer** (`pull-news` le frappe
sur le contenu du fait pour être idempotent ; le laisser bouger casserait cette
propriété), et le fichier **doit déjà exister** — l'atelier corrige, il ne crée
pas. La création reste à `pull-news`.

---

## 6. Ce que les sections affichent

### Cartes instantanées — disque seul, à chaque chargement

| Section | Contenu |
|---|---|
| **Atelier des brouillons** | Les trois piles, par kind |
| **File de revue** | Histogramme d'ancienneté (aujourd'hui, 1-3 j, 4-7 j, 8-14 j, +14 j) et motifs de blocage classés. Un item retenu pour plusieurs motifs les compte **tous** |
| **Inventaire** | Par kind : total, publiés, brouillons. Plus le détail des collections |
| **Livraison** | Ce que la livraison ferait, **sans rien écrire** — branche, titre, fichiers. Route à part plutôt qu'un `--dry-run` à lancer : la question « qu'est-ce qui partirait ? » doit se lire sans appuyer sur quoi que ce soit. C'est aussi ce qui révèle ce que la livraison **n'emporte pas** |

La carte des socles lance réellement `check-seeds` plutôt que de dupliquer sa
logique — une règle dupliquée finit par diverger. Un socle en retard n'est **pas**
une indisponibilité : c'est un résultat, et c'est même celui qu'on cherche.

### Cartes réseau — demandées après coup, échouant séparément

Chargées après l'affichage du reste : un jeton absent ou un réseau lent ne doit
pas retarder les brouillons. Une carte qui tombe n'emporte pas les autres.

| Section | Contenu | Ce qu'il lui faut |
|---|---|---|
| **Récolte** | Verdict de la dernière récolte, étape par étape | `gh` authentifié |
| **Santé de la production** | `app_config` en lecture seule : `backendFeaturesEnabled`, `communityContributionsEnabled`, `contentBaseURL`, `interstitialFrequency` · dérive des edge functions | Credentials · `SUPABASE_PROJECT_REF` + `SUPABASE_ACCESS_TOKEN` |
| **File communautaire** | Métriques de production — files, blocages, graphes | `SUPABASE_ANON_KEY` + `MONITOR_TOKEN` |

Les métriques passent par la **même** Edge Function `metrics` que le moniteur du
Raspberry Pi, et non par Postgres avec la clé `service_role` pourtant sous la
main. C'est délibéré : le chemin du Pi est ainsi exercé tous les jours depuis le
Mac, au lieu d'être découvert cassé sur une étagère à l'autre bout de la maison.

**La règle qui compte partout ici : une carte ne ment jamais par omission.** `gh`
non authentifié, credentials absents, réseau tombé — la carte le **dit**, avec un
`indisponible` qui nomme la cause. Elle n'affiche jamais un zéro. « 0 brouillon en
attente » parce qu'un dossier n'a pas pu être lu est exactement la panne qu'on
supprime, pas qu'on déplace.

### Le verdict de la Récolte, et pourquoi il ne lit pas le statut

**L'API GitHub rapporte `conclusion: success` pour une étape en
`continue-on-error` sortie en code 1.** Quatre runs se sont annoncés verts alors
que deux avaient échoué ; le champ qui dirait la vérité (`outcome`) n'est pas
exposé. Le statut ne dit donc rien, et **le journal est la seule autorité**.

La lecture cherche **ce qui doit être là**, pas l'absence d'erreur — chercher
« pas d'erreur » se fait piéger par un journal vide, qui est précisément ce que
produit une chaîne coupée tôt. Quatre marqueurs positifs sont attendus :
préflight, récolte, semaine du mode en ligne, dépôt sur la branche de transport.

Un piège dans le piège : GitHub recopie **chaque commande** dans le journal avant
de l'exécuter, en cyan gras. La ligne contient donc le marqueur même si la
commande n'a jamais tourné. Ces échos sont retirés avant toute recherche.

Quatre issues, et la quatrième n'est **pas** un succès :

| Verdict | Sens |
|---|---|
| `complète` | Les quatre marqueurs sont là |
| `partielle` | Certaines étapes sont muettes — elles sont nommées |
| `échec` | Aucun marqueur : la chaîne n'est pas allée jusqu'au premier résultat |
| `indéterminé` | Journal vide ou illisible. **Jamais « ok »** — un contrôle qui, dans le doute, approuve, ne contrôle rien |

---

## 7. Les routes HTTP

| Méthode | Route | Ce qu'elle rend |
|---|---|---|
| `GET` | `/` | La page. Fichiers servis depuis une **liste blanche** — aucun chemin venu de la requête n'atteint le disque |
| `GET` | `/api/state` | Cartes instantanées, actions publiques, carnet, kinds éditables |
| `GET` | `/api/state/network` | Récolte, `app_config`, dérive des fonctions |
| `GET` | `/api/state/supabase` | Métriques de production, par l'Edge Function |
| `GET` | `/api/livraison` | Aperçu de livraison — **lecture pure**, `git status` / `git log` |
| `GET` | `/api/drafts` | Le triage complet, plus ses statistiques |
| `GET` | `/api/draft/:kind/:id` | Un item : données, empreinte, faits, champs, blocages |
| `PUT` | `/api/draft/:kind/:id` | Réécrit — validation **entièrement** faite avant le premier octet écrit |
| `DELETE` | `/api/draft/:kind/:id` | Écarte |
| `POST` | `/api/run` | Exécute une action, sortie **diffusée au fil de l'eau** avec le code retour en dernière ligne |

Ce que le client reçoit d'une action ne comprend **jamais** l'`argv` ni le
binaire. Le motif de validation n'est pas envoyé non plus : le publier inviterait
à valider côté page plutôt que côté serveur.

### Codes de refus

| Code | Cause |
|:-:|---|
| `400` | Action inconnue, paramètre non déclaré, mal formé, ou identifiant qui change |
| `404` | Kind non éditable, ou item inexistant |
| `409` | Le fichier a changé sur le disque depuis son ouverture · ou : écarter un item publié |
| `412` | Credentials absents |
| `422` | Schéma ou règle éditoriale non respectés |
| `428` | Confirmation requise pour une action de production |

**L'intention avant la capacité.** Une action de production sans confirmation est
refusée (428) *même sans credentials* — l'ordre inverse rendait ce garde-fou
impossible à vérifier sur une machine sans clé. Et la confirmation vit dans le
**corps** de la requête, jamais dans l'URL : un lien partagé ou un rechargement de
page ne peut donc rien déclencher.

---

## 8. Ce que la console ne fait délibérément pas

- **Créer un item de contenu.** L'atelier corrige, il ne crée pas.
- **Ouvrir les POI à l'édition.** Il leur faudrait une carte.
- **Déployer des règles d'accès.** RLS versionné, relu en PR.
- **Fusionner une PR.** `deliver` ouvre, ne fusionne pas.
- **Écrire dans `app_config` hors d'un geste nommé.** Une valeur ne bouge que
  sous un nom qui dit pourquoi.
- **S'authentifier.** Elle n'en a aucune — voir §1.

---

## 9. Où se trouve quoi

| Fichier | Rôle |
|---|---|
| `ui/server.mjs` | Les routes, les deux portes, l'écoute |
| `ui/actions.mjs` | **La liste blanche** — la pièce de sécurité du dispositif |
| `ui/hotfix.mjs` | Le carnet, en données pures |
| `ui/drafts.mjs` | La porte « édition » : tri, lecture, écriture, suppression |
| `ui/state.mjs` | Les cartes du tableau de bord |
| `ui/runs.mjs` | Le verdict des workflows, lu dans le journal |
| `ui/indicateurs.mjs` | Ce que chaque onglet dit de lui-même |
| `ui/layout.mjs` | Onglets, colonnes, réconciliation du rangement |
| `docker/` | Le conteneur, son `.env`, et `verifier-exposition.sh` |

Chacun de ces modules a son `.test.mjs` à côté. Les contrôles du conteneur
(`docker/docker.test.mjs`, 9 tests) vérifient notamment que le port reste publié
sur `127.0.0.1` : c'est **la faute d'un caractère**, et un test échoue si elle est
commise.
