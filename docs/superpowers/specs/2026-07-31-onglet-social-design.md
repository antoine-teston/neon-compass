# Onglet Social — les événements Online et le classement des contributeurs

**Date** : 2026-07-31
**Statut** : validé, prêt pour le plan d'implémentation
**Dépend de** : `2026-07-31-profil-complet-design.md` (libère l'emplacement d'onglet)
**Amende** : spec fondatrice §11, qui excluait « fil social complet » de la v1

## Le problème

La spec fondatrice avait écarté le social de la v1 — décision juste à l'époque :
le coût de modération pour un dev solo au pic de sortie était le risque le mieux
identifié du projet. Mais elle disait aussi, §13, que « la longue traîne dépendra
du mode online de GTA VI ». C'est l'angle mort : l'app est conçue pour le pic de
sortie, or le pic dure six à dix semaines et l'Online dure des années.

GTA Online tourne encore aujourd'hui, treize ans après GTA V, sur une mécanique
simple : **une mise à jour hebdomadaire** de bonus et de remises, qui donne à
chaque joueur une raison de se reconnecter chaque semaine. C'est exactement la
boucle de rétention qui manque à un compagnon conçu pour un lancement.

L'ouverture de ce spec est délibérée et bornée : on ne construit pas un réseau
social, on construit **deux choses qui ne coûtent presque rien en modération** et
on décrit la troisième sans la construire.

## Le principe de dosage

Ce qui rend l'affaire tenable pour un dev solo tient en une règle, déjà éprouvée
ailleurs dans le projet : **pas de texte libre.** La spec fondatrice l'applique
au pseudo — « jamais de pseudo libre : supprime la modération des noms, le risque
d'usurpation et du data personnel ». Le Social reprend le même pari partout.

| Pilier | Ce qui est saisi par un utilisateur | Modération |
|---|---|---|
| Événements de la semaine | Rien — contenu éditorial publié par nous | Aucune |
| Classement des contributeurs | Rien — handles générés par nous, spots déjà modérés | Aucune |
| Recherche de coéquipiers *(v1.1)* | Un gamertag au format contraint, et rien d'autre | Quasi nulle |

Un corollaire structurant : **les deux piliers de v1 se lisent sans compte.** Le
compte n'est demandé qu'au moment de *figurer* au classement, jamais pour entrer
dans l'onglet. Si le Social avait été bâti sur le seul LFG, il aurait été un mur
de connexion pour les 90 % qui ne se connecteront jamais.

## Pilier 1 — Les événements de la semaine (v1)

### D'où vient la donnée

Aucune API n'existe et aucune n'est envisageable. Le chemin est celui du reste du
contenu, déjà construit et déjà arbitré :

| Source | Statut | Usage |
|---|---|---|
| Rockstar Newswire | ❌ `robots.txt : ClaudeBot Disallow: /` (relevé 29/07/2026) | **Interdit à la veille automatique.** Observation humaine uniquement |
| GTABOOM, Leonidaverse, GTA6.gg | ✅ robots.txt vérifiés ; Leonidaverse nomme `ClaudeBot` en `Allow` | **Le chemin réel** — leurs flux relaient l'update hebdomadaire en quelques heures |
| Jeu en main | ✅ | Source primaire : l'écran des remises, lu et saisi à la main |

`tools/content-cli/source-policy.mjs` fait déjà autorité et lève sur un domaine
interdit ; ce spec n'ajoute aucune source, il réutilise le registre existant.

**Coût d'exploitation, dit franchement** : un run le jeudi, environ vingt minutes
de relecture humaine, chaîne `data-scout → facts-to-online-event → content-qa →
publish`. C'est un engagement récurrent, pas une livraison ponctuelle. Il doit
être accepté maintenant plutôt que découvert en décembre.

### Un type de contenu à part

Les événements ne sont **pas** une extension de `news.schema.json`. Deux raisons
concrètes :

1. Une entrée d'actu vit sur sa `publishedAt` — `FeedModel` trie par comparaison
   de chaînes, et le schéma impose pour cela une date courte sans horodatage. Un
   événement vit sur son `endsAt`. Mélanger les deux temporalités dans un même
   tri est un piège certain.
2. Les champs typés (bonus, remises, podium) seraient vides pour 90 % des entrées
   du fil.

La rubrique `category: "event"` de `news` reste valable pour l'annonce ponctuelle
et datée — il n'y a pas de conflit, ce sont deux objets différents.

`content/schema/online-event.schema.json` :

```
id             "online_gtav_2026_w31"        pattern ^online_[a-z0-9_]+$
game           "gtav" | "leonida"            ← Game, déjà unifié (Core/Game.swift)
startsAt       ISO court
endsAt         ISO court
title          localized
bonuses[]      { activity: localized, label: localized }
discounts[]    { item: localized, percent: entier 1-100 }
podiumVehicle  localized | absent
sources[]      ≥ 1
confidence     confirmed-official | multi-source | single-source | rumor
status         draft | published
```

