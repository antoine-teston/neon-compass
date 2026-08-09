# Fusionner une PR de contenu depuis la console

## Problème

La console ouvre une PR (`deliver`) et s'arrête là. Le merge se fait sur GitHub,
et le verdict de publication se lit sur GitHub Actions. Pour une boucle qui
commence et devrait finir dans la console, cela fait **deux postes de contrôle
pour un seul geste** — et le second est celui qui dit si le contenu a réellement
atteint les utilisateurs.

Le refus initial de fusionner était motivé : pour `news` et `online-events`, le
merge déclenche la publication CDN, donc le diff relu est le dernier garde-fou.
Ce document ne lève pas ce garde-fou — il **le déplace dans la console** au lieu
de le laisser hors d'elle.

## Ce que le merge déclenche réellement

Vérifié dans `.github/workflows/content.yml`, job `publish-news`. Le job ne
regarde que `content/`, et compare le merge à son parent :

- `HORS` = tout fichier changé sous `content/` **hors** `news/`,
  `online-events/`, `inbox/` et `cdn-versions.json`. S'il est non vide, **rien
  n'est publié** et le job l'explique.
- `À PUBLIER` = au moins un fichier sous `content/news/` ou
  `content/online-events/`.

Donc : **un merge publie si et seulement s'il touche de l'actu ou un événement
en ligne, et rien d'autre sous `content/`.** Le code, la doc et les workflows
sont invisibles à cette règle — une PR de code ne publie jamais.

Quatrième issue à ne pas confondre avec un échec : si `SUPABASE_URL` ou
`SUPABASE_SERVICE_ROLE_KEY` manquent dans l'environnement `production`, le job
**reste vert** et écrit un avertissement. Le contenu est sur `main` sans être en
ligne.

## Décisions de cadrage

| Question | Décision |
|---|---|
| Quelles PR | **Celles qui ne touchent que `content/`.** Le code continue de se fusionner sur GitHub — la console est un outil de contenu, et le diff qu'elle sait lire est du JSON. |
| Que montre la relecture | **Lecture éditoriale d'abord, diff brut repliable ensuite.** L'éditorial dit ce que le merge signifie ; le diff garantit que la mise en forme ne cache rien. |
| Garde CI | **Verte obligatoire.** Rouge ou en cours → refus motivé. |
| Après la fusion | **Suivi jusqu'au verdict de publication**, lu dans le journal du run. |
| Forme | **Carte « PR ouvertes » + boîte de relecture**, le motif que l'atelier emploie déjà : liste → clic → boîte → geste dans le pied. |

## Architecture

### `ui/pulls.mjs` — nouveau

Deux responsabilités séparées, et la seconde est pure.

**Les appels `gh`** : lister les PR ouvertes, lire les fichiers et l'état des
contrôles de l'une d'elles. Réutilise `ghDisponible()` de `runs.mjs`, qui sait
déjà dire quoi faire quand `gh` est muet.

**La règle, pure** : `effetDuMerge(fichiers)` rend l'un de trois verdicts.

| Verdict | Quand |
|---|---|
| `publie` | au moins un `content/(news\|online-events)/`, et rien d'autre sous `content/` |
| `hors-perimetre` | des fichiers publiables **et** d'autres sous `content/` → le job refusera tout en bloc |
| `sans-effet` | aucun fichier publiable |

`fusionnable(pr)` en dérive : une PR est fusionnable depuis la console si tous
ses fichiers sont sous `content/` **et** que ses contrôles sont au vert.

### Le contenu de la PR se lit en git local

`git fetch origin refs/pull/<n>/head:refs/console/pr/<n>`, puis tout est lecture
locale : `git show` pour les deux versions d'un fichier, `git diff` pour le diff
brut. Un seul appel réseau, aucun quota d'API, et `transitionDe()` de
`deliver.mjs` s'applique tel quel — « avant » sur `main`, « après » sur la
référence récupérée.

Le fetch ne touche ni `HEAD` ni l'arbre de travail : il pose une référence sous
un espace de noms à nous, effaçable par `git update-ref -d`.

### Aucune troisième porte

Deux routes de **lecture** — `GET /api/pulls` et `GET /api/pulls/:n` — et la
fusion passe par la porte « geste » existante : `POST /api/run`, action déclarée
`merge-pr`, numéro validé par motif, `bin: 'gh'`.

Une route `POST /api/pulls/:n/merge` qui lancerait un processus serait une porte
de plus à défendre, dans un serveur dont tout le modèle tient à ce qu'il n'y en
ait que deux.

### Les gardes s'évaluent côté serveur

`actions.mjs` gagne une propriété déclarative `precondition`. Pour `merge-pr`,
elle vérifie **au moment du geste** que la PR ne touche que `content/` et que ses
contrôles sont verts.

