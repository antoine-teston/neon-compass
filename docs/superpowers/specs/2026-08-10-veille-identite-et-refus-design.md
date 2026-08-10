# Identité et refus dans la chaîne de veille

## Problème

La chaîne n'a aucune identité qui survive à une reformulation, et aucune mémoire
du refus. Deux conséquences mesurées, pas supposées.

**Les doublons.** La veille a tourné deux fois par jour les 08, 09 et 10 août —
deux sessions concurrentes de la même Routine, que `content/inbox/runs/2026-08-10b.md`
raconte lui-même : « une autre session de cette même Routine avait déjà poussé son
propre commit ». Les deux sessions lisent les mêmes articles et en tirent des
`claim` différents. Or `factDiscriminant` hache `source_url + claim` ; deux
rédactions du même fait portent donc deux identités, et la PR #83 proposait
4 entrées pour 2 articles. Sur l'inbox complète : **12 URLs dupliquées** par les
seuls doubles runs.

**Le refus qui ne tient pas.** Le 2026-08-09, `8da9ccb` a écarté `news_9bd3ef15`
avec son motif — « la durée d'environ vingt minutes évoquée pour la vidéo Netflix
ne tient qu'à un message du support client relayé sans confirmation ». Le fait
source est resté dans l'inbox. `pull-news --dry-run` sur `main` répond aujourd'hui :

```
écrirait content/news/news_9bd3ef15.json  [rumor] 2026-08-07
```

Il va la recréer, en squelette non rédigé cette fois. Il n'existe aucun moyen de
dire « non » durablement à un fait récolté.

**Ce que ces deux pannes ont en commun.** Les règles existaient — en prose.
`facts-to-news.mjs:47` promet qu'« un fait re-signalé doit se réapparier sur
l'item qu'il a déjà produit, sinon le fil accumule des doublons à chaque run ».
`.claude/agents/data-scout.md:139` avertit l'agent que « l'identité d'un fait est
le hachage de `source_url + claim` » et que deux identités feraient « afficher
deux cartes concurrentes ». Aucune des deux n'est un mécanisme. C'est la cicatrice
`deploy-rules` une fois de plus : une règle qu'aucun code n'applique n'est pas une
règle, c'est un souhait.

## Ce qui a été mesuré

Sur les 16 fichiers d'inbox de `main` : **78 URLs distinctes pour 101 faits**.
Distribution des faits par URL : 59 en portent un, 15 en portent deux, 4 en
portent trois.

Les URLs à plusieurs faits se répartissent en deux familles, et la distinction
commande tout le design :

- **Légitimes** — un article « toutes les localisations confirmées » donne trois
  faits `poi` ; un article de codes donne un `game-fact` et un `cheat`. C'est
  ainsi que les 537 POI sont arrivés.
- **Pathologiques** — les 12 URLs vues deux fois par les runs `08-08`/`08-08b`,
  `08-09`/`08-09b`, `08-10`/`08-10b`, toujours de même `kind`.

Un contrôle « une URL = une entrée » appliqué sans nuance casserait la première
famille. D'où la table de cardinalité par kind (§ Architecture).

## Décisions de cadrage

**Le verrou vit à la convergence, pas à la production.** Un contrôle posé à la
récolte ne peut pas régler la concurrence : deux sessions lisent « URL non
couverte » avant que l'une ou l'autre n'écrive. Seul un contrôle qui tourne
*après* le merge voit les deux lectures. C'est la même leçon que le correctif de
fusion du 2026-08-10 (`85277a0`) — la barrière appartient au serveur, pas à la
page. Un contrôle à la récolte reste utile comme économie d'appels, jamais comme
garantie.

