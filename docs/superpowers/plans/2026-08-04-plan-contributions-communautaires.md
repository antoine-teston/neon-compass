# Plan d'implémentation — Les contributions communautaires

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restreindre la soumission de lieux à la carte VI, fermer le no-op silencieux du chemin déconnecté, et donner à Social un volet où l'on parcourt et vote les propositions de la communauté.

**Architecture:** Une colonne `approved_at` posée par trigger traverse le bundle jusqu'à `Contribution`, en chaîne brute parce que tout le décodage de contenu passe par un `JSONDecoder()` nu. Le découpage en deux sections est un type pur, `ContributionSections`, testable sans SwiftUI. `SocialScreen` ne garde que la structure ; le volet vit dans ses propres fichiers.

**Tech Stack:** Swift 6 concurrence stricte, SwiftUI, SwiftData, Swift Testing, XcodeGen, Supabase (Postgres + RLS + Edge Functions Deno).

**Spec:** `docs/superpowers/specs/2026-08-04-contributions-communautaires-design.md`

## Global Constraints

- **Swift 6, concurrence stricte.** SwiftUI seulement. Tests en Swift Testing (`import Testing`).
- **Aucune chaîne en dur.** Toute chaîne visible passe par `NeonCompass/Resources/Localizable.xcstrings`, dans les **cinq** langues `en`, `fr`, `es`, `it`, `de`. `en` est la base.
- **`xcodegen generate` après toute création ou suppression de fichier source**, sinon `xcodebuild` rapporte « 0 tests » au lieu d'un échec de compilation.
- **`xcodebuild test` peut réécrire `Localizable.xcstrings`.** Vérifier `git status` avant chaque commit ; restaurer avec `git checkout -- NeonCompass/Resources/Localizable.xcstrings` plutôt qu'emporter l'artefact.
- **Deux verrous sur chaque objet.** `pg_default_acl` accorde tout à `anon` et `authenticated` sur les objets nouvellement créés : **toute migration qui crée une table ou une fonction porte sa propre révocation.** Le filet est `supabase/tests/privileges_test.sql`.
- **IP** : aucune marque déposée dans une chaîne d'interface.
- Simulateur : `iPhone 17` (iOS 26.5). Tests :
  `xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test`
- **Le décodage de contenu utilise `JSONDecoder()` nu** (`ContentCDN.swift:112,155`), donc `.deferredToDate` : une date ISO 8601 y échoue. Les dates de contenu se modélisent en `String` et se parsent à la main — motif établi par `OnlineEvent.swift:118-140`.

---

## Structure des fichiers

**Plan A — la donnée et la carte**

| Fichier | Changement |
|---|---|
| `supabase/migrations/20260804120000_contribution_approved_at.sql` | **créé** — colonne, rétro-remplissage, trigger, révocation |
| `supabase/tests/schema_test.sql` | assertion sur la colonne et le trigger |
| `supabase/tests/privileges_test.sql` | la fonction du trigger entre dans la liste explicite |
| `supabase/functions/rebuild-community-bundles/index.ts:72,82-93` | `approved_at` au `select` et au mapping |
| `NeonCompass/Core/Community/Contribution.swift` | `var approvedAt: String?` + `approvedAtDate` |
| `NeonCompassTests/Community/ContributionTests.swift` | **créé** |
| `NeonCompass/Features/Community/SignInToContributeAlert.swift` | **créé** — l'alerte partagée |
| `NeonCompass/Features/Map/MapScreen.swift` | garde VI sur le bouton et les épingles, alerte déconnectée |
| `NeonCompass/Features/Community/ContributionAnnotationView.swift` | catégorie ajoutée, votes en lecture |

**Plan B — le volet Social**

| Fichier | Changement |
|---|---|
| `NeonCompass/Core/Community/ContributionSections.swift` | **créé** — le découpage, pur |
| `NeonCompassTests/Community/ContributionSectionsTests.swift` | **créé** |
| `NeonCompass/Core/Community/ContributionRepository.swift` | `fetchMyVotes(uid:)` |
| `NeonCompass/Core/Community/SupabaseContributionRepository.swift` | son implémentation |
| `NeonCompassTests/Community/CommunityFakesTests.swift` | `FakeContributionRepository.votesToReturn` |
| `NeonCompass/Features/Community/CommunityModel.swift` | `myVotes`, `loadMyVotes(uid:)`, `vote` met à jour |
| `NeonCompass/Features/Social/ContributionsPanel.swift` | **créé** |
| `NeonCompass/Features/Social/ContributionRow.swift` | **créé** |
| `NeonCompass/Features/Social/SocialScreen.swift` | sélecteur de volets ; l'existant devient le volet Événements |

---

# PLAN A — la donnée et la carte

Livrable seul : il ferme un bug et une incohérence de données, sans toucher Social.

### Task A1 : la colonne `approved_at`

**Files:**
- Create: `supabase/migrations/20260804120000_contribution_approved_at.sql`
- Modify: `supabase/tests/schema_test.sql`
- Modify: `supabase/tests/privileges_test.sql`

**Interfaces:**
- Produces: la colonne `public.contributions.approved_at timestamptz`, et la fonction `public.stamp_contribution_approval()`.

- [ ] **Step 1 : écrire la migration**

Créer `supabase/migrations/20260804120000_contribution_approved_at.sql` :

```sql
-- La date d'APPARITION sur la carte, distincte de la date de soumission.
--
-- `created_at` existe déjà mais date du dépôt : un lieu resté trois jours en
-- modération arriverait déjà enterré dans la section « À découvrir » du volet
-- Social, ce qui viderait de son sens la seule raison pour laquelle cette
-- section existe — que chaque proposition passe sous les yeux au moins une fois.
alter table public.contributions add column approved_at timestamptz;

-- Rétro-remplissage : pour l'existant, la date de soumission est la meilleure
-- approximation disponible, et elle est juste tant que la modération suit.
update public.contributions set approved_at = created_at where status = 'approved';

-- Un TRIGGER ici, là où `20260802170000_contribution_xp.sql` en a délibérément
-- refusé un pour l'XP. La différence n'est pas de goût : l'XP est une
-- RÉCOMPENSE, et une reprise de migration qui repasserait une ligne à
-- `approved` en attribuerait deux fois. Un horodatage est DÉRIVÉ, et la garde
-- `approved_at is null` le rend idempotent — une réapprobation ne réécrit rien.
create or replace function public.stamp_contribution_approval()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'approved' and new.approved_at is null then
    new.approved_at := now();
  end if;
  return new;
end;
$$;

create trigger contributions_stamp_approval
  before insert or update of status on public.contributions
  for each row execute function public.stamp_contribution_approval();

-- Révocation obligatoire : `pg_default_acl` accorde EXECUTE à `anon` et
-- `authenticated` sur toute fonction nouvellement créée. Une fonction de
-- trigger n'a aucune raison d'être appelable directement.
revoke all on function public.stamp_contribution_approval() from public, anon, authenticated;
```

- [ ] **Step 2 : ajouter les assertions de schéma**

Dans `supabase/tests/schema_test.sql`, à la fin du fichier, ajouter :

```sql
-- `approved_at` et son trigger : la section « À découvrir » du volet Social
-- trie dessus, et sans le trigger la colonne resterait nulle pour toute
-- approbation future.
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'contributions'
      and column_name = 'approved_at' and data_type = 'timestamp with time zone'
  ) then
    raise exception 'contributions.approved_at manquante ou du mauvais type';
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.contributions'::regclass
      and tgname = 'contributions_stamp_approval'
      and not tgisinternal
  ) then
    raise exception 'trigger contributions_stamp_approval manquant';
  end if;
end $$;
```

- [ ] **Step 3 : ne rien changer à `privileges_test.sql`, et savoir pourquoi**

