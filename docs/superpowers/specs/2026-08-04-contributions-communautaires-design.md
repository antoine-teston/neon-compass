# Les contributions communautaires — VI seulement, et un volet pour les voir

**Date** : 2026-08-04
**Statut** : validé, prêt pour les plans d'implémentation
**Prolonge** : `2026-07-31-onglet-social-design.md` (piliers 1 et 2), et referme trois
défauts relevés en relisant le chemin de contribution après
`2026-08-04-profil-connecte-design.md`.

## Le problème

### Trois défauts, pas un besoin d'esthétique

**Un no-op silencieux.** `MapScreen.swift:356-359` :

```swift
Button("map.longPress.proposeSpot") {
    if authModel.userID != nil {
        pendingContributionLocation = pendingPinLocation
    }
    pendingPinLocation = nil   // ← pas de `else`
}
```

Déconnecté, on appuie sur « Proposer un lieu » et il ne se passe rien. Ni alerte,
ni invitation à se connecter : le menu se referme. C'est d'autant plus grave que
le Profil vient de gagner une invitation qui envoie explicitement faire ce geste.

**Les contributions ne savent pas de quelle carte elles parlent.** La table
`contributions` ne porte que `position_x` / `position_y`
(`20260802120000_initial_schema.sql:94-95`), et `MapScreen` passe `visibleSpots`
à la carte sans filtrer par `mapGame`. Aujourd'hui c'est invisible — la carte VI
est un placeholder sans contenu et l'app ouvre volontairement sur la référence
(`MapScreen.swift:29-33`). Le jour où VI a des positions, chaque contribution
apparaîtrait **sur les deux cartes à la fois**.

**Le vote n'a aucun état.** `ContributionAnnotationView` affiche deux compteurs et
deux boutons ; rien ne distingue « je n'ai pas voté » de « j'ai voté pour ». On
peut retaper indéfiniment sans jamais savoir où on en est. La catégorie, choisie
à la soumission, n'est affichée nulle part non plus.

### Et un endroit qui manque

Voter se fait aujourd'hui dans le popover d'une épingle. C'est le seul chemin, et
il suppose de trouver des épingles sur une carte. Avant la sortie du 19 novembre,
la carte VI est vide : une contribution existerait sans qu'aucune surface de
l'app ne puisse la montrer.

## Les décisions

### 1. La soumission n'est possible que sur la carte VI

Décision de produit, et elle simplifie tout : **aucune colonne de jeu n'est
ajoutée à `contributions`**, puisque le jeu est connu par construction.

Elle se tient éditorialement. La carte de référence est intégralement documentée
depuis dix ans ; il n'y a rien à y découvrir. Toute la raison d'être des
contributions est la carte que personne n'a encore parcourue.

Conséquences :

- Le bouton « Proposer un lieu » n'apparaît que si `mapGame == .leonida`.
- `MapScreen` ne transmet les spots communautaires que dans ce cas.
- La règle est **côté client**. Ce n'est pas un relâchement : les positions sont
  normalisées `[0,1]` et rien, en base, ne permettrait de distinguer un point de
  Leonida d'un point de la référence. Le vrai verrou est la modération —
  `status` reste `pending` jusqu'à approbation humaine.

### 2. Le chemin déconnecté dit ce qui bloque

Le bouton reste **visible** hors connexion : le masquer priverait un visiteur de
la seule occasion d'apprendre que la contribution existe. Il ouvre une alerte qui
dit pourquoi, avec un bouton qui bascule sur l'onglet Profil — symétrique de
`ContributeHintSheet`, qui bascule dans l'autre sens.

### 3. Un volet Propositions dans Social

Un sélecteur segmenté en tête de `SocialScreen` : **Événements | Propositions**.

Le sélecteur de jeu conditionnel (`showsGamePicker`) redescend **dans** le volet
Événements, avec le classement et la bannière — jamais deux barres de segments
empilées.

**Pas de bascule V/VI en tête de Social**, et c'est la règle que le dépôt
applique déjà : `OnlineEventsModel.showsGamePicker` vaut `availableGames.count > 1`
précisément pour ne pas afficher un sélecteur à une seule valeur utile. Les deux
volets ne seraient d'ailleurs pas parallèles mais complémentaires dans le temps —
V a les événements et aucune proposition, VI a les propositions et pas encore
d'événements. Un croisement serait toujours vide. Le volet porte donc son
périmètre en sous-titre (« Carte VI · posées par la communauté ») plutôt qu'un
contrôle mort. Le jour où l'online VI ouvre, la bascule remonte en tête sans rien
casser.

Le classement reste avec les événements : il est **global** — de l'XP de
contributeur, pas du contenu de jeu — donc il n'a rien à faire sous une bascule
de jeu.

### 4. Deux sections, et pourquoi

```
Propositions
Carte VI · posées par la communauté

À DÉCOUVRIR
 ◉ Planque  · il y a 2 h
   Toit du parking sur la marina
   NEON-FALCON-88
   [▲ 12]  [▼ 1]              ⋯

LES MIEUX NOTÉES
 ▲ 214  Planque du nord
 ▲ 187  Rampe du viaduc
```