**Le registre des URL ne s'écrit pas : il est l'inbox.** « Cette URL a-t-elle été
récoltée ? » se répond en lisant les `source_url` de `content/inbox/*.facts.json`.
Ajouter un fichier de registre créerait un état de plus à tenir synchrone, et un
fichier partagé que deux sessions concurrentes éditeraient en conflit. Le seul
état réellement neuf est le registre des refus, qui lui ne se dérive de rien : un
fait écarté n'a plus d'entrée, donc plus rien à lire.

**L'état ne peut pas vivre dans Supabase.** La passerelle de la Routine ne joint
que `api.github.com` — elle ne pourrait pas lire la table. Écarté pour une raison
d'architecture, pas de goût.

**`factDiscriminant` n'est pas touché.** Le refrapper migrerait les 78 entrées
publiées pour un gain nul une fois le contrôle de convergence en place.

**L'ordonnanceur de la Routine n'est pas touché.** Il vit hors du dépôt. La chaîne
devient indifférente au nombre de runs, ce qui était l'objectif : corriger
l'ordonnanceur seul laisserait un `workflow_dispatch` manuel, un réessai ou une
session relancée recréer le problème.

## Architecture

### Le contrôle de convergence — `facts-to-news.mjs`

Fonction pure, aucun réseau, aucun disque — donc testable en rejouant les faits
réels des 08 au 10 août.

**La pureté du module est une contrainte, pas un ornement** : son en-tête annonce
« aucune I/O », et le registre des refus est un fichier. C'est donc `cli.js` qui
le lit et le passe en paramètre à `materialize`, comme il lui passe déjà les
entrées existantes. Le module décide ; il ne va rien chercher. Les deux tables de
cardinalité vivent dans `schemas.mjs`, aux côtés de `KINDS` sur laquelle porte
leur test d'exhaustivité.

Règle : pour un kind à **cardinalité une**, un fait dont la `source_url` figure
déjà dans les `sources` d'une entrée existante ne produit rien. Le `claim`
n'entre pas dans la décision, et c'est précisément ce qui rend le contrôle
insensible à la reformulation.

`materialize` gagne une sortie `ecartes`, distincte de `alreadyMaterialized` :
un fait déjà matérialisé s'est réapparié à son entrée, un fait écarté a été
*jeté*. Les confondre afficherait « rien à faire » à qui vient de perdre une
lecture.

**Il écarte, il ne fusionne pas, et il le dit.** `pull-news` rapporte chaque
écart avec l'URL et l'entrée qui la portait déjà :

```
écarté  what-to-expect-when-gta-6-hits-netflix-…  — déjà porté par news_9bd3ef15
pull-news: 2 squelette(s), 3 écarté(s) — URL déjà couverte, 78 déjà matérialisé(s)
```

Un écart silencieux se lirait comme une absence de travail.

### La cardinalité, en un seul endroit

```js
export const CARDINALITE = {
  news: 'une',
  poi: 'multiple', 'poi-gtav': 'multiple',
  cheats: 'multiple', collections: 'multiple',
};

/** Les kinds que ce contrôle ne juge PAS, et pourquoi. Un kind sans entrée ici
 *  ni dans `CARDINALITE` fait tomber la suite. */
export const HORS_CONTROLE = {
  'online-events':
    'identité portée par windowDiscriminant (début de fenêtre), déjà insensible au claim',
};
```

`facts-to-online-event.mjs` fait reposer l'identité d'un événement sur le début
de fenêtre et non sur le contenu — il ne souffre pas de ce défaut, et c'est ce
qui lui permet de corriger un compte à rebours prolongé au lieu de créer une
seconde carte. L'inscrire dans `CARDINALITE` suggérerait qu'il est couvert par ce
contrôle-ci alors qu'il l'est par le sien ; le taire laisserait croire à un oubli.
D'où une seconde table, qui dit l'exemption et sa raison.

Un test assert que **tout kind de `KINDS` (`schemas.mjs`) figure dans exactement
une des deux tables**. Ajouter un kind force donc à trancher — cardinalité, ou
exemption motivée — au lieu de retomber sur un défaut implicite. Même geste que
`nominative-fields.mjs` : la règle est une table qu'on peut lire, pas une
intuition répartie dans le code.

