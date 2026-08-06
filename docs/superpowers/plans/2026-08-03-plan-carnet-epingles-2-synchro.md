# Carnet d'épingles — chantier 2 (synchro Pro) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Faire du carnet d'épingles une donnée qui suit son propriétaire d'un appareil à l'autre, pour les abonnés Pro — ce que le plafond gratuit vend déjà dans son mur.

**Architecture:** Une table `personal_pins` sous RLS, clé primaire `(uid, id)` où `id` est l'UUID que le client a déjà attribué à l'épingle. La suppression bascule en pierre tombale, sans quoi effacer sur l'iPhone ne se propagerait jamais. La réconciliation est dernière-écriture-gagne **par épingle**, comme celle de la progression, et vit dans `PersonalPinStore` — un seul magasin décide.

**Tech Stack:** Postgres 17 + RLS, Supabase Swift SDK, SwiftData, Swift Testing, psql pour les tests SQL.

## Global Constraints

- **Deux verrous sur chaque table, pas un.** `pg_default_acl` accorde `arwdDxtm` à `anon` et `authenticated` sur toute table nouvellement créée dans `public` : **toute migration qui crée une table porte donc sa propre révocation**, puisque `20260802140000_privileges.sql` n'est plus le dernier fichier.
- **`supabase/tests/privileges_test.sql` est en LECTURE PURE** et s'exécute contre la production après chaque application. Toute table nouvelle doit apparaître dans ses listes, en connaissance de cause.
- **`schema_test.sql` est réservé à la base jetable** — il insère des fixtures. Ne jamais le lancer contre la production.
- **Supabase reste derrière des protocoles dans `Core/`** — les features ne l'importent jamais directement.
- **Swift 6, concurrence stricte. Swift Testing** pour tout test nouveau.
- **`xcodegen generate` après toute création de fichier source.**
- **`xcodebuild test` peut réécrire `Localizable.xcstrings`** — vérifier `git status` avant de commiter.
- La synchro est **Pro + connecté**, jamais l'un sans l'autre. Le protocole lui-même n'a aucun avis là-dessus : ce sont ses appelants qui vérifient.
- Spec : `docs/superpowers/specs/2026-08-03-carnet-epingles-design.md`, section « Découpage → Chantier 2 ».

```sh
Scripts/db-test.sh --stubs     # Postgres nu + stubs (Docker absent sur cette machine)
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test
```

---

## Décisions de conception

**`(uid, id)` en clé primaire, l'`id` venant du client.** L'épingle a déjà un `UUID` local qui est son identité depuis le chantier 1 ; le serveur l'adopte au lieu d'en fabriquer un second. Sans ça il faudrait une table de correspondance, ou un aller-retour avant de pouvoir écrire — et une épingle posée hors ligne n'aurait pas d'identité stable.

**Les bornes de longueur sont nouvelles, et nécessaires.** `progression` ne portait aucun texte libre : ses colonnes sont un identifiant, un booléen et une date. `personal_pins` est **la première table où le client écrit de la prose**. Sans borne, un compte pourrait y stocker des mégaoctets. D'où `title ≤ 200`, `note ≤ 2000`, `icon ≤ 32`, et `x`/`y` dans `[0, 1]`.

**`game` porte un CHECK, `icon` non.** Les deux sont des ensembles fermés côté client, mais ils ne changent pas au même rythme. Ajouter une carte est un évènement délibéré qui s'accompagne d'une migration ; ajouter une septième icône est une mise à jour d'app, et un CHECK ferait alors du serveur le goulot — les clients à jour se verraient refuser leurs épingles jusqu'à ce que la migration passe. `PersonalPinIcon.from(rawValue:)` retombe déjà sur `.marker` pour l'inconnu : la tolérance est du bon côté.

**Pas de purge des pierres tombales, et c'est délibéré.** Purger côté serveur rouvre le danger classique : un appareil resté hors ligne au-delà de la fenêtre de purge n'a jamais vu la tombe, et **ressuscite l'épingle** en se resynchronisant. Le coût de ne pas purger est dérisoire — une ligne d'environ deux cents octets, soit un mégaoctet pour un joueur qui créerait et supprimerait cinq épingles par jour pendant trois ans. On garde tout.

---

## Structure des fichiers

**Créés**

| Fichier | Responsabilité |
|---|---|
| `supabase/migrations/20260803190000_personal_pins.sql` | Table, contraintes, RLS et **sa propre révocation de privilèges**. |
| `NeonCompass/Core/Sync/PersonalPinSyncing.swift` | Le protocole et son enregistrement de transport. |
| `NeonCompass/Core/Sync/SupabasePersonalPinSync.swift` | L'implémentation adossée à la table. |
| `NeonCompassTests/Sync/PersonalPinReconciliationTests.swift` | Les règles de réconciliation et la pierre tombale. |

**Modifiés**

| Fichier | Changement |
|---|---|
| `supabase/tests/privileges_test.sql` | `personal_pins` entre dans deux listes. |
| `supabase/tests/schema_test.sql` | RLS, défaut d'`uid`, bornes. |
| `NeonCompass/Core/Map/PersonalPinStore.swift` | Pierre tombale, téléversement, réconciliation. |
| `NeonCompass/Features/Map/MapScreen.swift` | Branche la synchro quand Pro + connecté. |
| `NeonCompassTests/Map/PersonalPinStoreTests.swift` | Suit la bascule en suppression logique. |