Côté page, le bouton grisé est un confort. **Le refus du serveur est la
barrière** — la console n'a aucune authentification, et une requête forgée
fusionnerait sinon n'importe quelle PR rouge. C'est aussi ce qui règle la course :
CI verte au chargement, commit arrivé depuis.

### La garde CI peut se fier au statut, ici

`runs.mjs` existe parce que l'API rapporte `success` pour une étape en
`continue-on-error` sortie en erreur. **`content.yml` n'a aucune étape
tolérante** — la seule du dépôt est dans `recolte.yml`. Le statut de `check` est
donc digne de foi.

C'est une propriété du workflow, pas une loi : le test de dérive assertera
l'absence de `continue-on-error` dans `content.yml`, faute de quoi cette garde
deviendrait fausse en silence.

## L'écran

### La carte « PR ouvertes »

Quatrième carte réseau de `cartesReseau()`, donc chargée après les brouillons et
tombant seule si `gh` est muet. Une ligne par PR : numéro, titre, âge, verdict
des contrôles, et **l'effet du merge**, qui est l'information que GitHub ne donne
nulle part.

Déclarée dans `DEFAUT.onglets.revue` de `layout.mjs`, à côté de `livraison`.

### La boîte de relecture

De haut en bas :

1. **L'effet du merge**, en une phrase : « publie 4 actus », « ne publie rien »,
   « sort du périmètre — ne publiera rien et le dira » ;
2. **la lecture éditoriale**, un bloc par item : transition de statut, titre et
   corps rendus, confiance, sources ;
3. **le diff brut, repliable**, sans filtre de chemin — un fichier inattendu dans
   la PR est précisément ce qu'il faut voir, et l'éditorial ne le montrerait pas ;
4. le pied : « Fermer », et « Fusionner » à droite.

Le bouton vit **dans** la boîte et non sur la carte : fusionner sans avoir ouvert
la relecture devient impossible par construction, et non par consigne.

### Après la fusion

La boîte ne se ferme pas. On note l'heure avant le geste, puis on cherche le run
de `content.yml` créé après — le tour que `derniersRuns({depuis})` fait déjà pour
la Récolte — et on lit son **journal**, jamais son statut. Quatre issues :

| Verdict | Ce qu'il veut dire |
|---|---|
| `publié` | le téléversement a eu lieu |
| `rien à publier` | le merge ne touchait pas d'actu |
| `hors périmètre` | le merge touchait aussi autre chose sous `content/` |
| `identifiants absents` | **job vert, contenu non publié** |

## Erreurs

La règle de la console s'applique sans exception : **jamais un zéro, toujours la
cause.**

- `gh` absent ou non authentifié → le message de `ghDisponible()`, pas « aucune
  PR » ;
- `git fetch` en échec → la boîte dit pourquoi, et n'affiche aucune relecture
  partielle ;
- un fichier au JSON illisible → son bloc éditorial le dit, le diff brut reste ;
- `gh pr merge` en échec (protection de branche, conflit apparu, PR fermée
  entre-temps) → le code retour est déjà diffusé par la porte « geste » ;
- run de publication introuvable → « en attente » puis « introuvable », jamais
  « publié ».

## Tests

1. **`effetDuMerge`**, tabulaire : les trois verdicts, dont les cas limites
   (`inbox/` seul, `cdn-versions.json` seul, mélange).
2. **Dérive contre `content.yml`** : les motifs de périmètre du module comparés à
   ceux du workflow, **et** l'absence de `continue-on-error`.
3. **Les refus du serveur** : PR hors contenu, CI rouge, CI en cours, PR
   inexistante — chacun son code, et **chacun éprouvé en le faisant refuser pour
   de vrai** avant qu'on lui fasse confiance.
4. **Le verdict de publication** depuis un journal, ses quatre issues.

Deux suites existantes couvrent le reste sans effort : `page.test.mjs` compare
les identifiants de `console.js` à ceux d'`index.html`, et `doc.test.mjs` refuse
de passer tant que l'action et les deux routes ne figurent pas dans la référence.

**La référence se met à jour dans le même lot** — règle posée le 2026-08-09. Ce
chantier ajoute une section à la console, ce que `doc.test.mjs` ne surveille pas
encore : l'assertion sur le nombre de sections annoncé entre dans le lot.

## Hors périmètre

- Les PR de code. Elles se fusionnent sur GitHub.
- La relecture ligne à ligne avec commentaires. La console montre, elle ne
  commente pas.
- La fermeture d'une PR sans fusion, et la suppression de branche.
- Le choix de la méthode de fusion : commit de fusion, comme le dépôt le fait
  déjà.