### Le registre des refus, et sa levée

`content/inbox/refus.json` — le seul état neuf du chantier. Lu par `cli.js`, qui
le passe à `materialize` ; écrit par l'action `discard-draft` du serveur de
console. Aucun des deux modules purs ne le touche.

```json
{
  "news|https://www.gtaboom.com/what-to-expect-when-gta-6-hits-netflix-on-august-27-c2f7": {
    "motif": "ne tient qu'à un message du support client relayé sans confirmation",
    "entree": "news_9bd3ef15",
    "le": "2026-08-09",
    "confiance": "rumor"
  }
}
```

**La clé s'aligne sur celle du contrôle de convergence**, pas sur l'identité du
fait. Pour un kind à cardinalité une : `kind|source_url`. Pour les autres : l'id
de l'entrée. Clé le refus sur `processedFrom` aurait rouvert le trou qu'on
bouche : ce discriminant contient le `claim`, donc une simple reformulation aurait
ressuscité l'entrée écartée.

**La levée est automatique, et l'échelle existe déjà.** L'énumération
`confidence` du schéma est ordonnée du plus fort au plus faible —
`confirmed-official`, `multi-source`, `single-source`, `rumor`. Un fait ultérieur
sur la même URL dont la confiance est **strictement supérieure** à celle
enregistrée n'est pas bloqué, et `pull-news` le dit :

```
refus du 2026-08-09 levé — confiance passée de rumor à multi-source
```

C'est le raisonnement éditorial réel : le 09/08 n'a pas écarté le sujet, il a
écarté une rumeur.

**Aucun champ « portée » n'est nécessaire.** Un `confirmed-official` écarté parce
qu'il n'intéresse personne n'a rien de strictement supérieur au-dessus de lui : il
n'est jamais relevé. La règle de confiance couvre les deux familles de refus sans
champ supplémentaire — et un champ que personne ne remplit correctement vaut moins
qu'une règle dérivée d'une valeur déjà obligatoire.

**Défaut assumé.** Un `single-source` écarté pour cause d'ennui remontera si un
second média le reprend, et il faudra le réécarter. Au pire trois fois, chaque
refus réenregistrant la confiance atteinte. C'est préférable à un sujet
définitivement invisible parce qu'il a été jugé une fois.

**Pas de geste de levée manuelle.** Le fichier est versionné et lisible : retirer
la ligne EST la levée.

### Le geste « Écarter » — `deleteDraft`, qui existe déjà

**Aucune action nouvelle.** Le geste est déjà là : bouton `#ed-delete` de
l'éditeur, `DELETE /api/draft/:kind/:id`, `drafts.mjs:341 deleteDraft()`. Il
refuse déjà un item `published` en 409 avec le bon motif, et vérifie l'empreinte
du fichier pour ne pas écraser une édition faite au terminal entre-temps.

Lui adjoindre une action `discard-draft` sur la porte « geste » créerait une
**seconde façon d'écarter** — une porte de plus à défendre, dans un serveur dont
le modèle tient à ce qu'il n'y en ait que deux, et deux chemins dont un seul
inscrirait le refus. La bonne forme est d'étendre celui qui existe.

`deleteDraft(kind, id, { fingerprint, motif })` gagne donc un paramètre :

- **`motif` obligatoire et non vide**, sinon 400 et rien n'est supprimé. C'est ce
  qui capture la phrase du 09/08, qui existait — mais dans un message de commit.
- Le fichier supprimé **et** le refus inscrit dans le même appel, avec la
  confiance qu'avait l'entrée. Un registre qui demanderait une étape séparée ne
  serait jamais rempli.
- Une inscription par `source` de l'entrée écartée : le refus doit mordre quelle
  que soit celle qui la re-signale.

