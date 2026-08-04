# Le Profil connecté — deux jauges, et des réglages qui se rangent

**Date** : 2026-08-04
**Statut** : validé, prêt pour le plan d'implémentation
**Prolonge** : `2026-07-31-profil-complet-design.md`, qui a versé les Défis dans le
Profil et sorti les réglages en feuille. Ce chantier-ci reprend l'entête et la
feuille, que le précédent avait déplacées sans les retravailler.

## Le problème

### L'entête connectée promet un niveau et n'en donne aucun

`ProfileHeaderView` affiche, connecté : le pseudo, le badge Pro, `Niveau 3` ←→
`450 XP`, « 3 en attente », « 342ᵉ ». Trois écarts avec ce qui était décidé.

- La spec du 31 juillet annonçait une « barre d'XP vers le niveau suivant »
  (§ *La page Profil*). Elle n'existe pas.
- La spec fondatrice annonçait des « grades à thème synthwave **originaux** », et
  la migration Supabase le confirme noir sur blanc — `20260802120000_initial_schema.sql:22`
  : « Les noms de grades restent côté client : c'est de l'affichage localisé, pas
  une règle métier. » Il n'y a aucun nom de grade côté client. Juste `Niveau %d`.
- Connecté avec `ServerFeaturesModel.isEnabled` à faux, l'entête affiche
  **« Ton profil »** — le titre anonyme — *et* « Niveau 0 / 0 XP » juste dessous.
  Elle se dit anonyme et chiffrée dans le même bloc. Constaté au simulateur le
  2026-08-04. La cause est `ProfileScreen.swift:27`, qui fond deux questions
  distinctes en un seul booléen :
  `isSignedIn: authModel.userID != nil && serverFeatures.isEnabled`, alors que le
  bloc chiffré du dessous est gouverné par un `if let profile` indépendant.

### Et ce niveau serait mort pour presque tout le monde

L'XP ne s'obtient que de deux façons : **+20 par contribution approuvée**
(`20260802170000_contribution_xp.sql:18`) et **+2 par vote reçu**
(`20260802120000_initial_schema.sql:285`). Le premier palier est à 50 XP.

Quelqu'un qui installe l'app, se connecte, coche deux cents lieux et débloque des
trophées reste à **« Niveau 0 · 0 XP »** pour toujours — et c'est le bloc le plus
visible de sa page Profil. Le niveau ne récompense que le contributeur, qui sera
une infime minorité. Habiller ce zéro ne l'aurait pas rendu vivant.

### La feuille de réglages n'a aucune hiérarchie

`SettingsScreen.swift` est un `VStack(alignment: .leading, spacing: 24)` où tout
est au même niveau : le badge Pro, un `Picker` segmenté, des `Toggle`, et trois
boutons nus dont « Supprimer mon compte ». Aucun regroupement, aucun titre de
section. Connecté, trois défauts précis :

- On ne voit **nulle part avec quel compte** on est connecté. Ni le fournisseur,
  ni l'adresse. `AuthProviding` n'expose que `currentUserID`.
- Les contributeurs masqués s'affichent en **UUID brut** (`SettingsScreen.swift:300`,
  `Text(authorUid)`) — illisible, donc indébloquable de façon fiable.
- « Régénérer le pseudo » change l'identité publique **sans confirmation**.

## Ce qu'on construit

### L'entête : deux jauges, pas une

```
╭──────────────────────────────────────────╮
│  NEON-FALCON-88                  PRO  ⚙  │
│                                          │
│  ÉCLAIREUR                               │
│  ━━━━━━━━━━━━━━━╸────────────   87 lieux │
│  13 avant « Cartographe »                │
│  ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈  │
│  ◈ BALISE · 210 XP · 342ᵉ · 3 en attente │
╰──────────────────────────────────────────╯
```

**La jauge haute est locale.** Elle compte `FoundStore.foundIDs.count` — les POI
cochés, tous jeux confondus. Elle vit dès le premier lieu coché, hors ligne, sans
compte, sans serveur. C'est elle qui porte le mot « niveau » au sens où un joueur
l'entend.

