# Le fil actu, et pourquoi il était vide

*2026-07-29*

## Le symptôme et sa cause

Le fil actu affichait son état vide depuis sa livraison. La cause n'était pas
dans l'app : `FeedScreen` lit un `ContentStore<NewsItem>` construit avec
`seed: []`, donc purement distant. Rien n'écrivait jamais dans la collection
`news` — ni Firestore, ni le CDN.

En remontant la chaîne, couche par couche :

| Couche | État avant |
|---|---|
| Veille (`data-scout`) | produisait bien des faits `kind: "news"` |
| Rédaction | `content/news/` n'existait pas |
| Schéma | pas de `news.schema.json` |
| CLI | `news` absent de `KINDS` → invisible pour `validate`, `publish`, `build-cdn` |
| Firestore | règles ouvertes en lecture sur `/news/**`, jamais rien écrit |
| App | modèle, vue et écran complets, câblés, corrects |

Six faits `kind: "news"` ont dormi dans `content/inbox` du 21 au 29 juillet.
Pas par oubli : ils n'avaient aucune sortie possible. Les faits `poi` du même
fichier, eux, étaient traités — parce qu'ils avaient un tuyau.

Le plan 3d n'avait construit que les trois tâches Swift. Il supposait que
l'actu serait « publiée éditorialement via le même pipeline que POI/Cheat/
Guide », mais rien n'a jamais été ajouté à ce pipeline pour elle.

## Ce qui a été posé

### Le partage des rôles

La reformulation d'un fait est le **seul** maillon qu'une machine ne peut pas
faire seule : il faut écrire depuis le fait, dans nos mots, sans jamais
reprendre une marque déposée. Tout le reste est du code vérifiable. Ce partage
n'est pas une préférence de style — c'est ce qui rend le run hebdomadaire
automatisable. Si l'identité des items dépendait du jugement d'un modèle, la
chaîne n'aurait aucun moyen fiable de savoir ce qu'elle a déjà publié.

### L'identité et l'idempotence

`tools/content-cli/facts-to-news.mjs` frappe une clé d'identité stable par
fait, écrite dans `processedFrom`, sur le modèle de `gtav-poi-ids.mjs`. La clé
porte le **contenu** du fait — hachage de `source_url` + `claim` — et non son
fichier d'origine ni son rang. Un fait re-signalé la semaine suivante, dans un
autre fichier d'inbox, se réapparie donc sur l'item qu'il a déjà produit au
lieu d'en créer un second.

Le drapeau `processed` de l'inbox reste posé, mais il ne sert plus qu'à la
veille (qui relit les faits déjà émis). L'idempotence, elle, ne dépend d'aucun
drapeau qu'on aurait pu oublier de mettre.

### Les trois garde-fous

Chacun est couvert par un test qui le voit effectivement mordre :

1. **Un squelette non rédigé ne se publie pas.** `pull-news` pose
   `needsRewrite: true` ; `check-publishable` refuse la publication tant que le
   drapeau est là. C'est ce qui attrape une rédaction qui a échoué en silence
   au milieu d'un run automatique.
2. **Une rumeur ne se publie pas.** Décision éditoriale, pas détail technique :
   une app compagnon non officielle ne présente pas une spéculation de presse
   comme une actualité. La rumeur garde son id et sa trace en `draft`.
   Assouplir cette règle est une ligne dans `checkPublishable`.
3. **`body` entre dans le scan des marques déposées.** Le champ n'existait pas
   avant l'actu, donc il n'était scanné nulle part.

Le squelette ne recopie **jamais** le fait brut dans `title`/`body` : le fait
cite ses sources mot pour mot, marques déposées comprises, et
`check-publishable` scanne toutes les entrées, brouillons compris. Le fait est
conservé dans `sourceClaim`, qui n'est jamais affiché.

### État du contenu au 2026-07-29

Six items, dont trois publiables :

| Confiance | Items | Statut |
|---|---|---|
| `confirmed-official` | 1 | `published` |
| `multi-source` | 2 | `published` |
| `rumor` | 3 | `draft` |

Le fil affichera donc trois entrées **au premier `publish`**, pas avant :
rien n'a été écrit en production.

## Le run hebdomadaire

`.github/workflows/veille.yml`, lundi 06:00 UTC, également lançable à la main.

```
data-scout → pull-news → rédaction → garde-fous → PR
```

Il ne publie jamais. La publication reste le déclenchement manuel du workflow
`Contenu`, qui écrit dans le Firestore de production et fait re-télécharger le
contenu à tous les clients.

### Dégradation propre

Les deux étapes qui demandent un modèle sont conditionnées à la présence du
secret `ANTHROPIC_API_KEY`. Sans lui, le run se contente de matérialiser ce qui
traîne dans l'inbox et d'ouvrir une PR de squelettes en brouillon : aucun coût,
aucune écriture hasardeuse, et les faits ne se perdent plus. C'est le
comportement par défaut tant que le secret n'est pas ajouté.

### Sur les permissions des agents

Aucune étape n'utilise `--dangerously-skip-permissions`. La veille lit des
pages web, donc du texte écrit par des tiers, dont certains ont intérêt à
détourner un agent. Trois choses limitent ce que ça peut donner :

- une liste d'outils explicite par étape (la rédaction n'a aucun accès réseau) ;
- le jeton GitHub n'est présent que dans l'étape qui ouvre la PR, jamais dans
  celles qui exécutent un agent ;
- `npm test` est un mur entre la rédaction et la PR, et un humain relit ensuite.

## Ce qui reste ouvert

- **La veille est dégradée.** Les deux runs de juillet signalent le même
  incident : `WebFetch` en 403 sur les domaines de la liste blanche
  (`gtaboom.com`, `rockstargames.com/newswire`), et `reddit.com` refusé au
  niveau même de l'outil `WebSearch`. Les faits actuels viennent d'extraits de
  recherche, avec des `source_date` approximatives. Programmer la veille ne
  répare pas ça — ça la répète.
- **`guides` et `trophies` sont dans la même situation qu'`actu` avant ce
  travail** : modèle Swift et règles Firestore présents, aucun kind dans le
  CLI, aucun répertoire de contenu. Les écrans correspondants resteront vides
  jusqu'à ce qu'on leur pose le même tuyau.
- **`cheats` et `collections` sont entièrement en `draft`** (1 et 15 entrées) :
  ils passent le pipeline mais ne franchissent pas la publication. C'est une
  décision éditoriale en attente, pas un défaut.