`sources`, `confidence` et `status` sont repris tels quels de `news.schema.json` :
même pipeline, mêmes garanties, et `check-publishable` refuse déjà de publier une
rumeur. **`check-originality.mjs` doit couvrir ce nouveau type** — une liste de
remises nomme des véhicules et des commerces, ce sont des références factuelles
comme les POI, mais elles ne peuvent pas passer sans contrôle.

### L'écran

`SocialScreen` → `OnlineEventsSection`. La carte de la semaine porte :

- Le compte à rebours, calculé sur `endsAt`
- Les bonus (activité + libellé)
- Les remises (bien + pourcentage)
- Le véhicule du podium, s'il y en a un

Un sélecteur de jeu n'apparaît **que si les deux jeux ont des événements** — même
règle que `gamesWithChallenges` côté progression. Tant que Leonida n'a pas ouvert
son Online, il n'y a rien à choisir et rien ne s'affiche.

### Le compte à rebours est le produit

Un article de site raconte la semaine ; personne ne prévient un joueur que le
double GTA$ finit demain. **C'est le rappel qui vaut l'onglet, pas la carte.**

**C'est une notification locale, pas un push.** `endsAt` est connu de l'appareil
dès la synchronisation du contenu : le rappel se programme sur place à
`endsAt − 24 h`, et se reprogramme à chaque synchronisation. Aucune Cloud
Function, aucun topic FCM, aucun compte, et le rappel tombe même si l'appareil
n'a pas vu le réseau depuis. C'est ce qui garde B1 entièrement autonome du
serveur.

Un `LocalNotificationScheduling` dans `Core/Notifications/` s'ajoute à côté de
`FollowedCategoryNotifying` — la demande d'autorisation vit aujourd'hui sur ce
dernier, qui est réservé au Pro ; le rappel d'événement doit pouvoir la demander
sans entitlement.

Elle est **gratuite** : la spec fondatrice §5 réserve le Pro aux notifications
suivies par catégorie de POI et précise que « les notifications générales restent
gratuites ». Un crochet de rétention derrière un paywall ne retient personne.

### Le jour de reset n'est pas codé en dur

GTA Online se met à jour le jeudi ; la cadence de Leonida est inconnue. Le compte
à rebours vient donc **toujours de `endsAt` du contenu publié**, jamais d'un
calcul de jour de semaine. Le seul usage d'un jour nommé est la phrase
d'information affichée quand aucun événement n'est publié — un paramètre Remote
Config (`onlineResetWeekday`, défaut jeudi) permet de la corriger sans mise à
jour de l'app.

## Pilier 2 — Le classement des contributeurs (v1)

### Pourquoi celui-là et pas un classement de complétion

Un classement de complétion serait **auto-déclaratif** : cocher « Trouvé » sur la
carte n'est vérifié par personne. Il ne vaut rien et il n'existera pas.