Le test fonctionne par **liste de refus** (`privileges_test.sql:97-108`) : il signale
toute fonction de `public` exécutable par `anon`, `authenticated` ou `PUBLIC`,
sauf trois nommément autorisées (`cast_vote`, `report_contribution`,
`is_editor`). `stamp_contribution_approval` n'a donc rien à y ajouter — c'est le
`REVOKE` de la migration qui fait passer le test, et son oubli que le test
attrape. Toucher la liste serait exactement l'erreur qu'elle prévient.

- [ ] **Step 4 : appliquer et vérifier sur une base jetable**

```sh
supabase db reset
psql "$(supabase status -o env | grep DB_URL | cut -d= -f2- | tr -d '"')" -f supabase/tests/schema_test.sql
```

Attendu : aucune exception. `schema_test.sql` inclut `privileges_test.sql`, donc les deux passent en une fois.

Si `supabase` n'est pas disponible localement, sauter à l'étape 5 et noter que la migration reste à appliquer — le reste du plan A ne dépend pas de son application, seulement de son existence.

- [ ] **Step 5 : commiter**

```sh
git add supabase/migrations/20260804120000_contribution_approved_at.sql supabase/tests/
git commit -m "feat(communaute): approved_at date l'apparition sur la carte, pas la soumission"
```

---

### Task A2 : `Contribution` porte la date

**Files:**
- Modify: `NeonCompass/Core/Community/Contribution.swift`
- Test: `NeonCompassTests/Community/ContributionTests.swift`

**Interfaces:**
- Produces: `Contribution.approvedAt: String?` (chaîne ISO 8601 brute), `Contribution.approvedAtDate: Date?` (parsée), `Contribution.parseTimestamp(_:) -> Date?`.

- [ ] **Step 1 : écrire le test qui échoue**

Créer `NeonCompassTests/Community/ContributionTests.swift` :

```swift
import Foundation
import Testing
@testable import NeonCompass

struct ContributionTests {
    private func decode(_ json: String) throws -> Contribution {
        try JSONDecoder().decode(Contribution.self, from: Data(json.utf8))
    }

    private static let base = """
    {"id":"c1","authorUid":"u1","authorHandle":"NEON-FALCON-88","category":"landmark",
     "title":"Toit du parking","languageCode":"fr","position":{"x":0.3,"y":0.6},
     "status":"approved","upvotes":12,"downvotes":1
    """

    @Test func decodesTheApprovalTimestamp() throws {
        let spot = try decode(Self.base + ###","approvedAt":"2026-08-04T18:00:00Z"}"###)
        #expect(spot.approvedAt == "2026-08-04T18:00:00Z")
        let date = try #require(spot.approvedAtDate)
        #expect(abs(date.timeIntervalSince1970 - 1_785_866_400) < 1)
    }

    /// LE cas qui compte. Un fragment mis en cache AVANT ce changement n'a pas
    /// la clé. Rendre le champ obligatoire ferait échouer le décodage de tout
    /// le fragment, donc viderait la carte hors ligne.
    @Test func decodesWithoutTheTimestamp() throws {
        let spot = try decode(Self.base + "}")
        #expect(spot.approvedAt == nil)
        #expect(spot.approvedAtDate == nil)
    }

    /// Une date illisible est ignorée, pas fatale — même règle que
    /// `OnlineEventBonus.until`. La perdre range la proposition en fin de
    /// section ; elle ne casse rien.
    @Test func anUnparsableTimestampIsIgnoredNotFatal() throws {
        let spot = try decode(Self.base + ###","approvedAt":"pas une date"}"###)
        #expect(spot.approvedAt == "pas une date")
        #expect(spot.approvedAtDate == nil)
    }

    /// Le fragment publié par `rebuild-community-bundles` porte des fractions
    /// de seconde et un décalage explicite : Postgres sérialise ainsi.
    @Test func decodesPostgresFractionalTimestamps() throws {
        let spot = try decode(Self.base + ###","approvedAt":"2026-08-04T18:00:00.123456+00:00"}"###)
        #expect(spot.approvedAtDate != nil)
    }

    /// Un aller-retour complet : le cache SwiftData réencode ce qu'il a décodé.
    @Test func roundTripsThroughEncoding() throws {
        let spot = try decode(Self.base + ###","approvedAt":"2026-08-04T18:00:00Z"}"###)
        let reencoded = try JSONEncoder().encode(spot)
        let again = try JSONDecoder().decode(Contribution.self, from: reencoded)
        #expect(again == spot)
    }
}
```

- [ ] **Step 2 : lancer le test pour vérifier qu'il échoue**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/ContributionTests 2>&1 | grep -E "error:|✘" | head -5
```

Attendu : `value of type 'Contribution' has no member 'approvedAt'`.

- [ ] **Step 3 : ajouter les deux membres**

Dans `NeonCompass/Core/Community/Contribution.swift`, remplacer :

```swift
    var upvotes: Int
    var downvotes: Int
}
```

par :

```swift
    var upvotes: Int
    var downvotes: Int

    /// L'horodatage d'approbation, **en chaîne brute**, tel que le fragment le
    /// porte.
    ///
    /// En `String` et non en `Date`, et ce n'est pas un raccourci : tout le
    /// décodage de contenu passe par un `JSONDecoder()` nu
    /// (`ContentCDN.swift:112,155`), dont la stratégie par défaut est
    /// `.deferredToDate` — une chaîne ISO 8601 y échouerait. Configurer ce
    /// décodeur toucherait tous les types de contenu à la fois. `OnlineEvent`
    /// résout la même contrainte de la même façon, en parsant à la main.
    ///
    /// Optionnel, et c'est ce qui protège le mode hors ligne : un fragment mis
    /// en cache avant l'ajout de la colonne n'a pas la clé, et un champ
    /// obligatoire ferait échouer le décodage du fragment entier.
    ///
    /// `var` et non `let` : Swift ne donne de valeur par défaut dans
    /// l'initialiseur membre à membre qu'aux propriétés `var` optionnelles.
    /// En `let`, les huit sites de construction existants devraient tous
    /// passer `nil` explicitement.
    var approvedAt: String?

    /// La date parsée, ou nil si absente ou illisible.
    ///
    /// Une date illisible est ignorée plutôt que fatale — même règle que
    /// `OnlineEventBonus.until` : la perdre range la proposition en fin de
    /// section, elle ne fabrique pas un ordre faux.
    var approvedAtDate: Date? { Self.parseTimestamp(approvedAt) }

    /// Une fonction et non une constante : `ISO8601DateFormatter` n'est pas
    /// `Sendable`, et sous concurrence stricte une constante statique non
    /// isolée est refusée à la compilation. Même contrainte que `OnlineEvent`.
    ///
    /// Deux passes : Postgres sérialise un `timestamptz` avec des fractions de
    /// seconde, que le format par défaut d'`ISO8601DateFormatter` refuse.
    static func parseTimestamp(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: raw) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw)
    }
}
```

- [ ] **Step 4 : lancer le test pour vérifier qu'il passe**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/ContributionTests 2>&1 | grep -E "error:|✘|Test run with" | head -8
```

Attendu : `Test run with 5 tests in 1 suite passed`.

- [ ] **Step 5 : commiter**

```sh
git status --short
git add NeonCompass/Core/Community/Contribution.swift NeonCompassTests/Community/ContributionTests.swift
git commit -m "feat(communaute): Contribution porte sa date d'approbation, tolérante à son absence"
```

---

### Task A3 : la colonne traverse le bundle

**Files:**
- Modify: `supabase/functions/rebuild-community-bundles/index.ts:72` et `:82-93`

**Interfaces:**
- Consumes: la colonne de la tâche A1, la clé `approvedAt` de la tâche A2.

- [ ] **Step 1 : ajouter la colonne au `select`**

Dans `supabase/functions/rebuild-community-bundles/index.ts`, remplacer :

```ts
    .select('id,author_uid,author_handle,category,title,language_code,position_x,position_y,status,upvotes,downvotes')
```

par :