L'ordre compte : **le registre s'écrit avant le `unlinkSync`.** L'inverse
laisserait, si l'écriture échouait, un fichier supprimé sans refus enregistré —
c'est-à-dire précisément la panne qu'on corrige, reproduite par le correctif.

La page ajoute la saisie du motif au geste existant. `#ed-delete` reste au même
endroit, avec le même `disabled` sur `published`.

## Erreurs

| Situation | Réponse |
|---|---|
| `motif` absent ou vide | 400, **rien n'est supprimé** |
| entrée inexistante | 404, comme aujourd'hui |
| entrée `published` | 409, message inchangé (`drafts.mjs:345`) |
| fichier modifié depuis l'ouverture | 409, empreinte, comportement inchangé |
| échec d'écriture du registre | l'erreur remonte et **le fichier n'est pas supprimé** — le registre s'écrit d'abord |
| `refus.json` illisible ou JSON invalide | `pull-news` **s'arrête** ; un registre qu'on ne sait pas lire ne vaut pas un registre vide, qui laisserait tout repasser |
| `refus.json` absent | traité comme vide — c'est l'état initial légitime |
| deux sessions écartent en même temps | le second `git push` échoue en non-fast-forward ; le rebase relit le registre |

La ligne qui compte est la quatrième : dans le doute, un contrôle refuse. Un
registre corrompu qui se dégraderait en « aucun refus » ferait revenir en silence
tout ce qui a été écarté.

## Tests

- **Rejeu du réel.** Les faits des 08, 09 et 10 août en fixture : 12 URLs
  dupliquées, une seule entrée produite pour chacune. C'est la panne exacte, pas
  une reconstitution.
- **Le contrôle retiré fait revenir les doublons** — exécuté, pas supposé. Un
  contrôle qui ne sait qu'approuver est indiscernable d'un bon.
- **Les faits multiples légitimes passent** : les trois `poi` d'un même article de
  localisations produisent trois entrées.
- **Tout kind de `KINDS` figure dans exactement une des deux tables** —
  `CARDINALITE` ou `HORS_CONTROLE`. Un kind dans les deux, ou dans aucune, fait
  tomber la suite.
- **Un fait refusé ne produit rien**, et le registre survit à un `pull-news`
  complet.
- **La levée fonctionne** : même URL, confiance passée de `rumor` à
  `multi-source` → l'entrée est produite et l'écart est rapporté.
- **La levée ne se déclenche pas à confiance égale ou inférieure.**
- **`motif` vide est refusé par `deleteDraft`, et le fichier survit** — la
  seconde moitié compte autant que la première.
- **Le registre s'écrit avant la suppression** : une écriture qui échoue laisse
  le brouillon en place, prouvé en la faisant échouer.

**Critère d'acceptation vivant.** Aujourd'hui, `pull-news --dry-run` sur `main`
veut écrire `news_9bd3ef15`. Après ce chantier il ne le veut plus, sans qu'on ait
touché à l'inbox — et il le voudra à nouveau si un article confirme les vingt
minutes.

## Hors périmètre

- **La traduction ES/IT/DE.** `cli.js:370` déclare que `translate` n'a que son
  `--dry-run` et que « l'appel IA reste à câbler » ; les 78 actus publiées sont
  toutes en `en+fr` seulement, alors que le schéma accepte les cinq langues et que
  la console affiche déjà un bouton « Traductions manquantes ». Chantier réel,
  spec distincte : il vit après la rédaction, pas à la matérialisation, et aucune
  de ses questions — quel modèle, quel coût, traduit-on les brouillons ou seulement
  le publiable, une traduction manquante bloque-t-elle la publication — ne touche
  celui-ci.
- **L'ordonnanceur de la Routine**, hors dépôt.
- **`factDiscriminant`**, inchangé.
- **La fusion de deux lectures concurrentes** : le contrôle écarte la seconde en
  le disant, il ne tente pas de réconcilier deux rédactions.
- **Dépublier une entrée `published`.**