**La ligne basse est serveur.** Grade contributeur, XP, rang, contributions en
attente. Elle n'existe que si `ProfileModel.profile` est non nil.

**Pourquoi la jauge haute ne double pas les anneaux du dessous.** Les anneaux de
`ProgressionListView` sont *par jeu* et en *pourcentage d'une collection connue*.
La jauge d'entête est *globale* et en *nombre absolu*. Deux questions
différentes : « où j'en suis dans les Tracts Epsilon » contre « combien j'ai vu
de Leonida ». Et surtout, le nombre absolu reste juste quand
`ChallengeProgress.expected` vaut `nil` — ce que le pourcentage ne peut pas, et
c'est exactement pourquoi `ProgressionListView.swift:29-32` refuse déjà de
tracer un anneau dans ce cas.

**Ce qui n'est pas compté** : les trophées. Le libellé dit « lieux », il compte
des lieux. Les trophées gardent leur carte propre, plus bas.

### Les grades

Six paliers de chaque côté, pour qu'ils se lisent comme des sœurs. Vocabulaires
volontairement disjoints — **route et mouvement** pour l'exploration, **signal et
lumière** pour la contribution : on ne doit jamais hésiter sur laquelle des deux
on est en train de lire.

**Explorateur** — paliers sur le nombre de lieux cochés. Calibrés sur les 537 POI
du socle `seed-poi.json` actuel, et choisis pour rester parlants quand le contenu
VI s'ajoutera : au dernier palier on a vu l'équivalent de la carte de référence
entière.

| Lieux | `en` (base) | `fr` | `es` | `it` | `de` |
|---|---|---|---|---|---|
| 0 | Drifter | Vagabond | Errante | Vagabondo | Streuner |
| 10 | Scout | Repéreur | Explorador | Battistrada | Späher |
| 40 | Pathfinder | Éclaireur | Rastreador | Esploratore | Pfadfinder |
| 100 | Cartographer | Cartographe | Cartógrafo | Cartografo | Kartograf |
| 250 | Trailblazer | Défricheur | Pionero | Pioniere | Wegbereiter |
| 500 | Neon Nomad | Nomade Néon | Nómada Neón | Nomade Neon | Neon-Nomade |

**Contributeur** — les paliers ne sont **pas** redéfinis ici. `Profile.level`
arrive déjà calculé par la colonne générée (`initial_schema.sql:24-33`). Le
client ne fait que nommer un entier qu'il reçoit.

| Niveau | XP (pour mémoire, côté base) | `en` (base) | `fr` | `es` | `it` | `de` |
|---|---|---|---|---|---|---|
| 1 | 50 | Spotter | Guetteur | Vigía | Vedetta | Beobachter |
| 2 | 150 | Beacon | Balise | Baliza | Segnale | Bake |
| 3 | 400 | Relay | Relais | Repetidor | Ripetitore | Relais |
| 4 | 900 | Lighthouse | Phare | Faro | Faro | Leuchtturm |
| 5 | 2000 | Grid Keeper | Gardien du réseau | Guardián de la red | Custode della rete | Netzwächter |

Le niveau 0 **n'a pas de nom** : c'est l'état d'invitation, décrit plus bas.

Conformité IP : aucun de ces mots n'est une marque, aucun ne reprend un rang de
la série. C'est du vocabulaire de cartographie et de signalisation — le sujet
même de l'app.