- **À découvrir** — approuvées sur lesquelles je n'ai pas voté, les plus récentes
  d'abord.
- **Les mieux notées** — triées par `upvotes − downvotes`.

**Pourquoi pas un tri unique par score.** Un vote positif rapporte +2 XP à son
auteur (`20260802120000_initial_schema.sql:285`). Un classement pur ferait que le
lieu jamais vu n'est jamais voté, donc reste jamais vu, et son auteur ne décolle
pas. La section « À découvrir » garantit que chaque proposition passe sous les
yeux au moins une fois.

**Les deux sections ne se recouvrent pas.** « Les mieux notées » exclut les
identifiants déjà affichés au-dessus. Deux fois la même ligne dans un écran se
lit comme un défaut, et une proposition d'il y a deux heures n'a pas besoin d'une
seconde apparition.

**Voter ne fait pas disparaître la ligne sous le doigt.** Elle reste en place, le
compteur bouge, et elle quitte « À découvrir » au prochain chargement. Retirer
une rangée sous le doigt qui vient de la toucher est désorientant.

Chaque ligne porte : pastille de catégorie, date relative, titre, pseudo de
l'auteur, les deux boutons de vote **avec mon état**, et un menu qui donne
signaler et masquer. La directive Apple 1.2 exige que ces deux gestes soient
atteignables partout où de l'UGC s'affiche — donc sur les deux surfaces, la liste
comme la carte.

### 5. Le popover de la carte s'allège

Il gagne la **catégorie**, qui n'était affichée nulle part. Ses compteurs de vote
passent en **lecture seule** : il dit ce qu'il y a là, il ne demande plus
d'arbitrer. Signaler et masquer y restent (Apple 1.2).

Chaque surface répond alors à sa propre question — la liste « qu'est-ce qui vient
d'être proposé », la carte « qu'est-ce qu'il y a ici » — et il n'y a plus qu'un
seul endroit à soigner pour le vote.

## Les données à faire venir

### `approved_at`, une colonne nouvelle

`created_at` existe (`initial_schema.sql:103`) mais date de la **soumission**. Un
lieu resté trois jours en modération arriverait déjà enterré dans « À découvrir »,
ce qui viderait de son sens la seule raison pour laquelle cette section existe.
Ce que la liste veut, c'est la date d'**apparition sur la carte**.

```sql
alter table public.contributions add column approved_at timestamptz;

-- Rétro-remplissage : pour l'existant, la date de soumission est la meilleure
-- approximation disponible, et elle est juste tant que la modération suit.
update public.contributions set approved_at = created_at where status = 'approved';
```

Posée par un **trigger** sur la transition vers `approved`. Contrairement à l'XP —
que `20260802170000_contribution_xp.sql` a délibérément refusé de mettre en
trigger, parce qu'une reprise de migration attribuerait des points en trop — un
horodatage est *dérivé*, pas une récompense, et la garde `approved_at is null` le
rend idempotent. Une réapprobation ne réécrit rien.

Le fichier de migration porte sa propre révocation sur la fonction du trigger :
`pg_default_acl` accorde tout à `anon` et `authenticated` sur les objets
nouvellement créés, et `supabase/tests/privileges_test.sql` nomme l'objet fautif
sinon.

### La colonne traverse le bundle

Le `select` de `rebuild-community-bundles/index.ts:72` s'arrête à `downvotes`. Il
gagne `approved_at`, et le mapping gagne `approvedAt`.

`Contribution` gagne `let approvedAt: Date?` — **optionnel**. Un cache SwiftData
antérieur à ce changement n'a pas le champ ; le rendre obligatoire ferait échouer
le décodage de tout le fragment en cache, donc viderait la carte hors ligne. Les
lignes sans date se rangent en fin de section.

### Mes votes

```
select contribution_id, direction from votes where uid = auth.uid()
```

Autorisée par `votes_select_own` (`20260802120100_rls_policies.sql:95-97`) et
servie par l'index `votes_uid_idx`. Requête directe, pas le bundle : elle est
personnelle et doit être fraîche.

C'est elle qui découpe les deux sections **et** qui donne enfin un état visible au
vote. Une seule lecture règle les deux.

## Architecture

### Le tri est un type pur

**`Core/Community/ContributionSections.swift`** — toute la logique de découpage,
sans SwiftUI ni I/O, donc testable :

```swift
struct ContributionSections: Equatable {
    let discover: [Contribution]
    let top: [Contribution]

    /// `discover` : non votées par moi, `approvedAt` décroissant, les sans-date
    /// en fin. `top` : score décroissant, EXCLUANT ce que `discover` montre
    /// déjà, départage par `approvedAt` puis par `id` pour que l'ordre soit
    /// stable d'un rendu à l'autre.
    init(spots: [Contribution], myVotes: [String: VoteDirection], limit: Int = 20)
}
```

Le départage par `id` n'est pas cosmétique : `upvotes − downvotes` produit
énormément d'ex æquo à zéro au démarrage, et un tri instable ferait sauter les
lignes à chaque réévaluation de la vue.

### Ce qui s'ajoute ailleurs

