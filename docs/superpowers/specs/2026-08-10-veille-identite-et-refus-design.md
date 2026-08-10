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

**Il écarte, il ne fusionne pas, et il le dit — avec le `claim` écarté.**

```
écarté  what-to-expect-when-gta-6-hits-netflix-…  — déjà porté par news_9bd3ef15
        « Un message du support client de Netflix évoquerait une durée de… »
pull-news: 2 squelette(s), 3 écarté(s) — URL déjà couverte, 78 déjà matérialisé(s)
```

Le `claim` dans le rapport n'est pas du confort, et c'est le prix assumé de ce
contrôle. **Une URL peut légitimement porter deux sujets distincts.** Le cas
existe dans les données : `playstation-quietly-adds-gta-6-…` porte trois faits du
2026-08-06, dont deux sont des doublons du même sujet (Sony réinscrit le jeu à
sa page éditoriale) — mais le troisième parle d'un ancien animateur du studio
jugeant le jeu achevé à 80-90 %. Rien de mécanique ne les distingue : il faudrait
lire.

Le contrôle écartera donc ce troisième fait. Il ne peut pas ne pas l'écarter sans
rouvrir la porte aux doublons, mais il ne doit pas le perdre en silence : le
`claim` imprimé, relu dans la PR quotidienne, laisse la décision à un humain qui
peut rouvrir le sujet depuis une autre source.

**Ce que ces données apprennent en passant** : les doublons ne viennent pas
seulement des doubles runs. Les 06 et 07 août, un run UNIQUE a produit deux faits
pour un même article, quatre fois. L'agent se répète tout seul. Un correctif qui
se serait contenté de l'ordonnanceur n'aurait rien réglé de cela.

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

**La portée réelle de la levée, constatée en exécutant — 2026-08-10.** Elle ne
joue que si l'article a été rejeté EN ENTIER. Le contrôle de convergence tourne
avant le registre ; si un frère de même URL a survécu, il couvre l'URL et le
fait est écarté sans que le registre soit jamais consulté. La levée est alors
inatteignable pour cette URL, quelle que soit la confiance qui monte.

Ce n'est pas une hypothèse : c'est le cas de l'article même qui a motivé ce
chantier. `what-to-expect-when-gta-6-hits-netflix-…` a produit deux entrées de
sujets distincts — la durée de vingt minutes (`news_9bd3ef15`, `rumor`, écartée
le 09/08) et l'accord Netflix présenté comme une première (`news_285eebb3`,
`single-source`, toujours en `draft` sur `main`). La seconde couvre l'URL, donc
la première ne reviendra jamais par la levée.

C'est le comportement voulu et non un défaut à corriger : la déduplication est
le contrôle qui protège le fil, la levée est un confort. Quand les deux
s'opposent, la déduplication prime. Et le cas majoritaire lui échappe — 59 des
78 URLs de l'inbox ne portent qu'un seul fait, donc rejeter leur entrée rejette
l'article entier et rend la levée atteignable.

**Conséquence sur ce qu'on inscrit au registre.** La clé étant `kind|url`, un
refus couvre TOUS les sujets de l'article. Inscrire le refus du 09/08
condamnerait donc aussi `news_285eebb3`, qui est un brouillon légitime. Le
registre ne doit donc PAS être pré-rempli avec cette décision : il se remplira
par le geste « Écarter », au cas par cas, quand un article aura été jugé en
entier.

**Le revers de la même pièce, mesuré en exécutant la preuve de bout en bout.**
Si un refus à `rumor` est inscrit sur une URL et qu'un AUTRE sujet du même
article arrive en `single-source`, la levée se déclenche — et le journal annonce
« refus levé, confiance passée de rumor à single-source » en écrivant une entrée
qui n'a rien à voir avec le sujet refusé. Le résultat est bon (ce sujet-là
mérite d'exister), la raison est fausse.

C'est la même cause que ci-dessus : la clé est l'article, pas le sujet. Un refus
y couvre trop, et n'importe lequel de ses frères mieux sourcé le lève.

Le remède serait une clé au sujet — mais le seul discriminant de sujet
disponible est le `claim`, prose écrite par un modèle, c'est-à-dire précisément
ce que tout ce chantier retire des identités. On garde donc la clé par URL, et
on écrit ici sa limite plutôt que de la découvrir un jour dans un fil qui
ressuscite. **La conséquence pratique tient en une phrase : écarter est un
jugement sur l'ARTICLE, pas sur la brève.**

Un article riche rend donc le geste grossier. Celui du 27 août en est
l'illustration : `what-to-expect-when-gta-6-hits-netflix-…` a produit à lui seul
quatre sujets distincts — la durée de vingt minutes, l'accord Netflix comme une
première, le demi-milliard de vues des bandes-annonces, et le partenariat
qualifié par le PDG. Les écarter tous parce que le premier est une rumeur serait
une perte réelle.

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
  localisations produisent trois entrées — la cardinalité `multiple` les exempte.
- **Un écart nomme ce qu'il jette** : le `claim` figure dans le rapport, testé
  sur le cas réel de `playstation-quietly-adds-gta-6-…` où le troisième fait est
  un sujet distinct légitimement sacrifié.
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

**Critère d'acceptation vivant, corrigé le 2026-08-10 après exécution.** La
formulation d'origine — « il le voudra à nouveau si un article confirme les
vingt minutes » — était fausse, pour la raison exposée plus haut : un frère
survit sur cette URL, donc la levée n'y est pas atteignable.

Ce qui se vérifie réellement, et qui reste le but du chantier :

- Avant : `pull-news --dry-run` voulait écrire `news_9bd3ef15`, l'entrée écartée
  la veille par un humain.
- Après : `0 squelette(s), 1 écarté(s), 78 déjà matérialisé(s)` — et l'écart
  nomme le fait jeté ainsi que l'entrée qui couvrait déjà son URL.

Le registre et sa levée se prouvent séparément, sur un article rejeté en entier
— seul cas où ils sont atteignables.

## Hors périmètre

- **La traduction ES/IT/DE.** La cause est une couture, comme le reste de ce
  dossier : `content-editor.md:15` dit « ES/IT/DE sont générés par le CLI — ne les
  remplis pas », et `cli.js:370` dit « l'appel IA reste à câbler ». Chaque moitié
  délègue à l'autre, et les 78 actus publiées sont bilingues alors que le schéma
  accepte les cinq langues et que la console affiche déjà un bouton « Traductions
  manquantes ».

  **Tranché le 2026-08-10 : c'est la ROUTINE qui traduira, pas le CLI.** Elle
  écrit déjà `title` et `body` en EN et FR depuis le `claim` ; écrire les cinq
  langues est le même geste, même modèle, même passe — aucune clé d'API, aucun
  coût, aucun secret de plus. `translate --dry-run` n'est donc pas un producteur
  inachevé mais le **contrôle**, et il devient utile tel quel.

  Chantier distinct malgré tout, parce que deux questions y restent entières et
  n'ont rien à voir avec l'identité ni le refus : une traduction manquante
  bloque-t-elle la publication, et que fait-on des 78 entrées déjà publiées.
- **L'ordonnanceur de la Routine**, hors dépôt.
- **`factDiscriminant`**, inchangé.
- **La fusion de deux lectures concurrentes** : le contrôle écarte la seconde en
  le disant, il ne tente pas de réconcilier deux rédactions.
- **Dépublier une entrée `published`.**
