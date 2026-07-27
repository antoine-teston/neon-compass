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

## Ce qui reste à faire, et qui demande une action de console

Le déploiement lui-même :

```sh
firebase deploy --only hosting
```

Le compte de service actuel porte trois rôles — Cloud Datastore User, Firebase Remote Config Admin,
Firebase Rules Admin — et **aucun ne permet de déployer Hosting**. Il faut donc, une fois :

1. Ajouter le rôle **Firebase Hosting Admin** au compte de service `firebase-adminsdk-fbsvc@…`
   (console Google Cloud → IAM), ou déployer depuis un compte utilisateur (`firebase login`).
2. Lancer un premier `firebase deploy --only hosting`.
3. Renseigner `contentBaseURL` dans Remote Config avec l'URL rendue par le déploiement.

Tant que l'étape 3 n'est pas faite, l'app continue de lire Firestore : la bascule est inerte, pas
risquée.

## Ce que ça ne change pas

Les spots communautaires continuent de passer par Firestore (`content_bundles`) : ils sont reconstruits
par une Cloud Function, qui n'est pas déployée tant que Blaze n'est pas activé. Les basculer aussi sur
le CDN demanderait de reconstruire les fragments depuis GitHub Actions — faisable, et c'est la suite
logique si le choix « sans Blaze » se confirme.