| Fichier | Changement |
|---|---|
| `Core/Community/ContributionRepository.swift` | `fetchMyVotes(uid:) async throws -> [String: VoteDirection]` |
| `Core/Community/SupabaseContributionRepository.swift` | son implémentation |
| `Core/Community/Contribution.swift` | `let approvedAt: Date?` |
| `Features/Community/CommunityModel.swift` | `myVotes`, `loadMyVotes(uid:)`, et `vote(on:direction:)` qui met `myVotes` à jour localement |
| `Features/Social/ContributionsPanel.swift` | **créé** — le volet et ses deux sections |
| `Features/Social/ContributionRow.swift` | **créé** — une ligne, ses votes, son menu |
| `Features/Social/SocialScreen.swift` | le sélecteur de volets ; l'existant devient le volet Événements |
| `Features/Community/ContributionAnnotationView.swift` | catégorie ajoutée, votes en lecture |
| `Features/Map/MapScreen.swift` | garde VI, correction du no-op déconnecté |
| `supabase/migrations/20260804120000_contribution_approved_at.sql` | **créée** |
| `supabase/functions/rebuild-community-bundles/index.ts` | `approved_at` au `select` et au mapping |

`SocialScreen` fait 161 lignes et porte déjà les événements, le classement, la
minuterie et la publicité. Le volet Propositions y ajouterait une centaine de
lignes de liste : il part donc dans ses propres fichiers, et `SocialScreen` ne
garde que la structure.

**Une seule alerte de connexion, partagée.** Le bouton de proposition sur la
carte et le vote dans la liste butent sur la même condition et doivent dire la
même chose. `Features/Community/SignInToContributeAlert.swift` porte le
modificateur ; les deux appelants le posent, et son bouton bascule sur l'onglet
Profil via `AppModel`, désormais dans l'environnement.

## Erreurs et états dégradés

| Situation | Comportement |
|---|---|
| Déconnecté | La liste est lisible, les deux sections existent ; « À découvrir » contient tout puisqu'on n'a voté sur rien. Voter ouvre la même alerte que le bouton de proposition |
| `ServerFeaturesModel` faux | Le volet Propositions n'apparaît pas : voter passe par une Edge Function, et l'offrir promettrait un service qui n'arrive jamais |
| Coupe-circuit communautaire fermé | Idem — même garde que le bouton de proposition, qui la porte déjà |
| Aucune proposition publiée | Un état vide qui dit que la carte VI s'ouvre à la sortie. Pas de bannière publicitaire dessus : la spec §5 la réserve aux écrans de liste, et un état vide n'en est pas un (même correctif que celui déjà appliqué aux événements) |
| Hors ligne | Le bundle en cache s'affiche ; `fetchMyVotes` échoue en silence et les sections retombent sur « tout dans À découvrir » |
| `approvedAt` absent | La ligne se range en fin de « À découvrir » plutôt que de faire échouer le décodage |
| Sur la carte V | Ni bouton de proposition, ni épingle communautaire |
| Auteur masqué | Ses propositions sortent des deux sections — `visibleSpots` filtre déjà |

## Tests

**Nouveaux**, en logique pure :

- `ContributionSectionsTests` — une votée sort de « À découvrir » ; l'ordre suit
  `approvedAt` décroissant ; une sans date passe en fin ; « les mieux notées »
  n'affiche pas ce qui est déjà au-dessus ; deux ex æquo gardent un ordre stable ;
  le plafond s'applique par section.
- `ContributionTests` — un fragment sans `approvedAt` se décode quand même.
- `CommunityFakesTests` (suite existante des doublures de `CommunityModel`) —
  `vote(on:)` met `myVotes` à jour sans attendre un rechargement, et un auteur
  masqué disparaît des deux sections.

**Vérification visuelle** : le volet dans ses trois états (garni, vide,
déconnecté), et la carte VI contre la carte V pour la présence du bouton.

**Ne doivent pas régresser** : `CommunityFakesTests`, `OnlineEventsModelTests`,
`LeaderboardTests`, `LocalizationCoverageTests`, `SmokeTests`,
`privileges_test.sql`, `schema_test.sql`.

## Livraison

Deux plans indépendants.

| Plan | Contenu | Utile seul ? |
|---|---|---|
| **A** | Migration `approved_at`, bundle, `Contribution`, garde VI, correction du no-op, popover allégé | Oui — ferme un bug et une incohérence de données |
| **B** | `ContributionSections`, `fetchMyVotes`, le volet Social et ses lignes | Suppose A |

## Ce qui n'est pas fait ici

- **Le bouton « Voir sur la carte »** depuis une ligne de la liste. Il faudrait
  piloter le `focusRequest` de `MapScreen` — aujourd'hui un `@State` privé —
  depuis un autre onglet, pour aboutir sur une carte vide jusqu'au 19 novembre.
  La liste se suffit : titre, catégorie, auteur, votes.
- **Aucun changement au calcul de l'XP** ni à la modération.
- **La recherche de coéquipiers** (pilier 3 de la spec Social), toujours v1.1.
- **Le classement** ne bouge pas : il reste dans le volet Événements.