---

## Task 1 : La table, ses verrous, et ce qui les vérifie

**Files:**
- Create: `supabase/migrations/20260803190000_personal_pins.sql`
- Modify: `supabase/tests/privileges_test.sql`
- Modify: `supabase/tests/schema_test.sql`

**Interfaces:**
- Produit : table `public.personal_pins (uid, id, game, x, y, title, note, icon, is_done, created_at, updated_at, deleted_at)`, PK `(uid, id)`, politique `personal_pins_all_own`.

- [ ] **Step 1 : Écrire la migration**

Créer `supabase/migrations/20260803190000_personal_pins.sql` :

```sql
-- Le carnet d'épingles, synchronisé pour les abonnés Pro.
--
-- Une ligne par épingle, jamais un blob unique : le dernier-écrivain-gagne se
-- fait PAR ÉPINGLE, sinon un appareil resté hors ligne longtemps écraserait tout
-- le carnet de l'autre en se resynchronisant. Même raisonnement que
-- `progression`, et la clé primaire a la même forme.
--
-- `id` vient du CLIENT : l'épingle a déjà un UUID local qui est son identité,
-- et le serveur l'adopte au lieu d'en fabriquer un second. Sans ça il faudrait
-- une table de correspondance, ou un aller-retour avant de pouvoir écrire — et
-- une épingle posée hors ligne n'aurait pas d'identité stable.
create table public.personal_pins (
  uid uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id uuid not null,

  game text not null check (game in ('leonida', 'gtav')),

  -- Bornées au carré unitaire : ce sont des coordonnées normalisées, et rien
  -- au-dehors ne désigne un point de la carte.
  x double precision not null check (x >= 0 and x <= 1),
  y double precision not null check (y >= 0 and y <= 1),

  -- LES BORNES DE LONGUEUR SONT NOUVELLES, et nécessaires.
  --
  -- `progression` ne portait aucun texte libre : un identifiant, un booléen, une
  -- date. Cette table est la PREMIÈRE où le client écrit de la prose. Sans
  -- borne, un compte pourrait y stocker des mégaoctets — RLS l'autorise, c'est
  -- sa propre ligne.
  title text not null default '' check (length(title) <= 200),
  note  text not null default '' check (length(note) <= 2000),

  -- PAS de CHECK sur la valeur, et c'est un choix — contrairement à `game`.
  --
  -- Les deux sont des ensembles fermés côté client, mais ils ne changent pas au
  -- même rythme. Ajouter une carte est un évènement délibéré qui s'accompagne
  -- d'une migration ; ajouter une septième icône est une simple mise à jour
  -- d'app, et un CHECK ferait alors du serveur le goulot : les clients à jour se
  -- verraient refuser leurs épingles jusqu'à ce que la migration passe.
  -- `PersonalPinIcon.from(rawValue:)` retombe déjà sur `marker` pour l'inconnu.
  -- Seule la longueur est bornée.
  icon text not null default 'marker' check (length(icon) <= 32),

  is_done boolean not null default false,
  created_at timestamptz not null,
  updated_at timestamptz not null,

  -- PIERRE TOMBALE. Un `delete` local ne se propage pas : sans cette colonne,
  -- une épingle effacée sur l'iPhone reviendrait depuis l'iPad à la
  -- resynchronisation suivante, puisque l'iPad la possède encore et que rien ne
  -- lui dirait qu'elle a été retirée.
  --
  -- On ne purge JAMAIS ces lignes, et c'est délibéré : purger rouvre le danger
  -- classique, un appareil resté hors ligne au-delà de la fenêtre n'a pas vu la
  -- tombe et RESSUSCITE l'épingle. Le coût de tout garder est dérisoire.
  deleted_at timestamptz,

  primary key (uid, id)
);

-- Le client relit son carnet entier au lancement, filtré sur son uid seul : la
-- clé primaire couvre déjà ce chemin. Pas d'index supplémentaire.

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.personal_pins enable row level security;

-- Un carnet est strictement personnel : ni lecture ni écriture d'autrui, à
-- aucune condition. Rien à voir avec `contributions`, qui a une face publique.
create policy personal_pins_all_own on public.personal_pins
  for all to authenticated
  using (auth.uid() = uid)
  with check (auth.uid() = uid);

-- ---------------------------------------------------------------------------
-- Privilèges — la révocation que cette migration porte elle-même
-- ---------------------------------------------------------------------------
--
-- `20260802140000_privileges.sql` n'est plus le dernier fichier de migration :
-- ses REVOKE ont été joués AVANT que cette table n'existe, et `pg_default_acl`
-- vient d'accorder SELECT/INSERT/UPDATE/DELETE à `anon` ET `authenticated`
-- dessus. Sans le bloc ci-dessous, un client anonyme aurait le premier verrou
-- grand ouvert et RLS serait seule à tenir.

revoke all on public.personal_pins from anon, authenticated;

-- Écriture connectée, bornée par RLS à ses propres lignes. La quatrième table
-- où le client écrit directement.
grant select, insert, update, delete on public.personal_pins to authenticated;

grant all on public.personal_pins to service_role;
```

