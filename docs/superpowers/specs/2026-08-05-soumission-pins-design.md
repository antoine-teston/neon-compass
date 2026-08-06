# La soumission d'un lieu — poser, nommer, savoir

**Date** : 2026-08-05
**Statut** : validé, prêt pour les plans d'implémentation
**Prolonge** : `2026-08-04-contributions-communautaires-design.md`, qui a soigné
la lecture et le vote des contributions sans jamais toucher au geste qui les
crée.

## Le problème

Le chemin de soumission est le dernier morceau du pilier communautaire à n'avoir
jamais été conçu. Il tient en deux pièces : un `confirmationDialog` d'appui long
(`MapScreen.swift:330-379`) et une feuille de 46 lignes
(`ContributionSubmissionSheet.swift`) — un `Form` système, un `Picker` de menu,
un `TextField`. Cinq défauts s'y empilent.

### Aucun retour, ni succès ni échec

```swift
onSubmit: { category, title in
    try? await communityModel.submit(…)   // ← MapScreen.swift:388
    pendingContributionLocation = nil
}
```

`CommunityModel.submit` est pourtant `async throws`, et l'Edge Function refuse de
cinq façons distinctes et parlantes : 503 coupe-circuit, 400 validation, 429
cooldown, 400 vocabulaire banni, 409 doublon géographique — plus le 401 de
`requireUser` et les pannes. Le `try?` les rend toutes indiscernables du succès.
La feuille se referme, et rien ne s'est passé.

C'est le même défaut de classe que le no-op déconnecté fermé la veille : une
action qui échoue en silence.

### Rien ne dit que ça part en modération

Le statut à l'insertion est `pending` (`submit-contribution/index.ts:92`). Le
joueur cherchera son épingle sur la carte et ne la trouvera jamais. « Mes
propositions » existe pourtant déjà dans le Profil, avec les trois statuts
(`ProfileScreen.swift:85-112`) — aucun chemin n'y mène depuis le geste.

### La position n'est ni montrée ni ajustable

Le point retenu est celui de l'appui long : là où était le pouce, au zoom du
moment. Rien ne le montre, rien ne le corrige. Or une position fausse est
précisément ce qui fait rejeter une proposition, et cela ne se rattrape plus
après l'envoi.

### Un formulaire système nu

`POIPinPalette` donne un symbole et deux couleurs pour chacune des six
catégories, et l'éditeur interne en fait déjà une grille de pastilles
(`EditorCategoryGrid.swift`) — la feuille livrée, elle, a un `Picker` de menu.
Pas de compteur pour la limite de 280, pas d'indicateur pendant l'envoi.

### La boucle d'XP ne se referme pas

`ContributeHintSheet` envoie explicitement faire ce geste depuis le Profil. Le
geste, lui, ne dit rien de ce qu'il rapporte.

## Les décisions

### 1. L'épingle fantôme vit DANS la carte, jamais au-dessus

C'est la contrainte qui commande toute la suite, et elle est déjà documentée en
tête du moteur (`MapScrollView.swift:4-14`) :

> les pins bougent AVEC la carte, sur la même horloge : plus de décalage d'une
> frame comme avec l'ancien design (pins en overlay SwiftUI séparé,
> repositionnés via un `@State` poussé depuis `scrollViewDidScroll` — la carte
> bouge côté render server, les pins rattrapaient une frame plus tard côté main
> thread).

Poser l'épingle fantôme en calque au-dessus de la vue de défilement serait donc
refaire exactement le design que le projet a mesuré puis abandonné. Elle est une
annotation du contenu hébergé, comme toutes les autres.

Son dessin reprend celui de `draftPin` (`MapScrollView.swift:239-260`) : anneau
pointillé, cœur neutre, symbole de la catégorie. Elle **change de couleur en
direct** quand on touche une autre pastille — c'est la seule confirmation qu'on a
choisi la bonne catégorie.

### 2. Taper ailleurs déplace, glisser affine

Vivant dans le contenu hébergé, l'épingle entre en concurrence avec le
`panGestureRecognizer` de l'`UIScrollView`. Deux reconnaisseurs, actifs
uniquement en placement, résolvent la question sans arbitrage coûteux :