```ts
    .select('id,author_uid,author_handle,category,title,language_code,position_x,position_y,status,upvotes,downvotes,approved_at')
```

- [ ] **Step 2 : ajouter la clé à la projection**

Dans le même fichier, remplacer :

```ts
    upvotes: row.upvotes ?? 0,
    downvotes: row.downvotes ?? 0,
  }));
```

par :

```ts
    upvotes: row.upvotes ?? 0,
    downvotes: row.downvotes ?? 0,
    // La date d'APPARITION sur la carte, sur laquelle le volet Social trie sa
    // section « À découvrir ». Publiée en chaîne ISO 8601 telle que Postgres la
    // sérialise ; `Contribution` la parse à la main côté client, parce que tout
    // le décodage de contenu passe par un `JSONDecoder()` nu.
    //
    // Nulle sur les lignes approuvées avant l'ajout de la colonne dont le
    // rétro-remplissage n'aurait pas abouti : le client les range en fin de
    // section plutôt que d'échouer.
    approvedAt: row.approved_at ?? null,
  }));
```

- [ ] **Step 3 : vérifier que le fichier reste valide**

```sh
deno check supabase/functions/rebuild-community-bundles/index.ts
```

Attendu : aucune erreur. Si `deno` n'est pas installé, vérifier à l'œil que les deux modifications sont bien dans le `select` et dans le `map`, et que la virgule finale est présente.

- [ ] **Step 4 : commiter**

```sh
git add supabase/functions/rebuild-community-bundles/index.ts
git commit -m "feat(communaute): le fragment publie la date d'approbation"
```

---

### Task A4 : la soumission se restreint à VI, et le chemin déconnecté parle

**Files:**
- Create: `NeonCompass/Features/Community/SignInToContributeAlert.swift`
- Modify: `NeonCompass/Features/Map/MapScreen.swift` (garde VI, alerte)
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Produces: le modificateur `.signInToContributeAlert(isPresented:)`, réutilisé par le plan B.

- [ ] **Step 1 : ajouter les trois chaînes**

Créer `$CLAUDE_JOB_DIR/tmp/add-contribute-gate-keys.py` :

```python
import json, collections

PATH = "NeonCompass/Resources/Localizable.xcstrings"

NEW = {
    "community.signInToContribute.title": {
        "en": "Sign in to contribute", "fr": "Se connecter pour contribuer",
        "es": "Inicia sesión para contribuir", "it": "Accedi per contribuire",
        "de": "Zum Mitmachen anmelden"},
    "community.signInToContribute.message": {
        "en": "Proposing places and voting need an account: it is what makes a contribution yours, and what earns you XP.",
        "fr": "Proposer un lieu et voter demandent un compte : c'est ce qui rend une contribution tienne, et ce qui te rapporte de l'XP.",
        "es": "Proponer lugares y votar requieren una cuenta: es lo que hace tuya una contribución y lo que te da XP.",
        "it": "Proporre luoghi e votare richiedono un account: è ciò che rende tua una contribuzione e ciò che ti fa guadagnare XP.",
        "de": "Orte vorschlagen und abstimmen brauchen ein Konto: es macht einen Beitrag zu deinem und bringt dir XP."},
    "community.signInToContribute.openProfile": {
        "en": "Open profile", "fr": "Ouvrir le profil", "es": "Abrir perfil",
        "it": "Apri il profilo", "de": "Profil öffnen"},
}

with open(PATH, encoding="utf-8") as f:
    catalog = json.load(f, object_pairs_hook=collections.OrderedDict)

for key, values in NEW.items():
    catalog["strings"][key] = collections.OrderedDict(
        localizations=collections.OrderedDict(
            (lang, {"stringUnit": {"state": "translated", "value": values[lang]}})
            for lang in sorted(values)
        )
    )

catalog["strings"] = collections.OrderedDict(sorted(catalog["strings"].items()))

with open(PATH, "w", encoding="utf-8") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2)
    f.write("\n")

print(f"{len(NEW)} clés ajoutées, {len(catalog['strings'])} au total")
```

Puis :

```sh
python3 "$CLAUDE_JOB_DIR/tmp/add-contribute-gate-keys.py"
```

Attendu : `3 clés ajoutées, N au total`.

- [ ] **Step 2 : créer l'alerte partagée**

Créer `NeonCompass/Features/Community/SignInToContributeAlert.swift` :

```swift
import SwiftUI

/// L'alerte que voient les deux gestes qui exigent un compte : proposer un lieu
/// sur la carte, et voter dans le volet Social.
///
/// Un seul endroit pour les deux, parce qu'ils butent sur la même condition et
/// doivent dire la même chose. Deux textes séparés divergeraient.
///
/// Ce qu'elle remplace : rien. Le bouton de proposition faisait un `if
/// authModel.userID != nil { … }` SANS `else` — déconnecté, le menu se
/// refermait et il ne se passait rien. Pas d'alerte, pas d'explication.
struct SignInToContributeAlert: ViewModifier {
    @Environment(AppModel.self) private var appModel
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.alert("community.signInToContribute.title", isPresented: $isPresented) {
            Button("community.signInToContribute.openProfile") {
                appModel.selectedTab = .profile
            }
            Button("profile.contribute.hint.cancel", role: .cancel) {}
        } message: {
            Text("community.signInToContribute.message")
        }
    }
}

extension View {
    func signInToContributeAlert(isPresented: Binding<Bool>) -> some View {
        modifier(SignInToContributeAlert(isPresented: isPresented))
    }
}
```

- [ ] **Step 3 : restreindre le bouton et les épingles à VI, et brancher l'alerte**

Dans `NeonCompass/Features/Map/MapScreen.swift` :

**(a)** Ajouter après `@State private var pendingContributionLocation: NormalizedPoint?` :

```swift
    @State private var showSignInToContribute = false
```

**(b)** Remplacer le bloc du bouton de proposition (`if serverFeatures.isEnabled, communityModel?.contributionsEnabled != false { … }`) par :

```swift
            // VI seulement. La carte de référence est intégralement documentée
            // depuis dix ans : il n'y a rien à y découvrir, et toute la raison
            // d'être des contributions est la carte que personne n'a encore
            // parcourue. C'est aussi ce qui dispense `contributions` d'une
            // colonne de jeu — il est connu par construction.
            if mapGame == .leonida, serverFeatures.isEnabled, communityModel?.contributionsEnabled != false {
                Button("map.longPress.proposeSpot") {
                    if authModel.userID != nil {
                        pendingContributionLocation = pendingPinLocation
                    } else {
                        // L'`else` qui manquait. Le bouton reste VISIBLE hors
                        // connexion — le masquer priverait un visiteur de la
                        // seule occasion d'apprendre que la contribution
                        // existe — mais il dit maintenant ce qui bloque.
                        showSignInToContribute = true
                    }
                    pendingPinLocation = nil
                }
            }
```

**(c)** Localiser le passage `communitySpots: communityModel?.visibleSpots ?? [],` et le remplacer par :

```swift
                // Les contributions ne concernent que VI : les afficher sur la
                // carte de référence les montrerait à des coordonnées
                // normalisées qui n'y veulent rien dire.
                communitySpots: mapGame == .leonida ? (communityModel?.visibleSpots ?? []) : [],
```

**(d)** Ajouter le modificateur, juste avant le `#if DEBUG` final qui porte `EditorLayer` :

```swift
        .signInToContributeAlert(isPresented: $showSignInToContribute)
```

- [ ] **Step 4 : construire et lancer toute la suite**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 \
  | grep -E "error:|✘|Test run with|TEST FAILED" | head -15
```

Attendu : `TEST SUCCEEDED`. `LocalizationCoverageTests` couvre les trois nouvelles clés.

- [ ] **Step 5 : commiter**

```sh
git status --short
# Si Localizable.xcstrings apparaît modifié sans qu'on y ait touché :
# git checkout -- NeonCompass/Resources/Localizable.xcstrings
git add NeonCompass/Features/Community/SignInToContributeAlert.swift \
        NeonCompass/Features/Map/MapScreen.swift \
        NeonCompass/Resources/Localizable.xcstrings project.yml