**Une barre d'un seul côté, délibérément.** La progression vers le palier suivant
n'est tracée que pour l'explorateur. La tracer côté contributeur exigerait de
dupliquer les seuils XP dans le client — la duplication même que la migration a
supprimée (`20260802170000_contribution_xp.sql:9-11` : « il n'y a plus qu'un seul
endroit où écrire l'XP, et zéro endroit où recalculer le niveau »). Une ligne de
texte suffit, et elle ne peut pas dériver de la base.

### Les états de l'entête

| État | Ce qu'affiche l'entête |
|---|---|
| Connecté, profil chargé, XP > 0 | Pseudo · jauge explorateur · ligne contributeur complète |
| Connecté, profil chargé, XP = 0 | Pseudo · jauge explorateur · **invitation à contribuer** |
| Connecté, chargement du profil en cours | Titre en gabarit `.redacted` · jauge explorateur · pas de ligne contributeur |
| Connecté, `serverFeatures` faux **ou** profil illisible | « Ton profil » · jauge explorateur seule. **La ligne contributeur disparaît entièrement** |
| Non connecté | « Ton profil » · jauge explorateur seule · l'invitation de connexion reste en pied de page, inchangée |

L'avant-dernière ligne est le correctif de l'incohérence relevée plus haut. La
règle devient, sans exception : **tout ce qui est chiffré suit `profile != nil`,
et rien d'autre.**

**Une seule question, un seul booléen.** L'entête ne reçoit *pas* de
`isSignedIn`. Ce serait reconduire la faute d'origine — deux conditions pour une
même question — et ce serait redondant : le profil n'est chargé que connecté,
donc `contributor != nil` implique déjà « connecté », et les deux états
« déconnecté » et « serveur coupé » rendent délibérément la même chose. Le seul
paramètre qui apporte une information que `profile` ne porte pas est **« un
chargement est-il en cours »** : sans lui, un utilisateur connecté verrait
« Ton profil » clignoter le temps de l'aller-retour réseau avant que son pseudo
n'apparaisse. `ProfileModel` gagne donc un `private(set) var isLoadingProfile`,
posé autour du `fetchProfile` — trois lignes, et la distinction « pas encore
connu » / « pas disponible » devient dicible.

### L'invitation à contribuer

À 0 XP, la ligne basse devient tapable :

> ⊕ **Propose un lieu pour ouvrir ton rang** · +20 XP à l'approbation ›

Un tap ouvre une feuille courte qui **dit le geste** — « Sur la carte, appuie
longuement à l'endroit du lieu » — et porte un bouton « Ouvrir la carte » qui
pose `appModel.selectedTab = .map`.

La feuille n'est pas un ornement : une contribution **se pose sur la carte**.
`ContributionSubmissionSheet` exige une `position`, et le seul chemin est l'appui
long (`MapScreen.swift:233-242`). Basculer directement sur la carte laisserait
l'utilisateur devant un écran sans indice.

C'est aujourd'hui **le seul endroit de l'app qui explique comment l'XP se
gagne**. Sans lui, ni le rang ni le classement de l'onglet Social ne sont
atteignables autrement que par accident.

### La feuille de réglages

Un `Form` natif sur fond `nightSky` (`.scrollContentBackground(.hidden)`), qui
apporte gratuitement Liquid Glass, Dynamic Type, les tailles de frappe et les
affordances VoiceOver — conforme à CLAUDE.md, « Liquid Glass pour tout le chrome
[…] le synthwave rétro vit dans la couche de contenu uniquement ».

```
── COMPTE ────────────────────────────────
   Connecté avec Apple
   antoine@exemple.fr
   Pseudo                    NEON-FALCON-88
   Changer de pseudo                      ›

── NEON COMPASS PRO ──────────────────────
   ✓ Pro actif
   Ce que Pro apporte                     ›

── APPARENCE ─────────────────────────────      (Pro)
   Thème   [ Magenta | Cyan | Coucher ]
   Icône néon                          ●──      (si supportée)

── NOTIFICATIONS ─────────────────────────      (Pro + serveur)
   Points de repère                    ──●
   Objets à collecter                  ●──
   …

── COMMUNAUTÉ ────────────────────────────      (serveur)
   NEON-RAVEN-12               Réafficher
   Contributeur 3F2A…          Réafficher

──────────────────────────────────────────
   Se déconnecter
   Supprimer mon compte                   ⚠
```

Quatre changements de fond au-delà du regroupement.

**L'identité du compte s'affiche.** Fournisseur et adresse, lus de la session.
`AuthProviding` gagne `currentAccount`. Les adresses relais Apple
(`@privaterelay.appleid.com`) s'affichent telles quelles : c'est bien l'adresse
du compte, et la masquer viderait la ligne de ce qui la rend utile.

**Le destructeur est isolé.** « Se déconnecter » et « Supprimer mon compte » vont
dans une dernière section sans titre, séparés du reste. Leur confirmation ne
change pas.

**Changer de pseudo se confirme.** L'Edge Function `regenerate-handle` ne met à
jour que `profiles.handle` ; `contributions.author_handle` est une colonne
dénormalisée écrite à la soumission (`initial_schema.sql:84`). **Les
contributions déjà publiées gardent l'ancien pseudo** — l'alerte le dit, sinon la
surprise arrive plus tard et sans explication possible.

**Les contributeurs masqués portent un nom.** `onBlockAuthor` reçoit déjà le
`spot` entier (`MapScreen.swift:251-253`), donc `spot.authorHandle` est
disponible au moment du blocage. Il est enregistré. Le client ne peut de toute
façon pas le retrouver plus tard : la politique RLS est
`using (auth.uid() = uid)` (`20260802120100_rls_policies.sql:65-67`) — on ne lit
que sa propre ligne de `profiles`.

**Deux décisions qui suppriment du code plutôt que d'en ajouter :**

- **L'icône alternative se conditionne à `UIApplication.shared.supportsAlternateIcons`.**
  `SettingsScreen.swift:281-286` documente que `AppIcon-Neon` n'existe pas encore
  et que la bascule *no-op en silence* ; aucun `CFBundleAlternateIcons` n'est
  déclaré dans `project.yml`. Dans un `Form`, un `Toggle` qui revient tout seul
  est pire qu'ailleurs. La ligne disparaît, et réapparaîtra d'elle-même le jour
  où l'asset est livré.
- **La section Pro ne réénumère pas les avantages.** `PaywallView.swift:27-36`
  les liste déjà. Les redire créerait deux listes qui divergeraient. La section
  dit l'état, et une ligne rouvre le paywall.

## Architecture

### Nouveaux types purs, dans `Core/`

Aucun n'a d'I/O ; tous sont testables sans simulateur.

**`Core/Progression/ExplorerGrade.swift`**

```swift
enum ExplorerGrade: Int, CaseIterable, Sendable {
    case drifter, scout, pathfinder, cartographer, trailblazer, neonNomad

    var threshold: Int              // 0, 10, 40, 100, 250, 500
    var nameKey: String             // "profile.explorerGrade.drifter", …
    static func forFound(_ count: Int) -> ExplorerGrade
    var next: ExplorerGrade?        // nil au dernier palier
    func progress(found: Int) -> Double?      // nil au dernier palier
    func remainingToNext(found: Int) -> Int?  // nil au dernier palier
}
```

**`Core/Auth/ContributorGrade.swift`**

```swift
enum ContributorGrade: Int, CaseIterable, Sendable {
    case spotter = 1, beacon, relay, lighthouse, gridKeeper

    var nameKey: String
    /// nil au niveau 0 — c'est l'état d'invitation, pas un grade. nil aussi
    /// pour tout entier hors 1…5 : la base peut gagner un palier avant l'app.
    static func named(level: Int) -> ContributorGrade?
}
```

Pas de seuils. La base les possède, et elle est seule à les posséder.

**`Core/Auth/SignedInAccount.swift`**

```swift
struct SignedInAccount: Equatable, Sendable {
    enum Provider: Equatable, Sendable { case apple, google, email, other(String) }
    let provider: Provider
    let email: String?
}
```

`AuthProviding` gagne `var currentAccount: SignedInAccount? { get }`.
`SupabaseAuthProvider` le construit depuis `client.auth.currentUser` :
`identities?.first?.provider` (repli sur `appMetadata["provider"]`) et `email`.
Les deux existent dans `supabase-swift` (`Sources/Auth/Types.swift:182`, `:209`,
`:333`).

### L'entête devient un état pur plus une vue bête

**`Features/Profile/ProfileHeaderState.swift`** — toute la dérivation, sans
SwiftUI :

```swift
struct ProfileHeaderState: Equatable {
    enum Contributor: Equatable {
        case invitation                                  // niveau 0
        case ranked(gradeNameKey: String?, xp: Int, rank: Int?, pending: Int)
    }

    enum Title: Equatable {
        case handle(String)   // profil connu
        case placeholder      // chargement en cours → rendu `.redacted`
        case neutral          // « Ton profil »
    }

    let title: Title
    let isProEntitled: Bool
    let explorerGrade: ExplorerGrade
    let foundCount: Int
    let explorerProgress: Double?
    let remainingToNext: Int?
    let nextGradeNameKey: String?
    let contributor: Contributor?  // nil quand profile == nil

    init(profile: Profile?, isLoadingProfile: Bool, isProEntitled: Bool,
         foundCount: Int, pendingContributionCount: Int)
}
```

C'est là que vit la règle « tout ce qui est chiffré suit `profile != nil` », et
c'est ce qui la rend testable — le défaut d'aujourd'hui est né d'une condition
répartie entre deux fichiers, dont aucun test ne pouvait voir la combinaison.

`ProfileScreen.swift:27` perd du même coup sa garde `&& serverFeatures.isEnabled`
et le commentaire qui l'explique : elle existait pour éviter un pseudo bloqué sur
« … » quand le serveur ne répond pas, et ce cas se règle maintenant par la
construction de l'état.

`ProfileHeaderView` ne fait plus que rendre cet état, plus deux fermetures
(`onOpenSettings`, `onContribute`). Elle passe de cinq paramètres hétérogènes à
un état et deux actions.

`ProfileScreen` construit l'état. Il lit `FoundStore` par l'environnement —
`ProgressionSection` le fait déjà (`ProgressionSection.swift:19`), donc aucune
nouvelle dépendance n'entre dans l'écran.

### La feuille éclate en cinq

| Fichier | Contenu |
|---|---|
| `Features/Settings/SettingsScreen.swift` | Le `Form`, les feuilles, les alertes |
| `Features/Settings/SettingsAccountSection.swift` | Identité, pseudo, connexion, déconnexion, suppression |
| `Features/Settings/SettingsAppearanceSection.swift` | Thème, icône |
| `Features/Settings/SettingsNotificationsSection.swift` | Catégories suivies |
| `Features/Settings/SettingsCommunitySection.swift` | Contributeurs masqués |

Les boutons de connexion (Apple, Google, e-mail) et `AppleSignInCoordinator`
**ne changent pas d'une ligne** : ils sont déplacés dans
`SettingsAccountSection`, tels quels. Le protocole cryptographique n'est pas
retouché pendant une refonte de mise en page.

### Une propriété ajoutée à un modèle SwiftData

`BlockedContributor` gagne `var authorHandle: String?`. Optionnelle, donc
migration légère automatique : les lignes existantes valent `nil` et retombent
sur un UID tronqué (« Contributeur 3F2A… »). `CommunityModel.block` prend le
pseudo en second paramètre ; l'unique appelant l'a déjà sous la main.

### Ce qui ne bouge pas

`ProgressionModel`, `ProgressionListView`, `ProgressionSection`, `AuthModel`,
`ThemeStore`, `FollowedCategoriesStore`, `SettingsModel`,
`AppleSignInCoordinator`, `PaywallView`, et tout le chargement de contenu.

`ProfileModel` ne gagne qu'un `private(set) var isLoadingProfile`, posé autour du
`fetchProfile` existant ; sa logique ne change pas. `AuthProviding` et
`SupabaseAuthProvider` ne gagnent que `currentAccount`, en lecture. Le chantier
touche l'entête, la feuille, et quatre types nouveaux — rien d'autre.

## Erreurs et états dégradés

| Situation | Comportement |
|---|---|
| Non connecté | Jauge explorateur entière ; ni ligne contributeur, ni invitation à contribuer. L'invitation de connexion en pied de page ne change pas |
| Connecté, `serverFeatures` faux | Titre neutre, jauge explorateur seule, ligne contributeur absente. Réglages : sections Communauté et Notifications absentes, comme aujourd'hui |
| Connecté, `fetchProfile` échoue | Identique à la ligne précédente. `ProfileModel.loadProfile` avale déjà l'erreur (`try?`) : ce chantier ne change pas ce choix, il rend seulement l'affichage cohérent avec lui |
| 0 lieu coché | `Drifter` / « Vagabond », barre à zéro, « 10 avant Repéreur ». Un vrai départ, pas un vide |
| Au dernier palier explorateur | Le grade s'affiche, la barre et la ligne « N avant … » disparaissent — il n'y a plus de suivant |
| `Profile.level` hors 1…5 | Aucun nom de grade ; l'XP et le rang s'affichent quand même. La base peut gagner un palier avant que l'app le connaisse |
| `Profile.rank` nul | La ligne omet le rang, garde le reste — règle existante, conservée |
| Pseudo bloqué sans handle enregistré | UID tronqué, déblocage fonctionnel |
| Aucune icône alternative déclarée | La ligne n'existe pas |
| Hors ligne | La jauge explorateur est entière (SwiftData) ; la ligne contributeur affiche le dernier profil connu, ou disparaît s'il n'y en a jamais eu |

## Tests

**Nouveaux**, tous en logique pure, sans I/O ni simulateur :

- `ExplorerGradeTests` — les bornes exactes (9 → `drifter`, 10 → `scout`,
  499 → `trailblazer`, 500 → `neonNomad`), `next` nil au sommet, `progress` nil
  au sommet, `remainingToNext` juste au milieu d'un palier, et un compte négatif
  ou nul qui retombe sur `drifter` sans planter.
- `ContributorGradeTests` — 0 → nil, 1…5 → les bons noms, 6 et −1 → nil.
- `ProfileHeaderStateTests` — **le test qui fige le correctif** : `profile == nil`
  ⟹ `contributor == nil`, dans les deux cas de chargement. Plus : les trois
  titres se distinguent (`profile` connu ⟹ `.handle` ; `nil` + chargement ⟹
  `.placeholder` ; `nil` sans chargement ⟹ `.neutral`) ; niveau 0 ⟹
  `.invitation` ; niveau 3 ⟹ `.ranked` avec la clé `relay`.
- `SignedInAccountTests` — la chaîne de fournisseur de Supabase (`apple`,
  `google`, `email`, un inconnu) se range dans le bon cas.
- `LocalizationCoverageTests` couvre automatiquement les onze nouvelles clés de
  grade dans les cinq langues.

**Ne doivent pas régresser** : `ProfileModelTests`, `AuthModelTests`,
`SettingsModelTests`, `FollowedCategoriesStoreTests`, `ProgressionModelTests`,
`ChallengeProgressCalculatorTests`, `TrophyTests`, `AppleSignInCoordinatorTests`,
`SmokeTests`.

**Vérification visuelle.** L'entête et la feuille se regardent au simulateur,
dans les quatre états du tableau ci-dessus. `cliclick` ne peut pas ouvrir la
feuille — un clic dans un `ScrollView` est consommé comme un défilement — donc on
force `showSettings = true` le temps des captures, puis on rétablit et on vérifie
que l'arbre git est propre. Même méthode pour les états dégradés, en forçant
`serverFeatures` et `profile`.

## Ce qui n'est pas fait ici

- **Aucun changement au calcul de l'XP ni aux seuils de niveau.** La base reste
  seule à les détenir.
- **L'exploration ne rapporte pas d'XP.** Décision explicite : l'XP est écrite
  serveur et sert de base au classement public ; la faire dépendre d'un compteur
  local la rendrait falsifiable.
- **L'icône alternative** — l'asset `AppIcon-Neon` reste à produire
  (`docs/ops/2026-07-23-alternate-app-icons.md`).
- **L'écran de connexion lui-même** : les trois boutons sont déplacés, pas
  redessinés. L'état déconnecté n'est pas le sujet de ce chantier.
- **Les badges** annoncés par la spec fondatrice, distincts des grades.
- **Le classement public** : seul le rang personnel est affiché, quand il existe.