```swift
// Déplace l'épingle sous le doigt. Un tap ne concurrence jamais un pan :
// aucune relation d'échec à déclarer.
placementTap = UITapGestureRecognizer(…)
placementTap.cancelsTouchesInView = true

// Affine, seulement si le toucher démarre sur l'épingle.
placementDrag = UIPanGestureRecognizer(…)
scrollView.panGestureRecognizer.require(toFail: placementDrag)
```

`gestureRecognizerShouldBegin` rend `false` hors placement ou hors de la zone de
frappe de l'épingle : le reconnaisseur échoue alors immédiatement, donc le
`require(toFail:)` ne retarde pas le panoramique — c'est la seule raison pour
laquelle cette relation est acceptable sur le geste le plus sensible de l'app.

`cancelsTouchesInView` est ce qui empêche un tap de placement d'ouvrir la fiche
d'un POI qu'il traverserait. En placement, taper la carte veut dire « pose-la
ici », jamais « ouvre ça ».

**Pourquoi les deux et pas l'un des deux.** Un glisser se termine toujours sous le
doigt : les vingt derniers points se font à l'aveugle. Un tap après un zoom est
précis et se répète. Le glisser reste pour le décalage de trois points, qu'un tap
rendrait pénible.

### 3. Un panneau, pas une feuille

La carte a déjà tranché contre la feuille système pour la fiche d'un POI
(`MapScreen.swift:426-449`) : un panneau posé dans l'arbre, avec `.contentShape(.rect)`,
`.accessibilityAddTraits(.isModal)` et une action d'échappement. La soumission a
le même besoin, en plus fort — elle doit voir la carte pendant qu'on ajuste.

Le panneau suit la même règle d'adaptation : bord bas en compact, bord *trailing*
en régulier (règle iPad du `CLAUDE.md`). Aucun `ToolbarItem` : cet écran d'onglet
n'a pas de barre, et un `ToolbarItem` y disparaîtrait sans erreur.

**En entrant en placement, la carte recentre le point dans la portion restée
visible.** Sans cela, un appui long dans le tiers bas met l'épingle fantôme sous
le panneau. Le `focusRequest` existe déjà (`MapScreen.swift:236`).

### 4. Trois états dans le même panneau

```
   PLACEMENT                        CONFIRMATION
┌──────────────────────────┐   ┌──────────────────────────┐
│ Proposer un lieu         │   │ ✓ Proposition envoyée    │
│ Carte VI · relu avant    │   │                          │
│ d'être publié            │   │ Elle apparaîtra sur la   │
│                          │   │ carte une fois relue.    │
│ ▣ Lieu  ◆ Collec. ⚑ Acti.│   │ 20 XP à l'approbation.   │
│ ⌂ Planq. ⛃ Véhic. ▦ Évén.│   │                          │
│                          │   │ Voir mes propositions →  │
│ ┌──────────────────────┐ │   │               [Terminé]  │
│ │ Nom du lieu…         │ │   └──────────────────────────┘
│ └──────────────────────┘ │
│ Annuler       [Envoyer]  │      REFUS = PLACEMENT + bandeau
└──────────────────────────┘      en tête, saisie intacte
```

**Le refus ne referme rien, et c'est l'argument décisif du panneau sur le
bandeau fugace.** Sur un 429 il faut attendre soixante secondes, sur un 409
déplacer l'épingle, sur un 400 reformuler : les trois exigent de **retrouver ce
qu'on avait tapé**. Un panneau qui se referme le jette.

**Le sous-titre annonce la modération avant la frappe.** L'apprendre au moment où
« envoyé » s'affiche arrive trop tard pour changer quoi que ce soit à ce qu'on
écrit.

**Le compteur n'apparaît qu'à partir de 240 sur 280.** Un compteur permanent sur
un champ que personne n'approche est du bruit ; il doit surgir quand il commence
à compter.

**Les XP se disent à la confirmation, et se disent juste : 20 à l'approbation.**
`award_contribution_xp` ne crédite rien à la soumission
(`20260802170000_contribution_xp.sql`) — c'est une fonction appelée par
`moderate:approve`, délibérément pas un trigger. Promettre 20 XP en envoyant
serait faux d'une durée de modération.

