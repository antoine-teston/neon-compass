# Section Codes — quatre modes de saisie et bascule entre les deux jeux

**Date** : 2026-07-29
**Statut** : validé, prêt pour le plan d'implémentation
**Remplace** : la partie « modèle de séquence » de `2026-07-22-plan-3b-cheats.md`

## Le problème

L'écran Codes existe (`Features/Cheats/`, plan 3b) mais n'affiche rien, et son
modèle ne peut pas représenter la donnée réelle de GTA V.

Deux causes, indépendantes :

1. **Un bug de décodage.** `cheat.schema.json` autorise les boutons `lb`, `lt`,
   `rb`, `rt` ; l'énumération Swift `GamepadButton` ne les a pas. Le seul cheat
   du dépôt, `cheat_sample_placeholder.json`, utilise `"xbox": ["up","up","b","lb"]`
   — `GamepadButton(rawValue: "lb")` rend `nil`, `Cheat.init(from:)` lève, le
   fichier est rejeté. L'écran est vide parce que la donnée ne décode pas, pas
   parce qu'il n'y a pas de contenu.

   Le plan 3b avait vu le décalage et l'avait consigné comme une fixture de
   contenu à corriger « avant toute publication réelle », hors de son périmètre.
   Son test unitaire écrit donc `"l1"` là où le contenu réel écrit `"lb"` : le
   test passe, le contenu échoue, et rien ne relie les deux. C'est ce chaînon
   manquant que la nouvelle suite ajoute, en décodant les fichiers livrés plutôt
   qu'un JSON écrit à la main.

2. **Un modèle trop étroit.** `sequence` exige `ps5` **et** `xbox`. GTA V a
   quatre modes de saisie, et cinq de ses 36 triches n'ont aucun combo manette.
   Ces triches sont inexprimables aujourd'hui.

## La donnée réelle

Extraite de `gta.fandom.com` via `api.php` (mode `api` du registre de sources,
spec §7), page *Cheats in GTA V*, `action=parse&prop=wikitext`. Les quatre
sections de la page donnent quatre modes :

| Mode | Codes (source primaire) | Après recoupement | Forme |
|---|---|---|---|
| Manette Xbox (360 / One / Series) | 29 | **31** | séquence de boutons |
| Manette PlayStation (3 / 4 / 5) | 28 | **31** | séquence de boutons |
| Clavier PC (console de triche) | 34 | **35** | mot-clé — `COMET` |
| Téléphone in-game | 36 | **36** | numéro + mnémonique — `1-999-266-38` / `1-999-COMET` |

**36 triches canoniques**, dont 14 apparitions de véhicules (39 %). Le
recoupement de D10 a apporté six codes que la source primaire n'avait pas.

### Le libellé n'est pas une clé de jointure

Une jointure naïve sur le libellé d'effet donne 55 entrées au lieu de 36 : la
même triche est nommée différemment d'une section à l'autre de la source —
« Fast Running » / « Fast Run », « Slidey Cars » / « Slippery Car Tires » /
« Slippery Cars », « Invincibility (Lasts only 5 minutes) » / « Invincibility ».
Chaque triche reçoit donc un identifiant canonique curé, et chaque libellé
source est mappé vers lui. La table d'alias est du contenu, pas de la
déduplication automatique : aucune heuristique de similarité ne distingue
« Slow Motion » de « Slow Motion Aim », qui sont deux triches distinctes.

Le vocabulaire de boutons de la source demande aussi une normalisation :
`D-Pad Left` et `D-Pad left` coexistent, et `X` désigne le bouton X sur Xbox
mais la croix sur PlayStation — désambiguïsé par la section d'origine, jamais
par le token seul.

### Couverture par mode

État après le recoupement de D10 :

| ps | xbox | pc | tél | triches |
|---|---|---|---|---|
| ✓ | ✓ | ✓ | ✓ | 31 |
| | | ✓ | ✓ | 4 — Dodo, Duke O'Death, Kraken, mode Réalisateur |
| | | | ✓ | 1 — téléphone noir |

Le téléphone couvre les 36 triches, la manette 31. **Cinq codes restent
invisibles à un joueur manette** : c'est le cas que l'UI doit traiter, et il
n'est pas marginal — deux d'entre eux sont des véhicules qu'on cherche par leur
nom.