- [ ] **Step 2 : Étendre `privileges_test.sql`**

Dans `supabase/tests/privileges_test.sql`, deux listes changent.

Première assertion — les tables où l'écriture est permise :

```sql
     and table_name not in ('progression', 'push_tokens', 'editor_drafts', 'personal_pins');
```

Quatrième assertion — la lecture connectée :

```sql
     and table_name not in ('app_config', 'contributions', 'leaderboard', 'profiles',
                            'votes', 'progression', 'push_tokens', 'editor_drafts',
                            'personal_pins');
```

Et corriger le commentaire de la première, qui dit « les trois tables » :

```sql
  -- Aucune écriture directe, nulle part, sauf les quatre tables où le client
  -- n'écrit que ses propres lignes.
```

Corriger aussi le commentaire de `20260802140000_privileges.sql` qui dit « Ce sont les trois seuls endroits où un client écrit directement » → « Ce sont les seuls endroits… ; `personal_pins` s'y ajoute dans sa propre migration. »

- [ ] **Step 3 : Étendre `schema_test.sql`**

Ajouter, après le bloc RLS de `progression` (les fixtures `11111111-…` et `22222222-…` existent déjà) :

```sql
-- ---------------------------------------------------------------------------
-- Carnet d'épingles — cloisonnement, défaut d'uid, bornes
-- ---------------------------------------------------------------------------

insert into public.personal_pins (uid, id, game, x, y, title, created_at, updated_at) values
  ('11111111-1111-1111-1111-111111111111', 'bbbbbbbb-0000-0000-0000-000000000001',
   'gtav', 0.5, 0.5, 'À moi', now(), now()),
  ('22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0000-0000-0000-000000000002',
   'gtav', 0.6, 0.6, 'À l''autre', now(), now());

do $$
declare
  n integer;
  owner uuid;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);

  -- Un carnet est strictement personnel : aucune face publique, contrairement
  -- aux contributions.
  select count(*) into n from public.personal_pins;
  assert n = 1, format('un utilisateur ne doit voir QUE son carnet, il en voit %s', n);

  -- Le défaut d'uid, comme sur progression : omettre la colonne ne doit pas
  -- produire un 403 dont le message ne dit rien.
  insert into public.personal_pins (id, game, x, y, created_at, updated_at)
       values ('bbbbbbbb-0000-0000-0000-000000000003', 'gtav', 0.1, 0.1, now(), now());
  select uid into owner from public.personal_pins
   where id = 'bbbbbbbb-0000-0000-0000-000000000003';
  assert owner = '11111111-1111-1111-1111-111111111111',
    format('le défaut doit poser l''appelant comme propriétaire, obtenu %s', owner);

  -- Écrire dans le carnet d'un autre reste refusé.
  begin
    insert into public.personal_pins (uid, id, game, x, y, created_at, updated_at)
         values ('22222222-2222-2222-2222-222222222222',
                 'bbbbbbbb-0000-0000-0000-000000000004', 'gtav', 0.2, 0.2, now(), now());
    assert false, 'écrire le carnet d''un autre doit rester refusé';
  exception when insufficient_privilege then
    null; -- attendu
  end;

  -- La pierre tombale est une MISE À JOUR, pas une suppression : la ligne reste,
  -- c'est ce qui permet à l'autre appareil d'apprendre l'effacement.
  update public.personal_pins set deleted_at = now(), updated_at = now()
   where id = 'bbbbbbbb-0000-0000-0000-000000000001';
  select count(*) into n from public.personal_pins
   where id = 'bbbbbbbb-0000-0000-0000-000000000001' and deleted_at is not null;
  assert n = 1, 'la tombe doit subsister comme ligne, sinon elle ne se propage pas';

  reset role;
end $$;

-- Les bornes de longueur, qui n'existaient sur aucune table avant celle-ci.
do $$
begin
  begin
    insert into public.personal_pins (uid, id, game, x, y, note, created_at, updated_at)
         values ('11111111-1111-1111-1111-111111111111',
                 'bbbbbbbb-0000-0000-0000-000000000005', 'gtav', 0.3, 0.3,
                 repeat('x', 2001), now(), now());
    assert false, 'une note de plus de 2000 caractères doit être refusée';
  exception when check_violation then
    null; -- attendu
  end;

  begin
    insert into public.personal_pins (uid, id, game, x, y, created_at, updated_at)
         values ('11111111-1111-1111-1111-111111111111',
                 'bbbbbbbb-0000-0000-0000-000000000006', 'gtav', 1.5, 0.3, now(), now());
    assert false, 'une coordonnée hors du carré unitaire doit être refusée';
  exception when check_violation then
    null; -- attendu
  end;
end $$;
```

- [ ] **Step 4 : Lancer les tests SQL**

```sh
Scripts/db-test.sh --stubs
```

Attendu : `les trois verrous : OK` et la sortie finale de `schema_test.sql`, sans `assert` en échec.

- [ ] **Step 5 : Commit**

```sh
git add supabase/
git commit -m "feat(bdd): la table du carnet, ses bornes et sa propre révocation"
```

---

## Task 2 : Le protocole et son implémentation

**Files:**
- Create: `NeonCompass/Core/Sync/PersonalPinSyncing.swift`
- Create: `NeonCompass/Core/Sync/SupabasePersonalPinSync.swift`