**La grille remplace le `Picker`.** Six pastilles, `POIPinPalette.symbol` et
`.color`, libellés par `localizedNameKey`. On n'étend pas `EditorCategoryGrid` :
il est `#if DEBUG` avec des littéraux français, et le fusionner traînerait du
code d'éditeur en Release. Le pendant localisé s'écrit dans `Features/Community`.

### 5. Le serveur gagne un code machine

Les messages de l'Edge Function sont de l'anglais en dur — les afficher tels
quels donnerait de l'anglais à un francophone, et lire le nombre de secondes du
cooldown dans `Please wait before submitting again (42s)` serait fragile.

```ts
export class HttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly code?: string,       // ← nouveau
    readonly retryAfter?: number, // ← nouveau
  ) { super(message) }
}
```

`serveJSON` sérialise `{ error, code, retryAfter }` quand ils sont présents.
Ajout **rétro-compatible** : les autres fonctions ne posent pas ces champs et
leur réponse ne change pas.

Le `code` fait autorité côté client, le statut n'est qu'un repli — c'est la seule
façon de distinguer les **deux 400** (validation de forme et vocabulaire banni),
qui n'appellent pas la même phrase.

### 6. Le 429 se prévient avant de partir

L'app garde localement l'heure du dernier envoi réussi. Deux propositions
d'affilée sur le même téléphone — le cas courant — n'atteignent jamais le réseau :
「Envoyer」est désarmé et le décompte s'affiche d'emblée. Le serveur reste
l'autorité pour le cas multi-appareil, que la mémoire locale ne peut pas
connaître.

### 7. Mes propositions pas encore publiques s'affichent sur la carte VI

```swift
myContributions.filter { $0.status != .rejected && !visibleSpots.contains(id: $0.id) }
```

Deux raisons : la question « où est passée ma proposition ? » se pose sur la
carte, donc la réponse doit y être ; et avant le 19 novembre c'est la seule chose
qui rendra la carte VI non vide pour celui qui vient de la remplir.

**Le `rejected` est exclu** — une cicatrice permanente n'apprend rien, et le
Profil porte déjà ce statut.

**L'`approved` pas encore dans le fragment est inclus**, et ce n'est pas un
détail : la reconstruction des fragments est une tâche `*/5 * * * *` qui
elle-même n'agit que sur drapeau `dirty`
(`20260802150000_scheduling.sql:51-64`), et l'app ne retélécharge que si la
version du manifeste a bougé. Le trou entre l'approbation et le fragment se
compte en minutes, parfois en lancements. Sans cette clause, l'épingle
disparaîtrait puis reviendrait sans raison visible — exactement le défaut qu'on
reproche à un fantôme purement local.

Même dessin dans les deux cas, phrase différente au popover : « en attente de
relecture » ou « approuvée — elle arrive sur la carte de tous ».

**Rien à faire pour le *shadow ban*** : `Contribution` ne modélise pas
`shadow_hidden`, donc un auteur masqué voit sa proposition comme les autres. Le
principe du procédé est qu'il ne le sache pas.

Ces épingles ne sont **pas groupées** : elles sont les miennes, elles se comptent
sur les doigts. Elles se dessinent directement, comme `draftPins`.

## Architecture

### La machine à états est un type pur

`Core/Community/ContributionPlacement.swift` — toute la logique du panneau, sans
SwiftUI ni I/O, donc testable. Même parti que `ContributionSections`.

```swift
struct ContributionPlacement: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case editing(ContributionSubmissionError?)
        case sending
        case confirmed
    }

    var position: NormalizedPoint
    var category: POICategory = .landmark
    var title: String = ""
    var phase: Phase = .editing(nil)

    /// Instant avant lequel « Envoyer » reste désarmé. Nourri par le 429 du
    /// serveur ET par le dernier envoi réussi connu localement.
    var retryAfter: Date?

    var trimmedTitle: String
    func canSubmit(now: Date) -> Bool
    func remainingCooldown(now: Date) -> Int?

    /// Les deux effacent un 409 en cours : déplacer ou changer de catégorie
    /// sont précisément ce qui lève ce refus, la déduplication étant bornée à
    /// une catégorie et à un rayon.
    mutating func moved(to position: NormalizedPoint)
    mutating func picked(_ category: POICategory)

    mutating func failed(with error: ContributionSubmissionError, now: Date)
    mutating func succeeded()
}
```

