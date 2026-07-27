# Contenu servi par CDN — pourquoi, et comment basculer

**Date** : 2026-07-27
**Spec de référence** : `docs/superpowers/specs/2026-07-27-content-read-aggregation-design.md` (dont ce
document corrige une conclusion, voir plus bas)

## Pourquoi

Le trafic de cette app est à 95 % de la **lecture de contenu partagé et versionné**. Ce n'est pas une
charge de base de données, c'est de la distribution de fichiers. Or pour ça, le moins cher et le plus
rapide n'est pas Firestore mais un fichier JSON derrière une URL :

| | Firestore | CDN |
|---|---|---|
| Coût par lecture | facturé par document | **zéro** |
| Latence | aller-retour vers `eur3` | cache en périphérie |
| Client requis | SDK Firebase | n'importe quel client HTTP |

Le troisième point est le plus structurant : un JSON se lit identiquement depuis Swift, Kotlin et un
navigateur. C'est ce qui permettra à un second client — ou au plan B PWA de la spec — de se brancher
sans rien réécrire côté serveur.

**Correction assumée d'une décision antérieure.** La spec d'agrégation avait envisagé le CDN puis
l'avait écarté : Hosting n'était pas provisionné, et une fois les fragments découpés le gain de coût
devenait dérisoire (≈ 1 €/mois). Ce raisonnement était juste **pour un client iOS unique**. Il ne
l'est plus dès qu'on vise plusieurs plateformes : ce qui était une économie marginale devient de
l'indépendance vis-à-vis des SDK.

## Comment c'est construit

```sh
cd tools/content-cli && node cli.js build-cdn
```

Produit `dist/` :

```
content/manifest.json              {version, commit, collections: {nom: {chunks, count}}}
content/v<version>/<collection>/<chunk>.json   {collection, chunk, items[]}
```

**Les fragments portent la version dans leur chemin**, donc leur contenu ne change jamais pour une URL
donnée : le CDN les garde un an (`immutable`), et aucun client ne peut recevoir un fragment périmé.
Seul le manifeste bouge, et il est court-caché (60 s). Les en-têtes correspondants sont dans
`firebase.json`.

La version vient du **nombre de commits** (`git rev-list --count HEAD`) : monotone, déterministe, et
calculable hors ligne — contrairement à `contentVersion` de Remote Config, qui exige des credentials.
La construction tourne donc en CI sans aucun secret.

Comme pour Firestore, seul le `status: "published"` part : un brouillon peut dormir dans le dépôt
indéfiniment sans jamais atteindre un client.

## Comment on bascule, et comment on revient

Un paramètre Remote Config, **`contentBaseURL`** :

- **vide ou absent** → tout passe par Firestore, exactement comme avant ;
- **renseigné** (ex. `https://neoncompass-gt-vi.web.app`) → l'app lit le CDN.

Aucune mise à jour de l'app n'est nécessaire, **dans les deux sens**. C'est la seule façon honnête
d'introduire une nouvelle source de vérité en production : le repli d'urgence est une valeur à effacer.

Un point à connaître avant de replier : la version du CDN vient du nombre de commits, celle de Remote
Config d'un compteur de publications. La première est structurellement plus grande. Passer au CDN
déclenche donc une resynchronisation (voulu) ; revenir en arrière laisse le cache client en place
jusqu'à ce que `contentVersion` dépasse ce nombre. Un repli sert à éteindre un incendie, pas à revenir
au contenu d'avant.

## En service depuis le 2026-07-27

```sh
cd tools/content-cli && node cli.js build-cdn
GOOGLE_APPLICATION_CREDENTIALS="$FIREBASE_SERVICE_ACCOUNT_PATH" \
  functions/node_modules/.bin/firebase deploy --only hosting --project neoncompass-gt-vi
node cli.js content-source https://neoncompass-gt-vi.web.app
```

**Correction d'une affirmation antérieure de ce document** : il y était écrit que le compte de service
ne pouvait pas déployer Hosting, faute du rôle idoine. C'était faux — le déploiement est passé du
premier coup avec les credentials existants. La leçon vaut d'être notée : les trois rôles listés dans
`docs/ops/2026-07-27-content-publishing.md` ne décrivent pas exhaustivement ce que le compte peut
faire, et il vaut mieux essayer que déduire.

Vérifié en ligne le jour même :

| | Attendu | Servi |
|---|---|---|
| `/content/manifest.json` | `max-age=60` | ✅ `public, max-age=60` |
| `/content/v233/poi_gtav/0.json` | cache long, immuable | ✅ `public, max-age=31536000, immutable` |
| Contenu | 537 entrées en 2 fragments | ✅ 500 + 37 |

`contentBaseURL` pointe sur `https://neoncompass-gt-vi.web.app`, donc **les clients lisent le CDN**.
Le repli tient dans une commande : `node cli.js content-source off`.

## Changer de source, et revenir

```sh
node cli.js content-source                                   # où en est-on ?
node cli.js content-source https://exemple.example           # basculer
node cli.js content-source off                               # revenir à Firestore
```

La commande lit-modifie-republie le template Remote Config : les autres paramètres
(`contentVersion`, coupe-circuit, drapeau serveur) survivent. Une écriture naïve les effacerait tous,
`publishTemplate` remplaçant le template entier.

## Ce que ça ne change pas

Les spots communautaires continuent de passer par Firestore (`content_bundles`) : ils sont reconstruits
par une Cloud Function, qui n'est pas déployée tant que Blaze n'est pas activé. Les basculer aussi sur
le CDN demanderait de reconstruire les fragments depuis GitHub Actions — faisable, et c'est la suite
logique si le choix « sans Blaze » se confirme.