**Interfaces:**
- Produit :
  - `struct PersonalPinSyncItem: Sendable, Equatable` — `id: UUID, game: String, x: Double, y: Double, title: String, note: String, icon: String, isDone: Bool, createdAt: Date, updatedAt: Date, deletedAt: Date?`
  - `protocol PersonalPinSyncing: Sendable` — `func upload(_ item: PersonalPinSyncItem) async`, `func fetchAll(uid: String) async -> [PersonalPinSyncItem]`
  - `final class SupabasePersonalPinSync: PersonalPinSyncing` — `init(client: SupabaseClient? = SupabaseClientProvider.shared)`

- [ ] **Step 1 : Écrire le protocole**

Créer `NeonCompass/Core/Sync/PersonalPinSyncing.swift` :

```swift
import Foundation

/// Une épingle telle qu'elle voyage. Volontairement plate et sans référence au
/// modèle SwiftData : `PersonalPin` est une classe liée à un `ModelContext`, donc
/// ni `Sendable` ni transportable hors du fil principal.
struct PersonalPinSyncItem: Sendable, Equatable {
    let id: UUID
    let game: String
    let x: Double
    let y: Double
    let title: String
    let note: String
    let icon: String
    let isDone: Bool
    let createdAt: Date
    let updatedAt: Date
    /// Non nul = pierre tombale. L'épingle a été supprimée sur un appareil, et
    /// cette information doit voyager comme le reste : un `delete` qui ne
    /// laisserait rien derrière lui ne se propagerait jamais.
    let deletedAt: Date?
}

/// Abstraction du miroir distant du carnet.
///
/// La synchro est Pro + connecté (spec : « nécessite le compte »), et ce
/// protocole n'en a aucun avis — comme `ProgressionSyncing`, il déplace des
/// données quand on le lui demande. C'est à ses appelants de vérifier
/// `ProEntitlementModel.isProEntitled` ET `AuthModel.userID` avant de
/// l'appeler.
protocol PersonalPinSyncing: Sendable {
    func upload(_ item: PersonalPinSyncItem) async
    func fetchAll(uid: String) async -> [PersonalPinSyncItem]
}
```

- [ ] **Step 2 : Écrire l'implémentation**

Créer `NeonCompass/Core/Sync/SupabasePersonalPinSync.swift` :

```swift
import Foundation
import Supabase

/// Implémentation réelle de `PersonalPinSyncing`, adossée à `personal_pins`.
///
/// L'`upsert` porte sur `(uid, id)`, la clé primaire : c'est la base qui garantit
/// l'unicité, pas une chaîne construite à la main. Et l'`id` vient du client,
/// donc une épingle posée hors ligne a déjà son identité définitive quand elle
/// finit par monter.
///
/// Les erreurs sont avalées, comme dans `SupabaseProgressionSync` : le carnet
/// local reste la vérité de l'appareil, la synchronisation est un confort. Le
/// protocole ne lève pas, et ses appelants n'auraient rien à faire d'une erreur
/// qu'ils ne peuvent pas réparer.
final class SupabasePersonalPinSync: PersonalPinSyncing {
    /// Miroir de la ligne. Les clés sont écrites explicitement plutôt que
    /// laissées à une conversion automatique : `isDone` deviendrait `is_done`
    /// mais `createdAt` deviendrait `created_at` et `deletedAt` `deleted_at` —
    /// sauf que `.convertToSnakeCase` casse sur les acronymes, et le décalage ne
    /// se verrait qu'à l'exécution, sur un appareil, en silence.
    private struct Row: Codable {
        let uid: String?
        let id: UUID
        let game: String
        let x: Double
        let y: Double
        let title: String
        let note: String
        let icon: String
        let isDone: Bool
        let createdAt: Date
        let updatedAt: Date
        let deletedAt: Date?

        enum CodingKeys: String, CodingKey {
            case uid
            case id
            case game
            case x
            case y
            case title
            case note
            case icon
            case isDone = "is_done"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
            case deletedAt = "deleted_at"
        }
    }

    private let client: SupabaseClient?

    init(client: SupabaseClient? = SupabaseClientProvider.shared) {
        self.client = client
    }

    func upload(_ item: PersonalPinSyncItem) async {
        guard let client, let uid = client.auth.currentUser?.id.uuidString else { return }
        let row = Row(
            uid: uid, id: item.id, game: item.game, x: item.x, y: item.y,
            title: item.title, note: item.note, icon: item.icon, isDone: item.isDone,
            createdAt: item.createdAt, updatedAt: item.updatedAt, deletedAt: item.deletedAt
        )
        do {
            try await client.from("personal_pins").upsert(row, onConflict: "uid,id").execute()
        } catch {
            print("SupabasePersonalPinSync: envoi impossible pour \(item.id) — \(error)")
        }
    }

    func fetchAll(uid: String) async -> [PersonalPinSyncItem] {
        guard let client else { return [] }
        do {
            let rows: [Row] = try await client
                .from("personal_pins")
                .select("uid,id,game,x,y,title,note,icon,is_done,created_at,updated_at,deleted_at")
                .eq("uid", value: uid)
                .execute()
                .value
            return rows.map {
                PersonalPinSyncItem(
                    id: $0.id, game: $0.game, x: $0.x, y: $0.y,
                    title: $0.title, note: $0.note, icon: $0.icon, isDone: $0.isDone,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt, deletedAt: $0.deletedAt
                )
            }
        } catch {
            print("SupabasePersonalPinSync: lecture impossible — \(error)")
            return []
        }
    }
}
```