`now` en paramètre obligatoire, jamais lu en interne : convention déjà posée par
`hubToFact`, et c'est ce qui rend le cooldown testable sans attendre une minute.

### L'erreur est typée

`Core/Community/ContributionSubmissionError.swift` :

```swift
enum ContributionSubmissionError: Error, Equatable, Sendable {
    case cooldown(retryAfter: Int)  // 429 · code "cooldown"
    case duplicateNearby            // 409 · code "duplicate"
    case titleRejected              // 400 · code "vocabulary"
    case signedOut                  // 401
    case disabled                   // 503 · code "disabled"
    case failed                     // 500, réseau, et tout le reste

    init(status: Int, body: Data?)
}
```

Le code `invalid` (400 de forme) tombe sur `.failed` et non sur `.titleRejected` :
la longueur est déjà bornée côté client et les positions sont normalisées par
construction, donc ce refus ne peut venir que d'un défaut à nous. « Reformulez »
serait un mauvais conseil.

Un 429 sans `retryAfter` retombe sur 60 s — la valeur de `COOLDOWN_SECONDS`.

### Ce qui s'ajoute ailleurs

| Fichier | Changement |
|---|---|
| `Core/Community/ContributionPlacement.swift` | **créé** — la machine à états |
| `Core/Community/ContributionSubmissionError.swift` | **créé** — l'erreur typée |
| `Features/Community/ContributionPlacementPanel.swift` | **créé** — le panneau, ses trois états |
| `Features/Community/ContributionCategoryGrid.swift` | **créé** — les six pastilles, localisées |
| `Features/Community/PendingContributionAnnotationView.swift` | **créé** — l'épingle pointillée et son popover, autonome comme `ContributionAnnotationView` |
| `Core/Map/MapScrollView.swift` | famille `unpublishedSpots` et épingle fantôme dans le contenu ; les deux reconnaisseurs ; `onPlacementMoved` ; `ContentToken` gagne la génération |
| `Features/Map/MapScreen.swift` | `placement` remplace `pendingContributionLocation` ; le panneau ; `loadMyContributions` à l'apparition, au retour au premier plan et après un envoi |
| `Features/Community/CommunityModel.swift` | `myUnpublishedSpots`, `myContributionsGeneration`, `lastSubmissionAt` local, `submit` qui propage |
| `Core/Community/SupabaseContributionFunctions.swift` | décode le corps d'erreur en `ContributionSubmissionError` |
| `supabase/functions/_shared/auth.ts` | `HttpError` gagne `code` et `retryAfter` ; `serveJSON` les sérialise |
| `supabase/functions/submit-contribution/index.ts` | pose les cinq codes |
| `Resources/Localizable.xcstrings` | les chaînes, cinq langues |
| `Features/Community/ContributionSubmissionSheet.swift` | **supprimé** |

La génération `myContributionsGeneration` suit la règle du moteur : les
collections de la carte s'invalident par un compteur, jamais par une comparaison
de tableaux, parce que `Contribution` peut changer de contenu sans changer de
composition.

## Erreurs et états dégradés