git commit -m "fix(carte): proposer un lieu est VI seulement, et ne rate plus en silence"
```

---

### Task A5 : le popover de la carte s'allège

**Files:**
- Modify: `NeonCompass/Features/Community/ContributionAnnotationView.swift`

**Interfaces:**
- Consumes: rien de nouveau. `onVote` disparaît de cette vue ; `MapScreen` cesse de le passer.

- [ ] **Step 1 : remplacer les boutons de vote par une lecture, et ajouter la catégorie**

Dans `NeonCompass/Features/Community/ContributionAnnotationView.swift` :

**(a)** Supprimer la propriété `let onVote: (VoteDirection) -> Void`.

**(b)** Remplacer le bloc `Text(spot.authorHandle)` et le `HStack(spacing: 16)` des votes par :

```swift
            // La catégorie n'était affichée NULLE PART, alors qu'on la choisit
            // à la soumission.
            HStack(spacing: 6) {
                Text(spot.category.localizedNameKey)
                    .font(.caption)
                    .foregroundStyle(NCColor.neonCyan)
                Text(verbatim: "·")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(spot.authorHandle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Les compteurs, en LECTURE. On vote dans le volet Social, où l'on
            // voit son propre état de vote et où la file se parcourt ; ce
            // popover dit ce qu'il y a là, il ne demande plus d'arbitrer.
            HStack(spacing: 16) {
                Label {
                    Text(verbatim: "\(spot.upvotes)")
                } icon: {
                    Image(systemName: "arrow.up")
                }
                Label {
                    Text(verbatim: "\(spot.downvotes)")
                } icon: {
                    Image(systemName: "arrow.down")
                }
                Spacer()
                // Signaler et masquer RESTENT : la directive Apple 1.2 les exige
                // partout où de l'UGC s'affiche, donc ici comme dans la liste.
                Button("map.spot.report", action: onReport)
                if let authorUid = spot.authorUid {
                    Button("map.spot.blockAuthor") {
                        showBlockConfirmation = true
                    }
                    .confirmationDialog(
                        Text(String(format: String(localized: "map.spot.blockConfirmTitle"), spot.authorHandle)),
                        isPresented: $showBlockConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("map.spot.blockConfirm", role: .destructive) {
                            onBlockAuthor()
                            showDetail = false
                        }
                        Button("map.spot.blockCancel", role: .cancel) {}
                    } message: {
                        Text("map.spot.blockConfirmMessage")
                    }
                    .id(authorUid) // scope the confirmationDialog state to this spot's author
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
```

- [ ] **Step 2 : retirer `onVote` de la chaîne d'appel — quatre sites exacts**

1. `NeonCompass/Features/Map/MapScreen.swift:245` — supprimer le bloc :

```swift
                onVote: { spot, direction in
                    Task { await communityModel?.vote(on: spot, direction: direction) }
                },
```

2. `NeonCompass/Core/Map/MapScrollView.swift:144` — supprimer la déclaration
   `let onVote: (Contribution, VoteDirection) -> Void`
3. `NeonCompass/Core/Map/MapScrollView.swift:225` — supprimer l'argument
   `onVote: { direction in onVote(spot, direction) },`
4. `NeonCompass/Core/Map/MapScrollView.swift:510` — supprimer la seconde
   déclaration `let onVote: (Contribution, VoteDirection) -> Void`, et
   `:663` l'argument `onVote: onVote,` qui la transmettait.

`CommunityModel.vote(on:direction:)` reste en place : le plan B l'appelle depuis
la liste.

- [ ] **Step 3 : construire et lancer toute la suite**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 \
  | grep -E "error:|✘|Test run with|TEST FAILED" | head -15
```

Attendu : `TEST SUCCEEDED`. `CommunityModel.vote(on:direction:)` reste en place — le plan B l'appelle depuis la liste.

- [ ] **Step 4 : commiter**

```sh
git status --short
git add NeonCompass/Features/Community/ContributionAnnotationView.swift NeonCompass/Features/Map/
git commit -m "refactor(carte): le popover d'un spot dit sa catégorie et cesse d'arbitrer"
```

---

# PLAN B — le volet Social

### Task B1 : `ContributionSections`, le découpage pur

**Files:**
- Create: `NeonCompass/Core/Community/ContributionSections.swift`
- Test: `NeonCompassTests/Community/ContributionSectionsTests.swift`

**Interfaces:**
- Consumes: `Contribution.approvedAtDate` (tâche A2), `VoteDirection`.
- Produces: `ContributionSections(spots:myVotes:limit:)` avec `discover: [Contribution]` et `top: [Contribution]`.

- [ ] **Step 1 : écrire le test qui échoue**

Créer `NeonCompassTests/Community/ContributionSectionsTests.swift` :

```swift
import Foundation
import Testing
@testable import NeonCompass

struct ContributionSectionsTests {
    private func spot(
        _ id: String,
        up: Int = 0,
        down: Int = 0,
        approvedAt: String? = nil
    ) -> Contribution {
        var made = Contribution(
            id: id,
            authorUid: "u-\(id)",
            authorHandle: "NEON-FALCON-88",
            category: .landmark,
            title: "Spot \(id)",
            languageCode: "fr",
            position: NormalizedPoint(x: 0.5, y: 0.5),
            status: .approved,
            upvotes: up,
            downvotes: down
        )
        made.approvedAt = approvedAt
        return made
    }

    // MARK: - À découvrir

    /// Ce sur quoi j'ai voté quitte « À découvrir » : la section existe pour que
    /// chaque proposition passe sous mes yeux UNE fois.
    @Test func votedSpotsLeaveTheDiscoverSection() {
        let sections = ContributionSections(
            spots: [spot("a"), spot("b")],
            myVotes: ["a": .up]
        )
        #expect(sections.discover.map(\.id) == ["b"])
    }

    /// Un vote négatif compte autant qu'un positif : j'ai vu, j'ai tranché.
    @Test func aDownvoteAlsoCountsAsSeen() {
        let sections = ContributionSections(spots: [spot("a")], myVotes: ["a": .down])
        #expect(sections.discover.isEmpty)
    }

    @Test func discoverIsMostRecentFirst() {
        let sections = ContributionSections(
            spots: [
                spot("vieux", approvedAt: "2026-08-01T10:00:00Z"),
                spot("neuf", approvedAt: "2026-08-04T10:00:00Z"),
                spot("moyen", approvedAt: "2026-08-02T10:00:00Z"),
            ],
            myVotes: [:]
        )
        #expect(sections.discover.map(\.id) == ["neuf", "moyen", "vieux"])
    }

    /// Une ligne sans date vient d'un fragment mis en cache avant l'ajout de la
    /// colonne. Elle passe en fin plutôt que de disparaître ou de remonter.
    @Test func spotsWithoutADateGoLast() {
        let sections = ContributionSections(
            spots: [spot("sansDate"), spot("daté", approvedAt: "2026-08-01T10:00:00Z")],
            myVotes: [:]
        )
        #expect(sections.discover.map(\.id) == ["daté", "sansDate"])
    }

    // MARK: - Les mieux notées

    @Test func topIsSortedByScore() {
        let sections = ContributionSections(
            spots: [spot("moyen", up: 10), spot("fort", up: 50), spot("faible", up: 1)],
            myVotes: ["moyen": .up, "fort": .up, "faible": .up]
        )
        #expect(sections.top.map(\.id) == ["fort", "moyen", "faible"])
    }

    /// Le score est un solde : vingt pour et dix-neuf contre valent moins que
    /// deux pour et zéro contre.
    @Test func scoreIsUpvotesMinusDownvotes() {
        let sections = ContributionSections(
            spots: [spot("controversé", up: 20, down: 19), spot("net", up: 2)],
            myVotes: ["controversé": .up, "net": .up]
        )
        #expect(sections.top.map(\.id) == ["net", "controversé"])
    }

    /// Pas deux fois la même ligne dans un écran : ça se lit comme un défaut,
    /// et une proposition affichée deux centimètres plus haut n'a pas besoin
    /// d'une seconde apparition.
    @Test func topExcludesWhatDiscoverAlreadyShows() {
        let sections = ContributionSections(
            spots: [spot("nouveauEtAimé", up: 99, approvedAt: "2026-08-04T10:00:00Z")],
            myVotes: [:]
        )
        #expect(sections.discover.map(\.id) == ["nouveauEtAimé"])
        #expect(sections.top.isEmpty)
    }

    /// Au démarrage, TOUT est à zéro : sans départage, l'ordre changerait à
    /// chaque réévaluation de la vue et les lignes sauteraient.
    @Test func tiesAreBrokenStably() {
        let spots = [spot("c"), spot("a"), spot("b")]
        let votes: [String: VoteDirection] = ["a": .up, "b": .up, "c": .up]
        let first = ContributionSections(spots: spots, myVotes: votes)
        let second = ContributionSections(spots: spots.reversed(), myVotes: votes)
        #expect(first.top.map(\.id) == second.top.map(\.id))
        #expect(first.top.map(\.id) == ["a", "b", "c"])
    }

    // MARK: - Plafond

    @Test func theLimitAppliesPerSection() {
        let unvoted = (1...30).map { spot("d\($0)", approvedAt: "2026-08-0\(($0 % 9) + 1)T10:00:00Z") }
        let voted = (1...30).map { spot("t\($0)", up: $0) }
        var votes: [String: VoteDirection] = [:]
        for s in voted { votes[s.id] = .up }
        let sections = ContributionSections(spots: unvoted + voted, myVotes: votes, limit: 5)
        #expect(sections.discover.count == 5)
        #expect(sections.top.count == 5)
    }

    @Test func emptyInputGivesEmptySections() {
        let sections = ContributionSections(spots: [], myVotes: [:])
        #expect(sections.discover.isEmpty)
        #expect(sections.top.isEmpty)
    }

    /// Déconnecté, on n'a voté sur rien : tout est à découvrir.
    @Test func withoutVotesEverythingIsToDiscover() {
        let sections = ContributionSections(
            spots: [spot("a", approvedAt: "2026-08-01T10:00:00Z"), spot("b", approvedAt: "2026-08-02T10:00:00Z")],
            myVotes: [:]
        )
        #expect(sections.discover.count == 2)
        #expect(sections.top.isEmpty)
    }
}
```

- [ ] **Step 2 : lancer le test pour vérifier qu'il échoue**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/ContributionSectionsTests 2>&1 | grep -E "error:" | head -3
```

Attendu : `cannot find 'ContributionSections' in scope`.

- [ ] **Step 3 : écrire le type**

Créer `NeonCompass/Core/Community/ContributionSections.swift` :

```swift
import Foundation

/// Le découpage du volet Propositions en deux sections. Type pur : ni SwiftUI,
/// ni I/O, ni date « maintenant » — donc entièrement testable.
///
/// **Pourquoi deux sections et pas un tri par score.** Un vote positif rapporte
/// +2 XP à son auteur (`20260802120000_initial_schema.sql:285`). Un classement
/// pur ferait qu'un lieu jamais vu n'est jamais voté, donc reste jamais vu, et
/// son auteur ne décolle pas. « À découvrir » garantit que chaque proposition
/// passe sous les yeux au moins une fois.
struct ContributionSections: Equatable {
    /// Approuvées sur lesquelles je n'ai pas voté, les plus récentes d'abord.
    let discover: [Contribution]

    /// Les meilleures, EXCLUANT ce que `discover` affiche déjà : deux fois la
    /// même ligne dans un écran se lit comme un défaut.
    let top: [Contribution]

    init(spots: [Contribution], myVotes: [String: VoteDirection], limit: Int = 20) {
        // Les dates sont parsées UNE fois, pas à chaque comparaison : un
        // comparateur qui construirait un `ISO8601DateFormatter` par appel en
        // ferait des milliers pour un seul tri.
        //
        // `uniquingKeysWith` et non `uniqueKeysWithValues` : ce dernier plante
        // sur un doublon d'identifiant. La base l'interdit, mais un fragment
        // corrompu ne doit pas faire tomber l'écran.
        let dates = Dictionary(
            spots.map { ($0.id, $0.approvedAtDate) },
            uniquingKeysWith: { first, _ in first }
        )

        let unvoted = spots.filter { myVotes[$0.id] == nil }
        let discovered = unvoted
            .sorted { left, right in
                switch (dates[left.id] ?? nil, dates[right.id] ?? nil) {
                // Une ligne sans date vient d'un fragment mis en cache avant
                // l'ajout de la colonne : elle passe en fin plutôt que de
                // disparaître ou de remonter en tête.
                case (nil, nil): return left.id < right.id
                case (nil, _): return false
                case (_, nil): return true
                case (let l?, let r?):
                    return l == r ? left.id < right.id : l > r
                }
            }
            .prefix(limit)
        discover = Array(discovered)

        let shown = Set(discover.map(\.id))
        top = Array(
            spots
                .filter { !shown.contains($0.id) }
                // Départage par identifiant, et ce n'est pas cosmétique : au
                // démarrage tous les scores valent zéro, et un tri instable
                // ferait sauter les lignes à chaque réévaluation de la vue.
                .sorted { left, right in
                    let leftScore = left.upvotes - left.downvotes
                    let rightScore = right.upvotes - right.downvotes
                    return leftScore == rightScore ? left.id < right.id : leftScore > rightScore
                }
                .prefix(limit)
        )
    }
}
```

- [ ] **Step 4 : lancer le test pour vérifier qu'il passe**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/ContributionSectionsTests 2>&1 | grep -E "error:|✘|Test run with" | head -8
```

Attendu : `Test run with 11 tests in 1 suite passed`.

- [ ] **Step 5 : commiter**

```sh
git status --short
git add NeonCompass/Core/Community/ContributionSections.swift \
        NeonCompassTests/Community/ContributionSectionsTests.swift project.yml
git commit -m "feat(communaute): deux sections, pour qu'une proposition ne reste pas invisible"
```

---

### Task B2 : mes votes

**Files:**
- Modify: `NeonCompass/Core/Community/ContributionRepository.swift`
- Modify: `NeonCompass/Core/Community/SupabaseContributionRepository.swift`
- Modify: `NeonCompass/Features/Community/CommunityModel.swift`
- Modify: `NeonCompassTests/Community/CommunityFakesTests.swift`

**Interfaces:**
- Produces: `ContributionRepository.fetchMyVotes(uid:) async throws -> [String: VoteDirection]`, `CommunityModel.myVotes: [String: VoteDirection]`, `CommunityModel.loadMyVotes(uid:) async`.

- [ ] **Step 1 : écrire le test qui échoue**

Dans `NeonCompassTests/Community/CommunityFakesTests.swift`, ajouter à `FakeContributionRepository` :

```swift
    nonisolated(unsafe) var votesToReturn: [String: VoteDirection] = [:]

    func fetchMyVotes(uid: String) async throws -> [String: VoteDirection] { votesToReturn }
```

Puis ajouter, à la fin du fichier, dans la suite de tests existante de `CommunityModel` :

```swift
    /// Voter met `myVotes` à jour TOUT DE SUITE. Sans ça, la ligne resterait
    /// dans « À découvrir » et ses boutons sans état jusqu'au prochain
    /// chargement — donc on pourrait revoter en boucle sans le voir.
    @Test func votingRecordsMyVoteLocally() async throws {
        let container = try makeContainer()
        let functions = FakeContributionFunctions()
        functions.voteResultToReturn = (upvotes: 13, downvotes: 1)
        let model = makeModel(context: ModelContext(container), functions: functions)
        let spot = Contribution(
            id: "c1", authorUid: "u1", authorHandle: "NEON-FALCON-88",
            category: .landmark, title: "Un lieu", languageCode: "fr",
            position: NormalizedPoint(x: 0.5, y: 0.5), status: .approved,
            upvotes: 12, downvotes: 1
        )
        await model.vote(on: spot, direction: .up)
        #expect(model.myVotes["c1"] == .up)
    }

    @Test func loadMyVotesFillsTheMap() async throws {
        let container = try makeContainer()
        let repository = FakeContributionRepository()
        repository.votesToReturn = ["c1": .up, "c2": .down]
        let model = makeModel(context: ModelContext(container), repository: repository)
        await model.loadMyVotes(uid: "u1")
        #expect(model.myVotes == ["c1": .up, "c2": .down])
    }
```

> La signature réelle est
> `makeModel(context:repository:functions:spots:remoteVersion:)`
> (`CommunityFakesTests.swift:65-71`) : `context` est requis et non nommé par
> défaut. `makeContainer()` est l'aide de conteneur SwiftData déjà utilisée par
> les tests voisins de ce fichier — reprendre exactement leur façon de
> l'obtenir.

- [ ] **Step 2 : lancer le test pour vérifier qu'il échoue**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/CommunityFakesTests 2>&1 | grep -E "error:" | head -5
```

Attendu : `value of type 'CommunityModel' has no member 'myVotes'`.

- [ ] **Step 3 : ajouter la méthode au protocole**

Dans `NeonCompass/Core/Community/ContributionRepository.swift`, remplacer :

```swift
protocol ContributionRepository: Sendable {
    func fetchMine(uid: String) async throws -> [Contribution]
}
```

par :

```swift
protocol ContributionRepository: Sendable {
    func fetchMine(uid: String) async throws -> [Contribution]

    /// Mes votes, indexés par identifiant de contribution.
    ///
    /// Requête directe et non un fragment, pour la même raison que `fetchMine` :
    /// elle est personnelle et doit être fraîche. La politique
    /// `votes_select_own` l'autorise (`20260802120100_rls_policies.sql:95-97`)
    /// et l'index `votes_uid_idx` la sert.
    ///
    /// Elle porte deux usages d'un coup : découper le volet Propositions en
    /// deux sections, et donner au vote un état visible — jusqu'ici rien ne
    /// distinguait « je n'ai pas voté » de « j'ai voté pour ».
    func fetchMyVotes(uid: String) async throws -> [String: VoteDirection]
}
```

- [ ] **Step 4 : implémenter côté Supabase**

Dans `NeonCompass/Core/Community/SupabaseContributionRepository.swift`, ajouter avant la dernière accolade fermante :

```swift
    private struct VoteRow: Decodable {
        let contributionId: String
        let direction: String

        enum CodingKeys: String, CodingKey {
            case contributionId = "contribution_id"
            case direction
        }
    }

    func fetchMyVotes(uid: String) async throws -> [String: VoteDirection] {
        guard let client else { return [:] }
        let rows: [VoteRow] = try await client
            .from("votes")
            .select("contribution_id,direction")
            .eq("uid", value: uid)
            .execute()
            .value
        // Une direction inconnue est ignorée plutôt que fatale : la contrainte
        // `check` de la table l'interdit, mais un jour où elle gagnerait une
        // troisième valeur, perdre une ligne vaut mieux que perdre la liste.
        return rows.reduce(into: [:]) { result, row in
            if let direction = VoteDirection(rawValue: row.direction) {
                result[row.contributionId] = direction
            }
        }
    }
```

- [ ] **Step 5 : porter l'état dans `CommunityModel`**

Dans `NeonCompass/Features/Community/CommunityModel.swift` :

**(a)** Ajouter après `private(set) var myContributions: [Contribution] = []` :

```swift
    /// Mes votes, par identifiant de contribution. Vide hors connexion — et
    /// c'est le bon défaut : tout se retrouve alors dans « À découvrir ».
    private(set) var myVotes: [String: VoteDirection] = [:]
```

**(b)** Ajouter une méthode de chargement, juste avant `func vote(` :

```swift
    /// Échoue en silence, délibérément : sans mes votes, les deux sections
    /// retombent sur « tout à découvrir », ce qui est dégradé mais juste. Une
    /// alerte pour ça interromprait la lecture sans rien offrir à faire.
    func loadMyVotes(uid: String) async {
        myVotes = (try? await repository.fetchMyVotes(uid: uid)) ?? [:]
    }
```

**(c)** Remplacer `vote(on:direction:)` par :

```swift
    func vote(on spot: Contribution, direction: VoteDirection) async {
        guard let counts = try? await functions.castVote(spotId: spot.id, direction: direction) else { return }
        // Enregistré AVANT la mise à jour des compteurs : le spot peut ne plus
        // être dans `approvedSpots` (fragment reconstruit entre-temps), et mon
        // vote a bien eu lieu quoi qu'il arrive. L'ordre inverse le perdrait
        // sur le `guard` suivant.
        myVotes[spot.id] = direction
        guard let index = approvedSpots.firstIndex(where: { $0.id == spot.id }) else { return }
        approvedSpots[index].upvotes = counts.upvotes
        approvedSpots[index].downvotes = counts.downvotes
    }
```

- [ ] **Step 6 : lancer toute la suite**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 \
  | grep -E "error:|✘|Test run with|TEST FAILED" | head -15
```

Attendu : `TEST SUCCEEDED`.

- [ ] **Step 7 : commiter**

```sh
git status --short
git add NeonCompass/Core/Community/ NeonCompass/Features/Community/CommunityModel.swift \
        NeonCompassTests/Community/CommunityFakesTests.swift
git commit -m "feat(communaute): mes votes sont lus, et le vote a enfin un état"
```

---

### Task B3 : les chaînes du volet

**Files:**
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

- [ ] **Step 1 : écrire le script**

Créer `$CLAUDE_JOB_DIR/tmp/add-panel-keys.py` :

```python
import json, collections

PATH = "NeonCompass/Resources/Localizable.xcstrings"

NEW = {
    "social.panel.events": {
        "en": "Events", "fr": "Événements", "es": "Eventos",
        "it": "Eventi", "de": "Events"},
    "social.panel.proposals": {
        "en": "Proposals", "fr": "Propositions", "es": "Propuestas",
        "it": "Proposte", "de": "Vorschläge"},
    "social.proposals.subtitle": {
        "en": "VI map · dropped by the community",
        "fr": "Carte VI · posées par la communauté",
        "es": "Mapa VI · marcados por la comunidad",
        "it": "Mappa VI · segnati dalla community",
        "de": "Karte VI · von der Community gesetzt"},
    "social.proposals.section.discover": {
        "en": "To discover", "fr": "À découvrir", "es": "Por descubrir",
        "it": "Da scoprire", "de": "Zu entdecken"},
    "social.proposals.section.top": {
        "en": "Best rated", "fr": "Les mieux notées", "es": "Mejor valorados",
        "it": "I più votati", "de": "Am besten bewertet"},
    "social.proposals.empty.title": {
        "en": "Nothing proposed yet", "fr": "Aucune proposition",
        "es": "Ninguna propuesta", "it": "Nessuna proposta",
        "de": "Noch keine Vorschläge"},
    "social.proposals.empty.message": {
        "en": "The VI map opens at release. Press and hold on it to propose the first place.",
        "fr": "La carte VI s'ouvre à la sortie. Appuie longuement dessus pour proposer le premier lieu.",
        "es": "El mapa VI se abre en el lanzamiento. Mantén pulsado para proponer el primer lugar.",
        "it": "La mappa VI apre all'uscita. Tieni premuto per proporre il primo luogo.",
        "de": "Die Karte VI öffnet zum Release. Halte sie gedrückt, um den ersten Ort vorzuschlagen."},
}

with open(PATH, encoding="utf-8") as f:
    catalog = json.load(f, object_pairs_hook=collections.OrderedDict)

for key, values in NEW.items():
    catalog["strings"][key] = collections.OrderedDict(
        localizations=collections.OrderedDict(
            (lang, {"stringUnit": {"state": "translated", "value": values[lang]}})
            for lang in sorted(values)
        )
    )

catalog["strings"] = collections.OrderedDict(sorted(catalog["strings"].items()))

with open(PATH, "w", encoding="utf-8") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2)
    f.write("\n")

print(f"{len(NEW)} clés ajoutées, {len(catalog['strings'])} au total")
```

- [ ] **Step 2 : l'exécuter et vérifier**

```sh
python3 "$CLAUDE_JOB_DIR/tmp/add-panel-keys.py"
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/LocalizationCoverageTests 2>&1 | grep -E "✘|Test run with" | head -5
```

Attendu : `7 clés ajoutées, N au total` puis le test vert.

- [ ] **Step 3 : commiter**

```sh
git add NeonCompass/Resources/Localizable.xcstrings
git commit -m "i18n(social): les chaînes du volet Propositions"
```

---

### Task B4 : la ligne et le volet

**Files:**
- Create: `NeonCompass/Features/Social/ContributionRow.swift`
- Create: `NeonCompass/Features/Social/ContributionsPanel.swift`

**Interfaces:**
- Consumes: `ContributionSections` (B1), `CommunityModel.myVotes` (B2), les clés (B3), `.signInToContributeAlert(isPresented:)` (A4).
- Produces: `ContributionsPanel(communityModel:)`, `ContributionRow(spot:myVote:onVote:onReport:onBlockAuthor:)`.

- [ ] **Step 1 : créer la ligne**

Créer `NeonCompass/Features/Social/ContributionRow.swift` :

```swift
import SwiftUI

/// Une proposition dans le volet Social : ce qu'elle est, qui l'a posée, et
/// les deux votes AVEC mon état — que la carte n'affichait pas.
struct ContributionRow: View {
    let spot: Contribution
    let myVote: VoteDirection?
    let onVote: (VoteDirection) -> Void
    let onReport: () -> Void
    let onBlockAuthor: () -> Void

    @State private var showBlockConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(spot.category.localizedNameKey)
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(NCColor.neonCyan)
                if let relative = relativeDate {
                    Text(verbatim: "·")
                        .font(NCTypography.cardMeta)
                        .foregroundStyle(.white.opacity(0.4))
                    Text(relative)
                        .font(NCTypography.cardMeta)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            }

            Text(spot.title)
                .font(NCTypography.body)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)

            Text(spot.authorHandle)
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white.opacity(0.5))

            HStack(spacing: 12) {
                voteButton(.up, symbol: "arrow.up", count: spot.upvotes)
                voteButton(.down, symbol: "arrow.down", count: spot.downvotes)
                Spacer()
                // Signaler et masquer : la directive Apple 1.2 les exige partout
                // où de l'UGC s'affiche, donc ici comme sur la carte.
                Menu {
                    Button("map.spot.report", action: onReport)
                    if spot.authorUid != nil {
                        Button("map.spot.blockAuthor", role: .destructive) {
                            showBlockConfirmation = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel(Text("map.spot.report"))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .confirmationDialog(
            Text(String(format: String(localized: "map.spot.blockConfirmTitle"), spot.authorHandle)),
            isPresented: $showBlockConfirmation,
            titleVisibility: .visible
        ) {
            Button("map.spot.blockConfirm", role: .destructive, action: onBlockAuthor)
            Button("map.spot.blockCancel", role: .cancel) {}
        } message: {
            Text("map.spot.blockConfirmMessage")
        }
    }

    /// Mon vote se voit : rempli et cyan quand c'est le mien, creux sinon.
    /// C'est exactement ce qui manquait — rien ne distinguait « je n'ai pas
    /// voté » de « j'ai voté pour ».
    private func voteButton(_ direction: VoteDirection, symbol: String, count: Int) -> some View {
        let isMine = myVote == direction
        return Button {
            onVote(direction)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isMine ? "\(symbol).circle.fill" : "\(symbol).circle")
                Text(verbatim: "\(count)")
            }
            .font(NCTypography.cardMeta)
            .foregroundStyle(isMine ? NCColor.neonCyan : .white.opacity(0.6))
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isMine ? [.isSelected] : [])
    }

    /// `nil` quand la date manque — la ligne perd sa mention, elle ne perd pas
    /// sa place.
    ///
    /// Pas de `now` reçu en paramètre : `.relative` se compare à l'instant du
    /// rendu et n'accepte pas de date de référence. Un `now` passé de l'écran
    /// serait donc une propriété morte, et la minuterie de `SocialScreen`
    /// reconstruit déjà la vue chaque minute — la mention se rafraîchit sans
    /// qu'on ait à la piloter.
    private var relativeDate: String? {
        guard let date = spot.approvedAtDate else { return nil }
        return date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }
}
```

- [ ] **Step 2 : créer le volet**

Créer `NeonCompass/Features/Social/ContributionsPanel.swift` :

```swift
import SwiftUI

/// Le volet Propositions de l'onglet Social.
///
/// C'est ICI qu'on vote, et pas dans le popover d'une épingle : voter c'est
/// parcourir ce qui vient d'être proposé, une épingle répond à « qu'est-ce
/// qu'il y a là ». Et avant la sortie du 19 novembre, la carte VI est vide —
/// ce volet est la seule surface où une contribution existe.
///
/// Pas de bascule V/VI : les contributions ne concernent que VI, et
/// `OnlineEventsModel.showsGamePicker` pose déjà la règle — pas de sélecteur
/// quand il n'y a rien à choisir. Le périmètre est dit en sous-titre.
struct ContributionsPanel: View {
    @Environment(AuthModel.self) private var authModel
    let communityModel: CommunityModel

    @State private var showSignInToContribute = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("social.proposals.subtitle")
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white.opacity(0.5))

            if communityModel.visibleSpots.isEmpty {
                emptyState
            } else {
                let sections = ContributionSections(
                    spots: communityModel.visibleSpots,
                    myVotes: communityModel.myVotes
                )
                if !sections.discover.isEmpty {
                    section("social.proposals.section.discover", spots: sections.discover)
                }
                if !sections.top.isEmpty {
                    section("social.proposals.section.top", spots: sections.top)
                }
            }
        }
        .signInToContributeAlert(isPresented: $showSignInToContribute)
    }

    private func section(_ titleKey: LocalizedStringKey, spots: [Contribution]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(titleKey)
                .font(NCTypography.cardMeta)
                .foregroundStyle(NCColor.neonCyan)
                .textCase(.uppercase)
            ForEach(spots) { spot in
                ContributionRow(
                    spot: spot,
                    myVote: communityModel.myVotes[spot.id],
                    onVote: { direction in
                        guard authModel.userID != nil else {
                            showSignInToContribute = true
                            return
                        }
                        Task { await communityModel.vote(on: spot, direction: direction) }
                    },
                    onReport: { Task { await communityModel.report(spot, reason: nil) } },
                    onBlockAuthor: {
                        if let authorUid = spot.authorUid {
                            communityModel.block(authorUid: authorUid, handle: spot.authorHandle)
                        }
                    }
                )
            }
        }
    }

    /// Pas de bannière publicitaire ici : la spec §5 la réserve aux écrans de
    /// LISTE, et un état vide n'en est pas un — même correctif que celui déjà
    /// appliqué à l'état vide des événements.
    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("social.proposals.empty.title")
                .font(NCTypography.body.bold())
                .foregroundStyle(.white)
            Text("social.proposals.empty.message")
                .font(NCTypography.body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}
```

- [ ] **Step 3 : construire**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3
```

Attendu : `** BUILD SUCCEEDED **`. Ces deux vues ne sont pas encore appelées ; la tâche B5 les branche.

- [ ] **Step 4 : commiter**

```sh
git status --short
git add NeonCompass/Features/Social/ContributionRow.swift \
        NeonCompass/Features/Social/ContributionsPanel.swift project.yml
git commit -m "feat(social): la ligne d'une proposition et son volet"
```

---

### Task B5 : `SocialScreen` gagne son sélecteur de volets

**Files:**
- Modify: `NeonCompass/Features/Social/SocialScreen.swift`

**Interfaces:**
- Consumes: `ContributionsPanel(communityModel:)` (B4), `CommunityModel.loadMyVotes(uid:)` (B2).

- [ ] **Step 1 : ajouter l'état, le modèle communauté et le sélecteur**

Dans `NeonCompass/Features/Social/SocialScreen.swift` :

**(a)** Ajouter après `@State private var leaderboardRows: [LeaderboardRow] = []` :

```swift
    /// Le volet affiché. Non persisté : Social s'ouvre sur les événements, qui
    /// sont son sujet principal jusqu'à la sortie.
    @State private var panel: Panel = .events
    @State private var communityModel: CommunityModel?
    @Environment(AuthModel.self) private var authModel

    private enum Panel: String, CaseIterable, Identifiable {
        case events, proposals
        var id: String { rawValue }

        var titleKey: LocalizedStringKey {
            switch self {
            case .events: "social.panel.events"
            case .proposals: "social.panel.proposals"
            }
        }
    }
```

**(b)** Remplacer le début de `content(_ model:)` — depuis `ScrollView {` jusqu'à la fermeture du bloc `if model.showsGamePicker { … }` inclus — par :

```swift
        ScrollView {
            VStack(spacing: 20) {
                Picker(selection: $panel) {
                    ForEach(Panel.allCases) { candidate in
                        Text(candidate.titleKey).tag(candidate)
                    }
                } label: {
                    Text("social.panel.events")
                }
                .pickerStyle(.segmented)

                switch panel {
                case .events:
                    eventsPanel(model)
                case .proposals:
                    if serverFeatures.isEnabled, let communityModel {
                        ContributionsPanel(communityModel: communityModel)
                    }
                }
            }
```

**(c)** Extraire le contenu existant dans une méthode. Ajouter, après `content(_:)` :

```swift
    /// L'écran d'avant, déplacé sans changement de comportement. Le sélecteur
    /// de jeu vit ICI et non en tête d'écran : deux barres de segments empilées
    /// seraient illisibles, et il ne concerne que les événements — le classement
    /// est global, les propositions sont VI par construction.
    @ViewBuilder
    private func eventsPanel(_ model: OnlineEventsModel) -> some View {
        if model.showsGamePicker {
            Picker(selection: Binding(
                get: { model.selectedGame },
                set: { model.selectedGame = $0 }
            )) {
                ForEach(model.availableGames) { game in
                    Text(game.shortLabel).tag(game)
                }
            } label: {
                Text("social.game.picker")
            }
            .pickerStyle(.segmented)
        }

        let shown = model.currentEvent(at: now) ?? model.latestEvent()
        if let shown {
            OnlineEventCard(event: shown, now: now)
        } else {
            emptyState
        }
        if serverFeatures.isEnabled {
            LeaderboardSection(rows: leaderboardRows)
        }
        // Écran de liste : la bannière s'y applique (spec §5), jamais sur la
        // carte en interaction. Conditionnée à l'abonnement ET à une carte à
        // montrer — un état vide n'est pas un écran de liste.
        if shown != nil, !proEntitlementModel.isProEntitled {
            BannerAdView()
        }
    }
```

Retirer du corps de `content(_:)` les lignes ainsi déplacées, en conservant `.frame(maxWidth: 640)`, `.frame(maxWidth: .infinity)`, `.padding(20)` et le `.refreshable` sur le `ScrollView`.

**(d)** Dans le `.refreshable`, ajouter après `await loadLeaderboard()` :

```swift
            await loadCommunity()
```

**(e)** Ajouter la construction et le chargement, après `loadModel()` :

```swift
    /// Construit à la demande et non au montage : le volet Propositions n'est
    /// pas celui qui s'ouvre, et `CommunityModel.live` monte quatre magasins.
    private func loadCommunity() async {
        if communityModel == nil {
            communityModel = CommunityModel.live(modelContext: modelContext)
        }
        await communityModel?.loadApprovedSpots()
        if let uid = authModel.userID {
            await communityModel?.loadMyVotes(uid: uid)
        }
    }
```

**(f)** Ajouter sur le `ZStack` du `body`, à côté du `.task { await loadModel() }` existant :

```swift
        .task(id: panel) {
            guard panel == .proposals else { return }
            await loadCommunity()
        }
```

- [ ] **Step 2 : construire et lancer toute la suite**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 \
  | grep -E "error:|✘|Test run with|TEST FAILED" | head -15
```

Attendu : `TEST SUCCEEDED`. Si `modelContext` n'est pas déjà dans `SocialScreen`, il y est — `@Environment(\.modelContext)` est déclaré ligne 11.

- [ ] **Step 3 : commiter**

```sh
git status --short
# Si Localizable.xcstrings apparaît modifié sans qu'on y ait touché :
# git checkout -- NeonCompass/Resources/Localizable.xcstrings
git add NeonCompass/Features/Social/SocialScreen.swift
git commit -m "feat(social): deux volets, Événements et Propositions"
```

---

### Task B6 : vérification visuelle

**Files:** aucun modifié en fin de tâche.

- [ ] **Step 1 : capturer le volet garni**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -1
APP=/Users/antoine/Library/Developer/Xcode/DerivedData/NeonCompass-enlprsteawxizwdrpgsyjxejtokr/Build/Products/Debug-iphonesimulator
xcrun simctl install booted "$APP/NeonCompass.app"
xcrun simctl launch booted co.antoineteston.NeonCompass
sleep 5
osascript -e 'tell application "Simulator" to activate'
/opt/homebrew/bin/cliclick c:397,878   # onglet Social
sleep 3
xcrun simctl io booted screenshot "$CLAUDE_JOB_DIR/tmp/social-volets.png"
```

Le sélecteur de volets est en tête d'un `ScrollView` : `cliclick` y est consommé
comme un défilement (cf. mémoire projet). Pour capturer le volet Propositions,
forcer `@State private var panel: Panel = .proposals`, reconstruire, capturer,
puis **rétablir** et vérifier que `git status` est propre.

Vérifier sur les captures : les deux segments, le sous-titre « Carte VI », les
deux sections nommées, et sur une ligne l'état de vote (rempli cyan quand il est
le mien).

- [ ] **Step 2 : vérifier la garde VI sur la carte**

Basculer `@State private var mapGame: MapGame = .leonida`, reconstruire, appuyer
longuement sur la carte, vérifier que « Proposer un lieu » apparaît. Rebasculer
sur `.reference` et vérifier qu'il a disparu. Rétablir la valeur d'origine.

- [ ] **Step 3 : vérifier le chemin déconnecté**

Se déconnecter depuis les réglages, appuyer longuement sur la carte VI, appuyer
sur « Proposer un lieu ». Attendu : l'alerte « Se connecter pour contribuer »
avec un bouton qui bascule sur le Profil — et non plus rien du tout.

- [ ] **Step 4 : suite complète et arbre propre**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 \
  | grep -E "Test run with|TEST FAILED" | head -3
git status --short
```

Attendu : suite verte et arbre propre (restaurer `Localizable.xcstrings` s'il a
été réécrit par l'extraction automatique).

---

## Ordre et dépendances

```
PLAN A
 A1 migration ──→ A3 bundle
 A2 Contribution ─┘
 A4 garde VI + alerte  (indépendante)
 A5 popover allégé     (indépendante)

PLAN B  (suppose A2 pour la date, A4 pour l'alerte)
 B1 ContributionSections ─┐
 B2 mes votes ────────────┼─→ B4 ligne + volet ─→ B5 SocialScreen ─→ B6 vérif
 B3 chaînes ──────────────┘
```