Aucun conflit de valeur entre les quatre sections de la source primaire (vérifié :
0 divergence sur les codes qu'elles partagent), ce qui la rend fiable pour cet
usage.

## Source : pourquoi pas Red Bull

La demande initiale visait `redbull.com/fr-fr/gta-5-codes-triche`. Son
`robots.txt` autorise ce chemin pour `User-agent: *`, mais son pare-feu Akamai
renvoie **403 dès que l'agent utilisateur contient « ClaudeBot »**, tout en
répondant 200 à un UA neutre. C'est un refus explicite de l'éditeur, posé au
niveau réseau plutôt que dans `robots.txt` ; le contourner par un autre UA est
exactement la zone grise que `tools/content-cli/source-policy.mjs` existe pour
fermer.

Les combos de boutons, mots-clés et numéros sont des faits identiques partout.
Fandom, déjà au registre, les fournit intégralement. Red Bull n'apporte rien
que Fandom n'ait, et le registre reste inchangé.

## Décisions

### D1 — `codes` : dictionnaire de modes à charge typée

`sequence` est remplacé par `codes`, dictionnaire dont les clés sont les modes
et les valeurs une union étiquetée :

```jsonc
"codes": {
  "playstation": { "kind": "buttons", "buttons": ["circle","r1","l2"] },
  "xbox":        { "kind": "buttons", "buttons": ["b","rb","lt"] },
  "pc":          { "kind": "keyword", "keyword": "COMET" },
  "phone":       { "kind": "phone", "number": "1-999-266-38", "mnemonic": "1-999-COMET" }
}
```

Côté Swift :

```swift
enum CheatInputMode: String, CaseIterable, Codable, Sendable {
    case playstation, xbox, pc, phone
}

enum CheatCode: Equatable, Sendable {
    case buttons([GamepadButton])
    case keyword(String)
    case phone(number: String, mnemonic: String?)
}
```

Toutes les entrées sont optionnelles ; `codes` doit en contenir au moins une.

Les alternatives écartées : des champs optionnels à plat (`pcKeyword`,
`phoneNumber`…) recopient la liste des modes dans quatre endroits et dispersent
« quels modes ce code supporte-t-il » en `nil`-checks dans les vues ; un tableau
d'entrées `[{"mode":…}]` impose une recherche linéaire, autorise les doublons,
et sa charge redevient une union à champs tous optionnels. Toute l'UX repose sur
deux faits — un mode se rend différemment, un code peut ne pas exister — et le
dictionnaire à charge typée est la seule forme où les deux sont de premier ordre.
`Cheat.swift` écrit déjà son `Codable` à la main (le `Dictionary` synthétisé
cassait le round-trip du cache SwiftData) : le coût reste dans ce fichier.

### D2 — `game` sur chaque triche, et dans son identifiant

Champ requis `game`, valeurs `"gtav"` et `"leonida"`. Pour que l'app n'ait qu'un
seul vocabulaire de jeu, l'énumération `NewsGame` est extraite en `Core/Game.swift`
sous le nom `Game`, avec `typealias NewsGame = Game` afin que les sites d'appel du
fil continuent de compiler.

L'identifiant porte le jeu : `cheat_gtav_invincibility`, pas
`cheat_invincibility`. Les deux jeux auront des triches homonymes —
invincibilité, munitions, météo — et un identifiant sans le jeu les ferait
collisionner le jour où les codes de GTA VI arrivent.

### D9 — Les 36 codes sont embarqués dans le binaire

`ContentStore<Cheat>.live` est appelé sans `seed:` sur ses deux sites
(`CheatsScreen.swift:49`, `RootView.swift:154`), alors que les POI et les
collections passent le leur. Conséquence : au premier lancement et hors ligne,
l'écran Codes reste vide même une fois le bug de décodage corrigé — le contenu
n'arrive que par le CDN ou Firestore.

Un socle embarqué `Resources/Cheats/seed-cheats.json` est donc généré depuis
`content/` sur le modèle de `seed-poi.json` : même projection, même garde-fou
`check-seeds`, même référence de dossier `type: folder` dans `project.yml`
(sans quoi XcodeGen aplatit le fichier et le `subdirectory:` du chargeur ne le
trouve pas). C'est justifié au-delà du parallélisme : les codes d'un jeu terminé
ne changent plus, et D5 — la saisie immédiate — ne tient pas si l'écran dépend
du réseau.

Le socle embarque indépendamment du statut `draft`/`published`, par la règle
déjà en place pour les POI (ce filtre gouverne la publication Firestore, pas ce
que le binaire contient). La relecture humaine des 36 textes d'effet est donc
une étape du plan, pas un filtre à l'exécution.

### D3 — Deux sélecteurs, de poids différents

Le jeu et le mode de saisie ne sont pas de même nature :

- **Jeu** — changement de contexte, tout le contenu change. Contrôle compact
  `V | VI` dans la toolbar, reprenant le vocabulaire `shortLabel` du fil d'actu.
- **Mode de saisie** — loupe sur le même contenu. Segmenté à 4 icônes sous la
  recherche, choix mémorisé entre les lancements.

`CheatsScreen.swift` porte une remarque selon laquelle un `Picker` segmenté
« n'était pas la bonne UX » : elle visait l'arbitrage Codes vs Guides, deux
types de contenu, donc un problème de navigation. Une loupe sur une seule liste
est un autre problème — un tap, aucun état caché.

### D4 — Les codes absents du mode actif restent visibles

Les cinq triches sans combo manette ne sont pas masquées quand une manette est
sélectionnée : un groupe replié en bas de liste — « 5 codes passent par un autre
mode de saisie » — bascule le mode au tap. Les masquer ferait croire qu'elles
n'existent pas ; les griser en ligne polluerait le scan rapide, qui est la
priorité de l'écran. Le compte est un paramètre de la chaîne localisée, pas une
constante : il suivra l'arrivée des codes de GTA VI sans retouche.

### D5 — Priorité à la saisie immédiate

L'utilisateur joue, manette ou clavier en main, et veut entrer un code
maintenant. En conséquence : sections par catégorie plutôt qu'une liste plate de
36, favoris en tête, recherche conservée, **bouton copier pour les modes PC et
téléphone** (rien à copier pour une manette), et lecteur plein écran conservé —
glyphes énormes, écran maintenu allumé — étendu au mot-clé et au numéro.

### D6 — `blocksTrophies` s'inverse en réassurance

La source établit qu'aucune triche de GTA V n'empêche le 100 % : le badge
d'avertissement magenta de `CheatCard` ne se déclencherait jamais. Le champ est
conservé (GTA VI pourra différer) mais l'information utile pour GTA V est une
réassurance, affichée **une fois** en pied d'écran et non 36 fois sur les
cartes, avec le fait qu'un code ne se mémorise pas dans le téléphone et doit
être resaisi quand son effet expire.

### D7 — Noms de véhicules conservés, effets réécrits

Comet, Kraken, Duke O'Death sont des identifiants factuels : sans eux le code
ne sert à rien. Ce qui est réécrit dans nos mots, c'est la **description de
l'effet**. Rédaction EN + FR — contrat de l'agent `content-editor`. La bascule
FR-primaire n'est pas touchée : le schéma exige toujours `en`, elle reste un
plan dédié.

### D10 — Deux sources, donc publiable

`check-publishable` refuse déjà un cheat `published` dont `verifiedBy` compte
moins de deux sources. Or le socle de D9 embarque le contenu indépendamment de
son statut : livrer 36 codes mono-sourcés en `draft` ferait entrer dans le
binaire exactement ce que la porte de publication refuse.

Les codes sont donc recoupés sur une seconde source autorisée — `gtaboom.com`,
mode `allow` au registre — puis publiés. Un code sur lequel les deux sources
divergent n'est pas publié : un combo faux est pire qu'un combo absent, il fait
échouer la saisie sans dire pourquoi. Un code que la seconde source ignore
reste en `draft` avec une seule source, et c'est dit.

### D8 — Corrections ciblées incluses

- `GamepadButton` gagne `lb`, `lt`, `rb`, `rt` (déjà au schéma, absents du
  modèle) — c'est le bug de décodage ci-dessus.
- `Platform.ps5` devient `CheatInputMode.playstation` : la source confirme des
  combos identiques de PS3 à PS5, l'étiquette « PS5 » est fausse. La clé
  `UserDefaults` `cheatsActivePlatform` doit être migrée, pas simplement
  renommée — une valeur stockée `"ps5"` doit continuer à se lire.

## Hors périmètre, assumé

- **Notification de sortie GTA VI.** L'état d'attente est informatif
  (explication + date du 19 novembre 2026), sans bouton de notification :
  `FollowedCategoryNotifying` est câblé sur `POICategory` (topic
  `spots-<catégorie>`) et le généraliser est un autre chantier.
- **es / it / de** — suivent la passe de localisation.
- **Codes GTA VI** — aucun n'existe avant la sortie. Aucun placeholder
  spéculatif : ce serait de la supposition présentée comme du fait, contraire à
  la ligne tenue par le fil d'actu.

## Résultat du recoupement

Fait le 2026-07-29, jetons normalisés des deux côtés, consigné dans
`tools/content-cli/gtav-cheats-corroboration.json` :

- **126 codes en accord**, sur les 127 que les deux sources décrivent tous deux.
- **1 désaccord**, tranché par la donnée : la seconde source donne
  `1-999-547-861` pour le mode ivre, la première `1-999-547-867`. Les deux citent
  le mnémonique `1-999-LIQUOR`, qui s'encode 547867 sur un clavier téléphonique
  (`R` = 7, et le 1 ne porte aucune lettre). La première source a raison.
- **6 codes apportés par la seconde source** : le combo PlayStation de la visée
  au ralenti — la lacune anticipée —, les deux combos manette de la nage rapide
  et du BMX, et le mot-clé PC du mode Réalisateur.
- **0 code que la seconde source ignore.**
- Une coquille de forme corrigée : la source primaire écrit une fois
  `(1-999 HOT-HANDS)` avec une espace là où toutes ses autres entrées mettent un
  tiret. La seconde confirme `1-999-HOT-HANDS`. Le parseur ramène les espaces à
  des tirets plutôt que de les effacer, ce qui aurait produit `1-999HOT-HANDS`.

Les 36 triches portent donc deux sources et le statut `published`.

## Tests

- Décodage : une triche à quatre modes, une à téléphone seul, une avec `codes`
  vide (doit être rejetée), un bouton inconnu (doit être rejeté).
- Round-trip encode/decode, qui est ce que le cache SwiftData de
  `ContentStore<Cheat>` exerce réellement.
- Migration de `cheatsActivePlatform` : valeur stockée `"ps5"` → `playstation`.
- Filtrage : le partitionnement entre triches disponibles dans le mode actif et
  triches à reléguer dans le groupe replié.
- Validation de contenu : les 36 fichiers passent le schéma, et chaque
  identifiant canonique est unique.