| Situation | Comportement |
|---|---|
| 429 cooldown | Bandeau « Encore *n* s avant la prochaine proposition », 「Envoyer」désarmé, décompte vivant |
| 409 doublon (< 0,02 normalisé, même catégorie, parmi les approuvées) | Bandeau « Un lieu de cette catégorie existe déjà tout près » ;「Déplacer」rend la main à la carte ; changer de catégorie lève aussi le refus |
| 400 vocabulaire | Bandeau « Ce nom ne passe pas. Reformulez-le », focus rendu au champ |
| 401 jeton expiré | Bandeau « Reconnectez-vous pour proposer un lieu », bouton vers le Profil |
| 503 coupe-circuit | Bandeau « Les propositions sont suspendues pour le moment » ;「Annuler」seul |
| 500 / réseau / corps illisible | Bandeau « L'envoi a échoué » ;「Renvoyer」 |
| Déconnecté au départ | Inchangé — `SignInToContributeAlert`, on n'entre pas en placement |
| `ServerFeaturesModel` faux, ou coupe-circuit fermé | Inchangé — le bouton d'appui long n'apparaît pas |
| Sur la carte V | Ni bouton, ni épingle fantôme, ni épingle en attente |
| Hors ligne | L'envoi tombe sur `.failed` et le panneau garde la saisie ;「Renvoyer」marche quand le réseau revient |
| `fetchMine` échoue | Aucune épingle en attente ne s'affiche ; le reste du chemin fonctionne. Échec silencieux, même parti que `loadMyVotes` |
| Proposition rejetée | Disparaît de la carte, reste dans « Mes propositions » avec son statut |

## Tests

**Neufs, en logique pure :**

- `ContributionPlacementTests` — un refus conserve titre et catégorie ; un 429
  arme l'échéance et désarme l'envoi, son expiration le réarme ; déplacer efface
  un 409 ; changer de catégorie efface un 409 ; le titre est élagué et la borne
  1-280 conditionne l'envoi ; un titre d'espaces seuls n'est pas envoyable ; un
  succès passe en `confirmed`.
- `ContributionSubmissionErrorTests` — chaque `code` tombe sur le bon cas ; un
  corps inconnu ou absent retombe sur `.failed` ; un 429 sans `retryAfter`
  retombe sur 60 s ; `invalid` tombe sur `.failed` et non sur `.titleRejected`.

**Étendus :**

- `CommunityFakesTests` — `submit` **propage** au lieu d'avaler ;
  `myUnpublishedSpots` exclut les rejetées et inclut une approuvée absente du
  fragment ; `myContributionsGeneration` avance à chaque rechargement.
- `contribution.test.ts` (Deno) — les codes rendus par `submit-contribution`,
  et la sérialisation de `HttpError` avec et sans `code`.

**Vérification à l'écran**, parce que rien de tout cela ne se teste autrement :
que le `require(toFail:)` ne fasse pas accrocher le panoramique au démarrage du
glissement ; qu'en placement, taper un POI ne l'ouvre pas ; que le recentrage
sorte bien l'épingle de sous le panneau ; le panneau au bord *trailing* sur iPad ;
les trois états ; la carte V qui ne montre rien.

**Ne doivent pas régresser** : `ContributionSectionsTests`, `ContributionTests`,
`LocalizationCoverageTests`, `SmokeTests`, `privileges_test.sql`, et surtout
`MapContentTokenTests` — `ContentToken` gagne un champ, et cette suite est
précisément celle qui garde le contrat d'invalidation du moteur.

## Livraison

Deux plans.

| Plan | Contenu | Utile seul ? |
|---|---|---|
| **A** | Les codes serveur, l'erreur typée, la machine à états, le panneau et ses trois états, le geste de placement | Oui — ferme le no-op silencieux, qui est le défaut grave |
| **B** | L'épingle en attente sur la carte : `myUnpublishedSpots`, la famille d'annotations, le popover | Suppose A |

## Ce qui n'est pas fait ici

- **Aucun champ libre de plus.** Pas de description, pas de photo. La règle de
  dosage de la spec Social — « aucun texte libre nulle part » au-delà du
  strictement nécessaire — tient : chaque champ libre est une surface de
  modération, et un titre en est déjà une.
- **Aucun changement au calcul de l'XP** ni à la modération.
- **Pas de brouillon persistant.** Quitter le placement perd la saisie. Un
  brouillon supposerait de la stocker, de la resituer et de l'expirer, pour un
  geste qui dure trente secondes.
- **Pas de retour de modération poussé** (notification quand une proposition est
  approuvée ou rejetée). Le Profil porte les statuts ; une notification demande
  une file APNs et un déclencheur, donc son propre chantier.
- **`ContributionAnnotationView` ne bouge pas** : le popover d'une proposition
  publiée a été refait la veille et n'a rien à voir avec ce chemin.