- [ ] **Step 3 : Compiler**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -20
```

Attendu : compilation propre.

- [ ] **Step 4 : Commit**

```sh
git add NeonCompass/Core/Sync/
git commit -m "feat(sync): le protocole du carnet et son transport Supabase"
```

---

## Task 3 : La pierre tombale

**Files:**
- Modify: `NeonCompass/Core/Map/PersonalPinStore.swift`
- Modify: `NeonCompassTests/Map/PersonalPinStoreTests.swift`

**Interfaces:**
- `PersonalPinStore.delete(_:)` cesse d'effacer et pose `deletedAt`.
- `PersonalPinStore.pins` ne contient plus que les vivantes ; `totalCount` et le plafond suivent.

- [ ] **Step 1 : Écrire les tests qui échouent**

Ajouter dans `NeonCompassTests/Map/PersonalPinStoreTests.swift` :

```swift
    // MARK: - Pierre tombale

    /// La bascule du chantier 2 : supprimer n'efface plus, ça DATE. Sans la
    /// tombe, effacer sur l'iPhone ne se propagerait jamais — l'iPad possède
    /// encore l'épingle et rien ne lui dirait qu'elle a été retirée.
    @Test func deletingLeavesATombstoneBehind() {
        let context = makeContext()
        let store = PersonalPinStore(modelContext: context)
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        store.delete(pin)
        #expect(store.pins.isEmpty, "une épingle supprimée ne doit plus être visible")
        let all = (try? context.fetch(FetchDescriptor<PersonalPin>())) ?? []
        #expect(all.count == 1, "la ligne doit subsister")
        #expect(all[0].deletedAt != nil, "elle doit porter sa date de suppression")
    }

    /// Une tombe ne se compte pas dans le plafond : sinon supprimer une épingle
    /// ne libèrerait jamais la place qu'elle occupait.
    @Test func tombstonesDoNotCountTowardTheCap() {
        let store = PersonalPinStore(modelContext: makeContext())
        for _ in 0..<PersonalPinStore.freeCap {
            store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: false)
        }
        #expect(store.isAtCap(isProEntitled: false))
        store.delete(store.pins[0])
        #expect(!store.isAtCap(isProEntitled: false), "supprimer doit libérer une place")
        #expect(store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: false) != nil)
    }

    /// Et une tombe ne réapparaît pas non plus par la carte.
    @Test func tombstonesAreInvisibleToTheMap() {
        let store = PersonalPinStore(modelContext: makeContext())
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        store.delete(pin)
        #expect(store.pins(for: .reference).isEmpty)
    }
```

- [ ] **Step 2 : Lancer pour vérifier l'échec**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/PersonalPinStoreTests 2>&1 | grep -E "✘|error:|Test run with"
```

Attendu : `deletingLeavesATombstoneBehind` échoue sur `all.count == 1` (la ligne a été physiquement effacée).

- [ ] **Step 3 : Basculer la suppression**

Dans `NeonCompass/Core/Map/PersonalPinStore.swift`, remplacer `refresh()` et `delete(_:)` :

```swift
    /// Relit le disque, **tombes exclues**.
    ///
    /// Le filtre est ici, en un seul endroit, et non à chaque site de lecture :
    /// c'est ce qui garantit qu'aucun chemin ne peut oublier de l'appliquer et
    /// faire réapparaître une épingle effacée. `pins` ne contient donc que des
    /// vivantes, et tout ce qui en dérive — `pins(for:)`, le décompte du
    /// plafond — en hérite sans y penser.
    func refresh() {
        let descriptor = FetchDescriptor<PersonalPin>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        pins = (try? modelContext.fetch(descriptor)) ?? []
        generation &+= 1
    }
```

```swift
    /// Suppression LOGIQUE. Un `delete` local ne se propage pas : sans la tombe,
    /// une épingle effacée sur l'iPhone reviendrait depuis l'iPad à la
    /// resynchronisation suivante, puisque l'iPad la possède encore et que rien
    /// ne lui dirait qu'elle a été retirée.
    ///
    /// On ne purge jamais ces lignes : purger rouvre le danger classique — un
    /// appareil resté hors ligne au-delà de la fenêtre n'a pas vu la tombe et
    /// RESSUSCITE l'épingle. Le coût de tout garder est dérisoire, une ligne
    /// d'environ deux cents octets.
    func delete(_ pin: PersonalPin) {
        let now = Date.now
        pin.deletedAt = now
        pin.updatedAt = now
        save()
        refresh()
        upload(pin)
    }
```

