# Spots communautaires en fragments — sortir du « une lecture par document »

**Date** : 2026-07-27
**Statut** : validé, à implémenter
**Branche** : `community/bundles`

## Problème

`FirestoreContributionRepository.fetchApproved()` fait un `getDocuments()` sur toute la collection
`contributions` filtrée sur `status == 'approved'`, **à chaque lancement de l'app**, sans pagination,
sans cache et sans garde de version. Firestore facture **une lecture par document renvoyé**.

Le coût est donc le produit de trois nombres qui explosent tous les trois le 19 novembre :

> utilisateurs actifs × lancements par utilisateur × spots approuvés

À 50 000 utilisateurs quotidiens, 3 lancements et 3 000 spots : **450 M lectures/jour**, soit de
l'ordre de **270 $/jour** au tarif multi-région `eur3`. Pour une app financée par la pub, c'est un
scénario où le succès ruine.

Le contenu éditorial a déjà été sorti de ce piège (spec du 2026-07-27, « Agrégation des lectures ») :
`ChunkedContentRepository` lit des fragments de 500 entrées dans `content_bundles`, et seulement
quand `contentVersion` a bougé. Les spots communautaires n'ont jamais reçu ce traitement.

## Ce qui rend le remède peu coûteux

`ContentItem` ne demande qu'un identifiant `String` et `Codable`. `Contribution` a déjà le premier.
Le rendre `Codable` suffit à le faire entrer dans `ContentStore`, et il hérite alors **sans une ligne
de plus** : les fragments, la garde de version, le cache SwiftData et le décodage tolérant.

## Décisions

### D1 — Le manifeste porte la version, pas Remote Config

Le contenu éditorial se versionne par `contentVersion` dans Remote Config, bumpé par le CLI à chaque
publication. Réutiliser ce canal ici serait doublement faux : une publication de contenu forcerait la
re-synchronisation des spots, et l'inverse aussi ; et surtout, publier un template Remote Config
toutes les cinq minutes depuis une Function est limité en débit et lourd.

Un document unique, `content_bundles/community_spots_manifest`, porte donc
`{ version, chunks, dirty, builtAt }`. Le client lit **ce seul document** pour savoir s'il a quelque
chose à rattraper.

**Coût par lancement quand rien n'a changé : 1 lecture.** Contre 3 000 aujourd'hui.

Il vit dans `content_bundles`, déjà en lecture publique : **aucune règle Firestore à changer**.

### D2 — Reconstruction déclenchée par ce qui compte, pas par les votes

Deux Cloud Functions, région `europe-west1` comme les autres :

- **`flagCommunityBundlesDirty`** — déclencheur `onDocumentWritten` sur `contributions/{id}`. Marque
  le manifeste `dirty` **uniquement** si un champ qui change ce que les clients voient a bougé :
  `status`, `shadowHidden`, `position`, `title`, `category`, `authorHandle`. Un vote ne modifie que
  `upvotes`/`downvotes` : il ne salit rien. Sans cette discrimination, chaque vote déclencherait une
  reconstruction complète — le pic de votes étant précisément le moment où on ne peut pas se le
  permettre.
- **`rebuildCommunityBundles`** — planifiée toutes les 5 minutes. Lit le manifeste (1 lecture) et
  s'arrête là si rien n'est sale et si la dernière construction a moins d'une heure. Sinon
  reconstruit les fragments, incrémente `version`, remet `dirty` à faux.

**Le rafraîchissement horaire forcé** existe pour une seule raison : les compteurs de votes ne
salissent pas le manifeste, donc sans lui ils resteraient figés à jamais. Une heure de fraîcheur pour
un compteur de votes est un compromis acceptable — le client applique déjà ses propres votes de façon
optimiste. Coût : 24 reconstructions par jour, soit ~72 000 lectures, ~0,04 $/jour.

### D3 — Les fragments réutilisent `content_bundles`, pas une nouvelle collection

Même format, même collection, un `collection` différent : `community_spots`. Trois bénéfices : aucune
règle à écrire, `ChunkedContentRepository<Contribution>(collectionName: "community_spots")` fonctionne
tel quel, et `pushBundles` du CLI — qui ne purge que les fragments de SA collection — ne peut pas les
écraser.

### D4 — Ce qui reste en lecture directe

`fetchMine(uid:)` garde sa requête directe : elle renvoie les quelques contributions d'un seul
utilisateur, c'est déjà minuscule et ça doit être frais (un contributeur doit voir sa soumission
immédiatement, avant toute reconstruction).

Le filtrage des auteurs bloqués reste côté client, inchangé : il est personnel, il n'a rien à faire
dans un fragment partagé.

### D5 — Les spots masqués ne partent pas dans les fragments

Le fragment ne contient que `status == 'approved'` **et** `shadowHidden != true`. Un shadow-ban doit
disparaître de ce que les clients lisent, et c'est le seul endroit où le filtre peut désormais
s'appliquer — les règles Firestore ne protègent plus rien ici, puisque le client ne lit plus la
collection `contributions`.

C'est le point de vigilance de ce chantier : **la règle de sécurité qui filtrait `shadowHidden`
devient un filtre applicatif dans la Function**. Un test le fige.

## Architecture

```
functions/src/
  communityBundles.ts          # NOUVEAU — logique pure : faut-il reconstruire, quels champs salissent
  communityBundles.test.ts     # NOUVEAU — node:test
  rebuildCommunityBundles.ts   # NOUVEAU — Function planifiée
  flagCommunityBundlesDirty.ts # NOUVEAU — déclencheur Firestore
  index.ts                     # + les deux exports

NeonCompass/Core/Community/
  Contribution.swift                    # + Codable
  FirestoreContributionRepository.swift  # fetchApproved retiré, fetchMine conservé
  ContributionRepository.swift           # protocole réduit
  CommunityBundleVersionProvider.swift   # NOUVEAU — lit le manifeste (1 lecture)

NeonCompass/Features/Community/
  CommunityModel.swift          # lit un ContentStore<Contribution> au lieu du repository
```

## Coût, avant et après

| | Aujourd'hui | Après |
|---|---|---|
| Lancement sans changement | 3 000 lectures | **1** |
| Lancement avec changement | 3 000 | 1 + ⌈N/500⌉ = 7 |
| Au pic (50 k × 3 lancements) | ~450 M/jour, ~270 $/jour | ~450 k/jour, ~0,3 $/jour |
| Reconstructions serveur | — | ~0,05 $/jour |

## Tests

**JS (`node:test`)** sur `communityBundles.ts`, logique pure : un changement de `upvotes` ne salit
pas, un changement de `status` salit, un `shadowHidden` salit, une création salit, une suppression
salit ; et la décision de reconstruire (sale → oui, propre et récent → non, propre et vieux d'une
heure → oui).

**Swift (Swift Testing)** : `Contribution` fait l'aller-retour JSON avec les clés que la Function
écrit ; `CommunityModel` expose bien les spots du store et applique le filtre des auteurs bloqués
par-dessus.

## Ce qui n'est PAS dans ce chantier

- **L'agrégation des pins communautaires à l'affichage** (`MapScrollView`, `ForEach(communitySpots)`
  sans clustering). C'est un problème de rendu, pas de coût de lecture — chantier voisin, distinct.
- La modération par lieu (regroupement des propositions à l'écriture).
- Le déploiement des Functions, qui demande une action authentifiée.
