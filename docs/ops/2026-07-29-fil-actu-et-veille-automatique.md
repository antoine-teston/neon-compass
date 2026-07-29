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

## L'accès aux sources

### Le 403 n'était pas ce qu'on croyait

Les deux runs de juillet concluaient à un blocage permanent en 403 sur les
domaines de la liste blanche. Vérification faite le 29 juillet, robots.txt en
main puis requête par requête :

- `www.gtaboom.com` autorise tout le monde (`User-Agent: * / Allow: /`), et les
  **cinq URLs qui avaient échoué répondent 200** — y compris avec l'UA par
  défaut de `curl`. Le blocage était transitoire, probablement un bouclier
  anti-bot momentané. `WebFetch` y accède d'ailleurs de nouveau.
- Il n'y avait donc rien à contourner sur ce domaine. La réponse correcte est
  un **réessai avec repli exponentiel**, pas un déguisement.

### Mais deux sources doivent réellement sortir du circuit

En lisant les robots.txt, deux problèmes de conformité sont apparus, sans
rapport avec le 403 :

- **`rockstargames.com` nomme `ClaudeBot: Disallow: /`.** La veille est un agent
  Claude. Le registre du spec §7 liste pourtant « Rockstar Newswire et site
  officiel », et le run du 21 juillet a cité `rockstargames.com/VI` comme source
  d'un fait — devenu un item publié. **Contradiction tranchée en faveur du
  robots.txt.** Les annonces officielles nous parviennent de toute façon par la
  presse spécialisée qui les relaie.
- **`reddit.com` : `User-agent: * / Disallow: /`.** Tout parcours automatique
  est exclu, quel que soit l'agent. Le flux Atom répond bien 200, mais il est
  sous `/` comme le reste. La voie sanctionnée est l'API Data officielle, avec
  identifiants OAuth — et son usage commercial est à trancher, l'app étant
  financée par la publicité. À noter : le contenu de r/GTA6 est de la
  spéculation communautaire, donc de confiance `rumor`, que le pipeline refuse
  de publier. L'ouvrir coûterait des identifiants et une question juridique pour
  des faits qui n'atteindraient jamais le fil.

`gtacodes.io` est par ailleurs hors service : il redirige vers
`gtacheatcodes.net`, dont le certificat TLS est cassé.

### La liste blanche est devenue du code

`tools/content-cli/source-policy.mjs` porte la politique par domaine, et
`fetch-source.mjs` l'applique :

```sh
node tools/content-cli/fetch-source.mjs policy       # l'état de la politique
node tools/content-cli/fetch-source.mjs feed <hôte>  # titres + dates récents
node tools/content-cli/fetch-source.mjs page <url>   # texte d'un article
node tools/content-cli/fetch-source.mjs wiki <titre> # wiki, via son API
```

La règle « jamais un site dont le robots.txt exclut les bots IA » vivait
uniquement dans le prompt de `data-scout` — et un run l'a malgré tout enfreinte.
Une règle qu'un modèle doit se rappeler n'est pas une règle. Elle lève
maintenant une exception, `WebFetch` a été retiré des outils de l'agent, et le
workflow ne lui autorise que ce script.

Trois gains au passage :

1. **Les flux d'abord.** `feed` rend titres, liens et dates structurés sans lire
   une seule page — donc sans parcourir le site. GTABOOM en publie un de 30
   entrées, Leonidaverse un `news-sitemap.xml` bilingue.
2. **Le wiki passe par son API.** Le HTML de `gta.fandom.com` est derrière un
   défi Cloudflare ; `api.php` répond normalement et rend le wikitext.
3. **Identification honnête.** L'UA annonce le bot et son dépôt, il n'emprunte
   pas celui d'un navigateur. Les domaines interrogés nous autorisent
   explicitement : se déguiser ne servirait à rien, et retirerait aux éditeurs
   le moyen de nous reconnaître.

## Ce qui reste ouvert

- **Décision à prendre sur le spec §7** : son registre de sources liste encore
  Rockstar et r/GTA6, que la politique refuse désormais. Le code fait autorité
  en pratique ; le spec devrait être aligné.
- **`guides` et `trophies` sont dans la même situation qu'`actu` avant ce
  travail** : modèle Swift et règles Firestore présents, aucun kind dans le
  CLI, aucun répertoire de contenu. Les écrans correspondants resteront vides
  jusqu'à ce qu'on leur pose le même tuyau.
- **`cheats` et `collections` sont entièrement en `draft`** (1 et 15 entrées) :
  ils passent le pipeline mais ne franchissent pas la publication. C'est une
  décision éditoriale en attente, pas un défaut.