L'XP est d'une autre nature. Spec fondatrice §5 : « XP gagnée par contribution
approuvée et par vote reçu », et « le niveau est calculé côté serveur (Cloud
Function à l'approbation) — jamais par le client ». Elle se gagne en faisant
approuver du contenu par un modérateur et en recevant des votes d'autrui : elle
est méritée et ingâchable par son propre bénéficiaire.

**Classer sur les contributions approuvées, jamais soumises.** C'est la
différence entre récompenser la qualité et récompenser le volume — et c'est la
modération qui encaisserait la seconde.

### L'architecture : jamais une requête client sur les profils

Les Security Rules sont deny-by-default, et balayer la collection des profils
depuis le client serait à la fois un coût et une fuite.

Une Cloud Function planifiée `rebuildLeaderboard.ts`, calquée sur
`rebuildCommunityBundles.ts` (même motif d'agrégation planifiée vers un document
unique, déjà en production) :

- écrit **un seul document** `leaderboards/weekly` — top 50 : handle, XP, nombre
  de spots approuvés ;
- dépose le rang personnel dans `profiles/{uid}`, que le Profil affiche
  (spec A) ;
- exclut les comptes shadow-bannés, mécanisme déjà décrit à la spec fondatrice
  §Anti-abus.

Chaque client lit deux documents, quel que soit le nombre d'utilisateurs.

Lecture sans compte. Y figurer en demande un. Et comme le reste du serveur, la
section disparaît proprement quand `ServerFeaturesModel` est faux — pas de
section vide.

## Pilier 3 — La recherche de coéquipiers (v1.1, décrite, non construite)

Décrite ici pour que le modèle de données de la v1 n'ait pas à être
rétro-adapté ; elle aura son propre spec et son propre plan.

**Pourquoi pas maintenant.** Deux raisons, dont une seule est de la prudence :

1. Un LFG sans Online ouvert ne sert à rien. GTA Online avait suivi GTA V de deux
   semaines ; si Leonida fait de même, le LFG arrive utile en décembre — et il
   donne une raison de rouvrir l'app après le pic.
2. C'est de l'UGC temps réel : dossier Apple 1.2 (signalement, blocage, EULA,
   traitement < 24 h), App Privacy labels à revoir (un gamertag est une donnée
   personnelle), classification d'âge à réexaminer. L'ajouter à la soumission de
   fin octobre exposerait le lancement à un motif de rejet de plus, sur un
   planning qui porte déjà le Plan 7.

**Écarté explicitement** : le livrer éteint par Remote Config dans la build
d'octobre. Le projet a bien ce mécanisme, mais il éteint partout du déjà-vu à la
review ; allumer après coup une fonctionnalité jamais vue tombe sous la règle
2.3.1, et c'est précisément sur de l'UGC que ça se remarque.

**Forme retenue** : annonce sans aucun texte libre — activité (liste fermée),
plateforme (liste fermée), micro oui/non, places, langue, créneau, et un seul
champ saisi, le gamertag PSN/Xbox validé par un format strict (jeu de caractères
et longueur par plateforme). TTL 24 h sur l'annonce. Le gamertag entre à
l'inventaire RGPD §14 : publié volontairement, effacé avec le compte, effacé avec
l'annonce.

## Livraison

Deux paliers indépendants, et c'est le dé-risquage principal :

| Palier | Contenu | Dépend de |
|---|---|---|
| **B1** | Schéma, pipeline, `SocialScreen`, événements, rappel local | Rien de serveur. Ni compte, ni Cloud Function, ni `ServerFeaturesModel` |
| **B2** | `rebuildLeaderboard.ts` + section classement | Cloud Functions déployées |

**B1 seul justifie l'onglet.** Si le planning se tend fin octobre, B2 saute sans
laisser de trou dans l'écran.

L'onglet démarre sur les événements **GTA V Online** et bascule sur Leonida quand
son Online ouvre, sans changement de code — le champ `game` suffit. Effet de bord
recherché : l'onglet est utile *avant* le 19 novembre, ce qui donne quelque chose
à montrer aux créateurs de contenu en octobre (spec fondatrice §12, « accès
TestFlight anticipé »).

## Erreurs et états dégradés

| Situation | Ce que l'app montre |
|---|---|
| Hors ligne | L'événement en cache, avec sa vraie date de fin |
| `endsAt` dépassé | « Terminé » et la phrase de prochaine mise à jour — **jamais** un compte à rebours négatif |
| Aucun événement publié | La phrase de cadence seule, sans contenu inventé |
| Une des trois sources tombe | Le run continue sur les autres ; `source-policy.mjs` arbitre |
| `ServerFeaturesModel` faux | Pas de classement, et pas de section vide non plus |
| Non connecté | Tout le Social reste lisible |

## Tests

- `OnlineEvent` — décodage, et la fenêtre active/périmée avec un `now` **injecté**,
  jamais `Date.now` en dur : c'est la seule façon de tester un compte à rebours.
- `OnlineEventsModel` — sélection de l'événement courant parmi plusieurs,
  affichage du sélecteur de jeu seulement si les deux jeux sont pourvus.
- `LeaderboardModel` — décodage du document unique, absence gracieuse.
- La programmation du rappel — l'heure calculée est bien `endsAt − 24 h`, aucun
  rappel n'est programmé pour un événement déjà terminé, et une reprogrammation
  ne laisse pas de doublon. Testé sur un `LocalNotificationScheduling` factice,
  sans jamais toucher `UNUserNotificationCenter`.
- Node : validation de `online-event.schema.json` et
  `facts-to-online-event.test.mjs`, sur le modèle de `facts-to-news.test.mjs`.
- Functions : `rebuildLeaderboard.test.ts`, sur le modèle de
  `communityBundles.test.ts` — en particulier l'exclusion des shadow-bannés et le
  classement sur les approuvées.
- `LocalizationCoverageTests` couvre les nouvelles clés dans les cinq langues.

## Risques

| Risque | Parade |
|---|---|
| **Le jeudi devient un engagement.** Une semaine ratée fait vieillir l'onglet | L'app dit « terminé » d'elle-même et ne prétend jamais qu'un bonus est en cours. Un onglet honnêtement vide vaut mieux qu'un onglet qui ment |
| **Le classement noie la modération** sous des spots médiocres | Classer sur les approuvées uniquement ; le monitoring de vélocité de la spec §Anti-abus marque déjà les bursts |
| **Une source tierce ferme ou change de format** | Trois sources autorisées, run tolérant à la perte de l'une ; en dernier recours, saisie manuelle — le volume est d'un événement par semaine |
| **L'Online de Leonida n'ouvre pas avant longtemps** | L'onglet vit sur GTA V Online entre-temps, ce qui était de toute façon le plan de départ |
| **Reproche de « fil social » à la review** | Aucun texte libre, aucun message privé, aucune photo en v1 ; les seules chaînes affichées sont éditoriales ou générées par nous |

## Ce qui n'est pas fait ici

- La recherche de coéquipiers (décrite, non construite).
- Toute messagerie, tout envoi d'image, tout profil public consultable.
- Un widget de compte à rebours d'événement — tentant, mais c'est de la surface
  Pro et ça attendra d'avoir vu si l'onglet prend.
- Un historique des semaines passées : un bonus expiré n'intéresse personne.