(`upload(_:)` est ajouté à la tâche 4 ; jusque-là, retirer cette ligne et la remettre alors. Pour éviter l'aller-retour, poser dès maintenant un `private func upload(_ pin: PersonalPin) {}` vide, complété en tâche 4.)

- [ ] **Step 4 : Lancer les tests**

```sh
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/PersonalPinStoreTests 2>&1 | grep -E "✘|error:|Test run with"
```

Attendu : les quinze tests passent.

- [ ] **Step 5 : Commit**

```sh
git status
git add -A
git commit -m "feat(carte): supprimer une épingle la date au lieu de l'effacer"
```

---

## Task 4 : Téléversement et réconciliation

**Files:**
- Modify: `NeonCompass/Core/Map/PersonalPinStore.swift`
- Create: `NeonCompassTests/Sync/PersonalPinReconciliationTests.swift`

**Interfaces:**
- Produit :
  - `PersonalPinStore.attachSyncIfNeeded(_ sync: PersonalPinSyncing) -> Bool` (`@discardableResult`)
  - `PersonalPinStore.reconcile(with remoteItems: [PersonalPinSyncItem])`
  - `PersonalPinStore.uploadEverything()` — pousse ce que le distant ignore.

- [ ] **Step 1 : Écrire les tests qui échouent**

Créer `NeonCompassTests/Sync/PersonalPinReconciliationTests.swift` :

```swift
import Foundation
import SwiftData
import Testing
@testable import NeonCompass

/// Espion de transport : retient ce qui monte, rend ce qu'on lui a posé.
private actor FakePersonalPinSync: PersonalPinSyncing {
    private(set) var uploaded: [PersonalPinSyncItem] = []
    private var remote: [PersonalPinSyncItem] = []

    init(remote: [PersonalPinSyncItem] = []) { self.remote = remote }

    func upload(_ item: PersonalPinSyncItem) async { uploaded.append(item) }
    func fetchAll(uid: String) async -> [PersonalPinSyncItem] { remote }
    func uploadedItems() async -> [PersonalPinSyncItem] { uploaded }
}

@MainActor
struct PersonalPinReconciliationTests {
    private func makeContext() -> ModelContext {
        let schema = Schema([FoundEntry.self, PersonalPin.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func item(
        id: UUID = UUID(), title: String = "Distante", isDone: Bool = false,
        updatedAt: Date, deletedAt: Date? = nil
    ) -> PersonalPinSyncItem {
        PersonalPinSyncItem(
            id: id, game: Game.reference.rawValue, x: 0.4, y: 0.4,
            title: title, note: "", icon: PersonalPinIcon.marker.rawValue,
            isDone: isDone, createdAt: updatedAt, updatedAt: updatedAt, deletedAt: deletedAt
        )
    }

    /// Le cas qui vend Pro : une épingle posée sur l'iPad apparaît sur l'iPhone.
    @Test func anUnknownRemotePinIsAdopted() {
        let store = PersonalPinStore(modelContext: makeContext())
        store.reconcile(with: [item(title: "Posée sur l'iPad", updatedAt: .now)])
        #expect(store.pins.count == 1)
        #expect(store.pins[0].title == "Posée sur l'iPad")
    }

    /// Dernière-écriture-gagne, sens distant.
    @Test func aNewerRemoteEditWins() {
        let store = PersonalPinStore(modelContext: makeContext())
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        pin.updatedAt = Date.now.addingTimeInterval(-120)
        store.reconcile(with: [item(id: pin.id, title: "Renommée ailleurs", updatedAt: .now)])
        #expect(store.pins[0].title == "Renommée ailleurs")
    }

    /// Dernière-écriture-gagne, sens local. Sans cette borne, un appareil resté
    /// hors ligne longtemps écraserait le travail récent de l'autre.
    @Test func anOlderRemoteEditLoses() {
        let store = PersonalPinStore(modelContext: makeContext())
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        store.update(pin, title: "Écrite ici", note: "")
        store.reconcile(with: [item(id: pin.id, title: "Vieille version",
                                    updatedAt: Date.now.addingTimeInterval(-3600))])
        #expect(store.pins[0].title == "Écrite ici")
    }

    /// La tombe voyage : effacer sur l'iPad efface sur l'iPhone.
    @Test func aRemoteTombstoneHidesTheLocalPin() {
        let store = PersonalPinStore(modelContext: makeContext())
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        pin.updatedAt = Date.now.addingTimeInterval(-120)
        let now = Date.now
        store.reconcile(with: [item(id: pin.id, updatedAt: now, deletedAt: now)])
        #expect(store.pins.isEmpty)
    }

    /// Une tombe distante qu'on n'a jamais connue ne crée RIEN. Adopter la ligne
    /// remplirait le disque de fantômes, un par épingle jamais vue.
    @Test func anUnknownRemoteTombstoneCreatesNothing() {
        let context = makeContext()
        let store = PersonalPinStore(modelContext: context)
        let now = Date.now
        store.reconcile(with: [item(updatedAt: now, deletedAt: now)])
        #expect(store.pins.isEmpty)
        let all = (try? context.fetch(FetchDescriptor<PersonalPin>())) ?? []
        #expect(all.isEmpty, "aucune ligne ne doit être créée pour une tombe inconnue")
    }

    /// Réconcilier fait avancer la génération : la carte doit redessiner ce qui
    /// vient d'arriver, sinon les épingles de l'autre appareil restent
    /// invisibles jusqu'au prochain changement.
    @Test func reconcilingAdvancesTheGeneration() {
        let store = PersonalPinStore(modelContext: makeContext())
        let before = store.generation
        store.reconcile(with: [item(updatedAt: .now)])
        #expect(store.generation != before)
    }

    /// Ce que le distant ignore doit monter : une épingle posée hors ligne n'a
    /// jamais été téléversée, et rien d'autre ne la pousserait.
    @Test func localOnlyPinsAreUploaded() async {
        let store = PersonalPinStore(modelContext: makeContext())
        let sync = FakePersonalPinSync()
        store.attachSyncIfNeeded(sync)
        let pin = store.create(at: NormalizedPoint(x: 0.5, y: 0.5), game: .reference, isProEntitled: true)!
        store.reconcile(with: [])
        // Laisse les tâches de téléversement s'exécuter.
        try? await Task.sleep(for: .milliseconds(200))
        let uploaded = await sync.uploadedItems()
        #expect(uploaded.contains { $0.id == pin.id })
    }

    /// La synchro ne s'attache qu'une fois : `MapScreen` la propose à chaque
    /// apparition pour rattraper la course du droit Pro, et ça ne doit pas
    /// remplacer celle qui travaille déjà.
    @Test func attachingIsIdempotent() {
        let store = PersonalPinStore(modelContext: makeContext())
        #expect(store.attachSyncIfNeeded(FakePersonalPinSync()))
        #expect(!store.attachSyncIfNeeded(FakePersonalPinSync()))
    }
}
```

- [ ] **Step 2 : Lancer pour vérifier l'échec**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/PersonalPinReconciliationTests 2>&1 | grep -E "error:|Test run with"
```

Attendu : ÉCHEC de compilation — `value of type 'PersonalPinStore' has no member 'reconcile'`.

- [ ] **Step 3 : Ajouter la synchro au magasin**

Dans `NeonCompass/Core/Map/PersonalPinStore.swift`, ajouter le champ auprès de `modelContext` :

```swift
    /// Nil tant que le droit Pro et le compte ne sont pas tous deux acquis. Le
    /// magasin ne les vérifie pas lui-même — il ne connaît ni
    /// `ProEntitlementModel` ni `AuthModel`, c'est ce qui le laisse testable
    /// sans StoreKit ni réseau. C'est `MapScreen` qui décide de l'attacher.
    private var sync: PersonalPinSyncing?
```

Ajouter en fin de classe :

```swift
    // MARK: - Synchronisation (Pro + connecté)

    /// Attache la synchro après coup si elle ne l'était pas déjà.
    ///
    /// Après coup, et pas à la construction : le magasin est bâti dans
    /// `NeonCompassApp`, avant que `ProEntitlementModel.refresh()` n'ait
    /// répondu. Sans ce rattrapage, un abonné verrait son carnet rester local
    /// jusqu'au prochain lancement.
    ///
    /// Renvoie si l'appel a effectivement attaché, pour que l'appelant sache
    /// qu'il lui reste à déclencher la première lecture.
    @discardableResult
    func attachSyncIfNeeded(_ sync: PersonalPinSyncing) -> Bool {
        guard self.sync == nil else { return false }
        self.sync = sync
        return true
    }

    /// Réconciliation dernière-écriture-gagne, ÉPINGLE PAR ÉPINGLE.
    ///
    /// Par épingle et non en bloc : un appareil resté hors ligne longtemps
    /// écraserait sinon tout le carnet de l'autre en se resynchronisant. C'est
    /// le même raisonnement que `FoundStore.reconcile`, et la même règle.
    ///
    /// Les tombes distantes s'appliquent comme le reste — c'est tout leur
    /// intérêt — mais une tombe qu'on n'a jamais connue ne crée RIEN : adopter
    /// la ligne remplirait le disque de fantômes, un par épingle jamais vue.
    func reconcile(with remoteItems: [PersonalPinSyncItem]) {
        let all = (try? modelContext.fetch(FetchDescriptor<PersonalPin>())) ?? []
        var byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

        for item in remoteItems {
            if let local = byID[item.id] {
                guard item.updatedAt > local.updatedAt else { continue }
                local.game = item.game
                local.x = item.x
                local.y = item.y
                local.title = item.title
                local.note = item.note
                local.icon = item.icon
                local.isDone = item.isDone
                local.updatedAt = item.updatedAt
                local.deletedAt = item.deletedAt
            } else {
                guard item.deletedAt == nil else { continue }
                let pin = PersonalPin(
                    id: item.id, x: item.x, y: item.y,
                    game: Game(rawValue: item.game) ?? .reference,
                    title: item.title, note: item.note,
                    icon: PersonalPinIcon.from(rawValue: item.icon),
                    isDone: item.isDone,
                    createdAt: item.createdAt, updatedAt: item.updatedAt
                )
                modelContext.insert(pin)
                byID[item.id] = pin
            }
        }
        save()
        refresh()

        // Ce que le distant ignore n'a jamais été téléversé — une épingle posée
        // hors ligne, ou créée avant que l'abonnement n'existe. Rien d'autre ne
        // la pousserait, faute d'un drapeau « à envoyer » sur le modèle.
        let known = Set(remoteItems.map(\.id))
        for pin in all where !known.contains(pin.id) { upload(pin) }
        for pin in pins where !known.contains(pin.id) { upload(pin) }
    }

    /// Téléverse une épingle, si et seulement si la synchro est attachée.
    ///
    /// Détaché sur une tâche : aucun appelant n'attend le réseau, et le magasin
    /// est `@MainActor`. L'instantané est pris ICI, sur le fil principal, parce
    /// que `PersonalPin` est une classe SwiftData — la passer à la tâche
    /// laisserait lire ses champs depuis un autre fil.
    private func upload(_ pin: PersonalPin) {
        guard let sync else { return }
        let item = PersonalPinSyncItem(
            id: pin.id, game: pin.game, x: pin.x, y: pin.y,
            title: pin.title, note: pin.note, icon: pin.icon, isDone: pin.isDone,
            createdAt: pin.createdAt, updatedAt: pin.updatedAt, deletedAt: pin.deletedAt
        )
        Task { await sync.upload(item) }
    }
```

Puis appeler `upload(pin)` à la fin de `create`, `update`, `setIcon`, `toggleDone` et `delete`.

- [ ] **Step 4 : Lancer les tests**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/PersonalPinReconciliationTests 2>&1 | grep -E "✘|error:|Test run with"
```

Attendu : les huit tests passent.

- [ ] **Step 5 : Commit**

```sh
git status
git add -A
git commit -m "feat(sync): le carnet monte ce qu'il écrit, et réconcilie par épingle"
```

---

## Task 5 : Le câblage, et la vérification complète

**Files:**
- Modify: `NeonCompass/Features/Map/MapScreen.swift`

- [ ] **Step 1 : Brancher la synchro**

Dans `NeonCompass/Features/Map/MapScreen.swift`, à la fin de `loadModel()`, dans le bloc `Task { … }` déjà présent, après la réconciliation de la progression :

```swift
            attachPinSyncIfNeeded()
```

Et ajouter, auprès de `reattachSyncIfNeeded()` :

```swift
    /// Même rattrapage que `reattachSyncIfNeeded`, pour le carnet : le magasin
    /// d'épingles est construit dans `NeonCompassApp`, donc bien avant que
    /// `ProEntitlementModel.refresh()` n'ait répondu. Sans ça un abonné verrait
    /// son carnet rester local jusqu'au prochain lancement.
    ///
    /// Sans effet et sans coût tant que le droit Pro ou le compte manquent, et
    /// idempotent ensuite — d'où l'appel depuis `.onAppear` en plus du
    /// chargement.
    private func attachPinSyncIfNeeded() {
        guard proEntitlementModel.isProEntitled, let userID = authModel.userID else { return }
        let sync = SupabasePersonalPinSync()
        guard personalPinStore.attachSyncIfNeeded(sync) else { return }
        Task {
            let remoteItems = await sync.fetchAll(uid: userID)
            personalPinStore.reconcile(with: remoteItems)
        }
    }
```

Et l'appeler depuis `.onAppear`, à côté de `reattachSyncIfNeeded()` :

```swift
        .onAppear {
            communityModel?.refreshBlockedAuthors()
            reattachSyncIfNeeded()
            attachPinSyncIfNeeded()
        }
```

- [ ] **Step 2 : Suite complète, deux appareils**

```sh
xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -30
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build 2>&1 | tail -10
Scripts/db-test.sh --stubs
```

Attendu : suite Swift verte, compilation iPad propre, tests SQL verts.

- [ ] **Step 3 : Commit**

```sh
git status
git checkout -- NeonCompass/Resources/Localizable.xcstrings 2>/dev/null || true
git add -A
git commit -m "feat(carte): le carnet des abonnés suit son propriétaire d'un appareil à l'autre"
```

---

## Self-review

**Couverture de la spec.** La section « Chantier 2 » de la spec énumère : table Supabase et RLS → tâche 1 ; révocation portée par la migration → tâche 1 ; entrée dans `privileges_test.sql` → tâche 1 ; protocole `PersonalPinSyncing` dans `Core/` → tâche 2 ; réconciliation dernière-écriture-gagne sur `updatedAt` → tâche 4 ; propagation des suppressions par `deletedAt` et bascule en pierre tombale → tâches 3 et 4. Le câblage Pro + connecté, que la spec pose comme contrainte globale, est en tâche 5.

**Cohérence des types.** `PersonalPinSyncItem` porte les mêmes champs en tâches 2 et 4. `PersonalPin.init` est appelé en tâche 4 avec la signature du chantier 1 — `id`, `x`, `y`, `game`, `title`, `note`, `icon`, `isDone`, `createdAt`, `updatedAt` — qui existe bien. `attachSyncIfNeeded` a le même nom et la même forme que celui de `MapModel`, délibérément.

**Points d'attention.**

1. `refresh()` filtre les tombes, donc `pins` ne les contient jamais — mais `reconcile` doit lire **toutes** les lignes, tombes comprises, pour ne pas recréer une épingle qu'il vient d'enterrer. D'où le `fetch` explicite en tête de `reconcile`, distinct de `pins`.
2. La boucle de téléversement final parcourt `all` **et** `pins` : `all` est l'instantané d'avant réconciliation, `pins` celui d'après. Les épingles adoptées du distant sont dans `known`, donc jamais renvoyées ; les seules à monter sont les locales que le distant ignorait.
3. `Scripts/db-test.sh --stubs` est le seul chemin disponible sur cette machine (Docker absent). Il est aveugle à ce que PostgREST vérifierait, mais il exécute bien RLS et les CHECK.
