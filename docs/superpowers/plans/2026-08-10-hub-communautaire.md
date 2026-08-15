# Hub communautaire — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter un annuaire de communautés avec promotion payante et événements dans l'onglet Social (v1.1).

**Architecture:** Troisième volet dans `SocialScreen`, adossé à deux nouvelles tables Supabase (`communities`, `community_events`). Promotion par abonnement StoreKit 2 mensuel (`community_spotlight`), synchronisé par App Store Server Notifications V2 via l'Edge Function existante. Lecture directe Supabase (pas ContentStore — ce n'est pas du contenu hébergé). Allumé par `app_config`.

**Tech Stack:** Swift 6 / SwiftUI / StoreKit 2 / Supabase (Postgres + RLS + Edge Functions) / Swift Testing

## Global Constraints

- iOS/iPadOS 26+, Swift 6, strict concurrency
- Localisation FR, EN, ES, IT, DE — toute clé dans le String Catalog
- Zéro texte libre en UGC — champs contraints uniquement
- Deux verrous par table (RLS + révocation de privilèges)
- Supabase derrière protocoles dans `Core/` — les features n'importent jamais `Supabase`
- Tests avec Swift Testing (`import Testing`), jamais XCTest
- `xcodegen generate` après toute création/suppression de fichier source

---

### Task 1: Migration Supabase — tables, RLS, trigger, privilèges

**Files:**
- Create: `supabase/migrations/20260810120000_communities.sql`
- Modify: `supabase/tests/privileges_test.sql` (ajouter `communities` et `community_events` aux listes attendues)

**Interfaces:**
- Produces: tables `communities` et `community_events` avec RLS et contraintes

- [ ] **Step 1: Écrire la migration**

```sql
-- supabase/migrations/20260810120000_communities.sql

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table communities (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null references auth.users(id) unique,
  name            text not null
                  check (length(name) between 3 and 30)
                  check (name ~ '^[a-zA-Z0-9 -]+$'),
  platform        text not null
                  check (platform in ('ps5','xbox','pc','cross-platform')),
  playstyles      text[] not null default '{}',
  languages       text[] not null default '{}',
  discord_invite  text check (discord_invite is null or discord_invite ~ '^https://discord\.gg/'),
  member_count    int not null default 1 check (member_count >= 1),
  server_address  text,
  promoted        bool not null default false,
  promoted_until  timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create table community_events (
  id             uuid primary key default gen_random_uuid(),
  community_id   uuid not null references communities(id) on delete cascade,
  event_type     text not null
                 check (event_type in (
                   'tournament','themed_night','recruitment',
                   'launch','training','other'
                 )),
  platform       text not null
                 check (platform in ('ps5','xbox','pc','cross-platform')),
  starts_at      timestamptz not null,
  ends_at        timestamptz,
  slots          int check (slots is null or slots > 0),
  created_at     timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table communities enable row level security;

create policy "communities_select" on communities
  for select using (true);
create policy "communities_insert" on communities
  for insert with check (auth.uid() = owner_id);
create policy "communities_update" on communities
  for update using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);
create policy "communities_delete" on communities
  for delete using (auth.uid() = owner_id);

alter table community_events enable row level security;

create policy "community_events_select" on community_events
  for select using (true);
create policy "community_events_insert" on community_events
  for insert with check (
    exists (
      select 1 from communities
      where id = community_id
        and owner_id = auth.uid()
        and promoted = true
    )
  );
create policy "community_events_delete" on community_events
  for delete using (
    exists (
      select 1 from communities
      where id = community_events.community_id
        and owner_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- Trigger — plafond de 3 événements actifs par communauté
-- ---------------------------------------------------------------------------

create or replace function enforce_community_event_limit()
returns trigger as $$
begin
  if (
    select count(*) from community_events
    where community_id = NEW.community_id
      and (ends_at is null or ends_at > now())
  ) >= 3 then
    raise exception 'community_event_limit_reached';
  end if;
  return NEW;
end;
$$ language plpgsql;

create trigger trg_community_event_limit
  before insert on community_events
  for each row execute function enforce_community_event_limit();

-- ---------------------------------------------------------------------------
-- Privilèges — révocation propre à cette migration
-- ---------------------------------------------------------------------------

revoke all on communities from anon, authenticated, public;
revoke all on community_events from anon, authenticated, public;
revoke all on function enforce_community_event_limit() from anon, authenticated, public;

grant select on communities to anon, authenticated;
grant select, insert, update, delete on community_events to authenticated;
grant select, insert, update, delete on communities to authenticated;
```

- [ ] **Step 2: Mettre à jour `privileges_test.sql`**

Ajouter `communities` et `community_events` aux listes de tables autorisées.

Dans le verrou 1, section « écriture directe » — ajouter les deux tables à la liste `not in` :
```sql
and table_name not in ('progression', 'push_tokens', 'editor_drafts', 'personal_pins',
                        'communities', 'community_events');
```

Dans la section `anon` — ajouter `communities` et `community_events` :
```sql
and table_name not in ('app_config', 'contributions', 'communities', 'community_events');
```

Dans la section `authenticated` — ajouter les deux :
```sql
and table_name not in ('app_config', 'contributions', 'leaderboard', 'profiles',
                        'votes', 'progression', 'push_tokens', 'editor_drafts',
                        'personal_pins', 'communities', 'community_events');
```

Dans le verrou 2 (fonctions), ajouter `enforce_community_event_limit` :
```sql
and not (grantee = 'authenticated'
         and routine_name in ('cast_vote', 'report_contribution', 'is_editor'));
```
Pas de changement ici : `enforce_community_event_limit` est un trigger, pas une RPC appelée par le client — elle a bien été révoquée de `anon`, `authenticated` et `public`.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260810120000_communities.sql supabase/tests/privileges_test.sql
git commit -m "feat(supabase): tables communities et community_events avec RLS et privilèges"
```

---

### Task 2: Modèles Swift — `Community`, `CommunityEvent`, repository

**Files:**
- Create: `NeonCompass/Core/Community/PlayerCommunity.swift`
- Create: `NeonCompass/Core/Community/CommunityEvent.swift`
- Create: `NeonCompass/Core/Community/CommunityRepository.swift`
- Create: `NeonCompass/Core/Community/SupabaseCommunityRepository.swift`
- Create: `NeonCompassTests/Community/PlayerCommunityTests.swift`
- Create: `NeonCompassTests/Community/CommunityEventTests.swift`

**Interfaces:**
- Produces: `PlayerCommunity` struct (Codable, Identifiable, Sendable), `CommunityEvent` struct, `CommunityRepository` protocol, `SupabaseCommunityRepository` impl

Le type s'appelle `PlayerCommunity` et non `Community` : `CommunityModel` existe déjà dans le projet (le modèle des contributions communautaires), et `Community` entrerait en collision. `PlayerCommunity` est sans ambiguïté.

- [ ] **Step 1: Écrire les tests de décodage**

```swift
// NeonCompassTests/Community/PlayerCommunityTests.swift
import Testing
import Foundation
@testable import NeonCompass

struct PlayerCommunityTests {
    @Test func decodesFromSupabaseJSON() throws {
        let json = """
        {
          "id": "550e8400-e29b-41d4-a716-446655440000",
          "owner_id": "660e8400-e29b-41d4-a716-446655440000",
          "name": "Neon Riders",
          "platform": "ps5",
          "playstyles": ["racing", "casual"],
          "languages": ["fr", "en"],
          "discord_invite": "https://discord.gg/abc123",
          "member_count": 42,
          "server_address": null,
          "promoted": true,
          "promoted_until": "2026-09-10T00:00:00+00:00",
          "created_at": "2026-08-10T12:00:00+00:00",
          "updated_at": "2026-08-10T12:00:00+00:00"
        }
        """.data(using: .utf8)!
        let community = try JSONDecoder().decode(PlayerCommunity.self, from: json)
        #expect(community.name == "Neon Riders")
        #expect(community.platform == .ps5)
        #expect(community.playstyles == [.racing, .casual])
        #expect(community.isPromoted)
        #expect(community.discordInvite == "https://discord.gg/abc123")
    }

    @Test func memberCountBracketRoundsDown() {
        #expect(PlayerCommunity.memberBracket(for: 1) == "1")
        #expect(PlayerCommunity.memberBracket(for: 9) == "1")
        #expect(PlayerCommunity.memberBracket(for: 10) == "10+")
        #expect(PlayerCommunity.memberBracket(for: 49) == "10+")
        #expect(PlayerCommunity.memberBracket(for: 50) == "50+")
        #expect(PlayerCommunity.memberBracket(for: 100) == "100+")
        #expect(PlayerCommunity.memberBracket(for: 500) == "500+")
        #expect(PlayerCommunity.memberBracket(for: 1000) == "500+")
    }

    @Test func unpromotedCommunityIsNotPromoted() throws {
        let json = """
        {
          "id": "550e8400-e29b-41d4-a716-446655440000",
          "owner_id": "660e8400-e29b-41d4-a716-446655440000",
          "name": "Chill Squad",
          "platform": "xbox",
          "playstyles": ["casual"],
          "languages": ["en"],
          "discord_invite": null,
          "member_count": 5,
          "server_address": null,
          "promoted": false,
          "promoted_until": null,
          "created_at": "2026-08-10T12:00:00+00:00",
          "updated_at": "2026-08-10T12:00:00+00:00"
        }
        """.data(using: .utf8)!
        let community = try JSONDecoder().decode(PlayerCommunity.self, from: json)
        #expect(!community.isPromoted)
    }
}
```

```swift
// NeonCompassTests/Community/CommunityEventTests.swift
import Testing
import Foundation
@testable import NeonCompass

struct CommunityEventTests {
    @Test func decodesFromSupabaseJSON() throws {
        let json = """
        {
          "id": "770e8400-e29b-41d4-a716-446655440000",
          "community_id": "550e8400-e29b-41d4-a716-446655440000",
          "event_type": "tournament",
          "platform": "ps5",
          "starts_at": "2026-08-15T20:00:00+00:00",
          "ends_at": "2026-08-15T23:00:00+00:00",
          "slots": 16,
          "created_at": "2026-08-10T12:00:00+00:00"
        }
        """.data(using: .utf8)!
        let event = try JSONDecoder().decode(CommunityEvent.self, from: json)
        #expect(event.eventType == .tournament)
        #expect(event.slots == 16)
    }

    @Test func eventWithoutEndDateDecodes() throws {
        let json = """
        {
          "id": "770e8400-e29b-41d4-a716-446655440000",
          "community_id": "550e8400-e29b-41d4-a716-446655440000",
          "event_type": "recruitment",
          "platform": "cross-platform",
          "starts_at": "2026-08-15T20:00:00+00:00",
          "ends_at": null,
          "slots": null,
          "created_at": "2026-08-10T12:00:00+00:00"
        }
        """.data(using: .utf8)!
        let event = try JSONDecoder().decode(CommunityEvent.self, from: json)
        #expect(event.endsAt == nil)
        #expect(event.slots == nil)
    }
}
```

- [ ] **Step 2: Implémenter les types**

```swift
// NeonCompass/Core/Community/PlayerCommunity.swift
import Foundation

enum CommunityPlatform: String, Codable, Sendable, CaseIterable, Identifiable {
    case ps5, xbox, pc
    case crossPlatform = "cross-platform"

    var id: String { rawValue }

    var localizationKey: String { "social.communities.platform.\(rawValue)" }
}

enum CommunityPlaystyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case rp, racing, heists, casual, competitive, exploration, creative

    var id: String { rawValue }

    var localizationKey: String { "social.communities.playstyle.\(rawValue)" }
}

struct PlayerCommunity: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let ownerID: String
    let name: String
    let platform: CommunityPlatform
    let playstyles: [CommunityPlaystyle]
    let languages: [String]
    let discordInvite: String?
    let memberCount: Int
    let serverAddress: String?
    let promoted: Bool
    let promotedUntil: String?
    let createdAt: String
    let updatedAt: String

    var isPromoted: Bool { promoted }

    static func memberBracket(for count: Int) -> String {
        switch count {
        case 500...: "500+"
        case 100...: "100+"
        case 50...: "50+"
        case 10...: "10+"
        default: "\(count)"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case name, platform, playstyles, languages
        case discordInvite = "discord_invite"
        case memberCount = "member_count"
        case serverAddress = "server_address"
        case promoted
        case promotedUntil = "promoted_until"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
```

```swift
// NeonCompass/Core/Community/CommunityEvent.swift
import Foundation

enum CommunityEventType: String, Codable, Sendable, CaseIterable, Identifiable {
    case tournament
    case themedNight = "themed_night"
    case recruitment
    case launch
    case training
    case other

    var id: String { rawValue }

    var localizationKey: String { "social.communities.eventType.\(rawValue)" }

    var systemImage: String {
        switch self {
        case .tournament: "trophy"
        case .themedNight: "moon.stars"
        case .recruitment: "person.badge.plus"
        case .launch: "party.popper"
        case .training: "figure.run"
        case .other: "calendar"
        }
    }
}

struct CommunityEvent: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let communityID: String
    let eventType: CommunityEventType
    let platform: CommunityPlatform
    let startsAt: String
    let endsAt: String?
    let slots: Int?
    let createdAt: String

    var startsAtDate: Date? { Contribution.parseTimestamp(startsAt) }
    var endsAtDate: Date? { Contribution.parseTimestamp(endsAt) }

    enum CodingKeys: String, CodingKey {
        case id
        case communityID = "community_id"
        case eventType = "event_type"
        case platform
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case slots
        case createdAt = "created_at"
    }
}
```

- [ ] **Step 3: Écrire le protocole et l'implémentation Supabase du repository**

```swift
// NeonCompass/Core/Community/CommunityRepository.swift
import Foundation

protocol CommunityListRepository: Sendable {
    func fetchAll() async throws -> [PlayerCommunity]
    func fetchUpcomingEvents() async throws -> [CommunityEvent]
    func createCommunity(_ draft: PlayerCommunityDraft) async throws -> PlayerCommunity
    func updateCommunity(id: String, draft: PlayerCommunityDraft) async throws
    func deleteCommunity(id: String) async throws
    func createEvent(_ draft: CommunityEventDraft, communityID: String) async throws
    func deleteEvent(id: String) async throws
}

struct PlayerCommunityDraft: Encodable, Sendable {
    let name: String
    let platform: CommunityPlatform
    let playstyles: [CommunityPlaystyle]
    let languages: [String]
    let discordInvite: String?
    let memberCount: Int

    enum CodingKeys: String, CodingKey {
        case name, platform, playstyles, languages
        case discordInvite = "discord_invite"
        case memberCount = "member_count"
    }
}

struct CommunityEventDraft: Encodable, Sendable {
    let eventType: CommunityEventType
    let platform: CommunityPlatform
    let startsAt: String
    let endsAt: String?
    let slots: Int?

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case platform
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case slots
    }
}
```

```swift
// NeonCompass/Core/Community/SupabaseCommunityRepository.swift
import Foundation
import Supabase

final class SupabaseCommunityListRepository: CommunityListRepository {
    private let client: SupabaseClient?

    init(client: SupabaseClient? = SupabaseClientProvider.shared) {
        self.client = client
    }

    func fetchAll() async throws -> [PlayerCommunity] {
        guard let client else { return [] }
        return try await client
            .from("communities")
            .select()
            .order("promoted", ascending: false)
            .order("promoted_until", ascending: false)
            .order("member_count", ascending: false)
            .execute()
            .value
    }

    func fetchUpcomingEvents() async throws -> [CommunityEvent] {
        guard let client else { return [] }
        return try await client
            .from("community_events")
            .select()
            .gte("starts_at", value: ISO8601DateFormatter().string(from: Date()))
            .order("starts_at", ascending: true)
            .limit(20)
            .execute()
            .value
    }

    func createCommunity(_ draft: PlayerCommunityDraft) async throws -> PlayerCommunity {
        guard let client else { throw CommunityError.notConfigured }
        return try await client
            .from("communities")
            .insert(draft)
            .select()
            .single()
            .execute()
            .value
    }

    func updateCommunity(id: String, draft: PlayerCommunityDraft) async throws {
        guard let client else { throw CommunityError.notConfigured }
        try await client
            .from("communities")
            .update(draft)
            .eq("id", value: id)
            .execute()
    }

    func deleteCommunity(id: String) async throws {
        guard let client else { throw CommunityError.notConfigured }
        try await client
            .from("communities")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    func createEvent(_ draft: CommunityEventDraft, communityID: String) async throws {
        guard let client else { throw CommunityError.notConfigured }
        struct Payload: Encodable {
            let communityID: String
            let eventType: CommunityEventType
            let platform: CommunityPlatform
            let startsAt: String
            let endsAt: String?
            let slots: Int?

            enum CodingKeys: String, CodingKey {
                case communityID = "community_id"
                case eventType = "event_type"
                case platform
                case startsAt = "starts_at"
                case endsAt = "ends_at"
                case slots
            }
        }
        try await client
            .from("community_events")
            .insert(Payload(
                communityID: communityID,
                eventType: draft.eventType,
                platform: draft.platform,
                startsAt: draft.startsAt,
                endsAt: draft.endsAt,
                slots: draft.slots
            ))
            .execute()
    }

    func deleteEvent(id: String) async throws {
        guard let client else { throw CommunityError.notConfigured }
        try await client
            .from("community_events")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}

enum CommunityError: Error {
    case notConfigured
    case eventLimitReached
}
```

- [ ] **Step 4: Lancer xcodegen et les tests**

```bash
cd /Users/antoine/gta_project && xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/PlayerCommunityTests
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/CommunityEventTests
```

- [ ] **Step 5: Commit**

```bash
git add NeonCompass/Core/Community/PlayerCommunity.swift \
        NeonCompass/Core/Community/CommunityEvent.swift \
        NeonCompass/Core/Community/CommunityRepository.swift \
        NeonCompass/Core/Community/SupabaseCommunityRepository.swift \
        NeonCompassTests/Community/PlayerCommunityTests.swift \
        NeonCompassTests/Community/CommunityEventTests.swift
git commit -m "feat: modèles PlayerCommunity, CommunityEvent et repository Supabase"
```

---

### Task 3: `CommunitiesModel` — le view model du volet

**Files:**
- Create: `NeonCompass/Features/Social/CommunitiesModel.swift`
- Create: `NeonCompassTests/Social/CommunitiesModelTests.swift`

**Interfaces:**
- Consumes: `CommunityListRepository`, `PlayerCommunity`, `CommunityEvent`
- Produces: `CommunitiesModel` — `@Observable @MainActor`, expose `communities`, `promotedCommunities`, `upcomingEvents`, filtres

- [ ] **Step 1: Écrire les tests**

```swift
// NeonCompassTests/Social/CommunitiesModelTests.swift
import Testing
import Foundation
@testable import NeonCompass

@MainActor
struct CommunitiesModelTests {
    private func community(
        id: String = "a",
        name: String = "Test",
        platform: CommunityPlatform = .ps5,
        playstyles: [CommunityPlaystyle] = [.casual],
        promoted: Bool = false,
        memberCount: Int = 10
    ) -> PlayerCommunity {
        PlayerCommunity(
            id: id, ownerID: "owner", name: name, platform: platform,
            playstyles: playstyles, languages: ["en"],
            discordInvite: nil, memberCount: memberCount,
            serverAddress: nil, promoted: promoted, promotedUntil: nil,
            createdAt: "2026-08-10T00:00:00Z", updatedAt: "2026-08-10T00:00:00Z"
        )
    }

    @Test func promotedCommunitiesAreFiltered() {
        let all = [
            community(id: "a", promoted: true),
            community(id: "b", promoted: false),
            community(id: "c", promoted: true),
        ]
        let model = CommunitiesModel(repository: FakeCommunityRepository(communities: all))
        model.communities = all
        #expect(model.promotedCommunities.count == 2)
    }

    @Test func filterByPlatformWorks() {
        let all = [
            community(id: "a", platform: .ps5),
            community(id: "b", platform: .xbox),
            community(id: "c", platform: .ps5),
        ]
        let model = CommunitiesModel(repository: FakeCommunityRepository(communities: all))
        model.communities = all
        model.platformFilter = .ps5
        #expect(model.filteredCommunities.count == 2)
    }

    @Test func filterByPlaystyleWorks() {
        let all = [
            community(id: "a", playstyles: [.racing, .casual]),
            community(id: "b", playstyles: [.rp]),
            community(id: "c", playstyles: [.casual]),
        ]
        let model = CommunitiesModel(repository: FakeCommunityRepository(communities: all))
        model.communities = all
        model.playstyleFilter = .casual
        #expect(model.filteredCommunities.count == 2)
    }

    @Test func noFilterShowsAll() {
        let all = [community(id: "a"), community(id: "b")]
        let model = CommunitiesModel(repository: FakeCommunityRepository(communities: all))
        model.communities = all
        #expect(model.filteredCommunities.count == 2)
    }
}

final class FakeCommunityRepository: CommunityListRepository, @unchecked Sendable {
    var communities: [PlayerCommunity]
    var events: [CommunityEvent]

    init(communities: [PlayerCommunity] = [], events: [CommunityEvent] = []) {
        self.communities = communities
        self.events = events
    }

    func fetchAll() async throws -> [PlayerCommunity] { communities }
    func fetchUpcomingEvents() async throws -> [CommunityEvent] { events }
    func createCommunity(_ draft: PlayerCommunityDraft) async throws -> PlayerCommunity {
        fatalError("not tested here")
    }
    func updateCommunity(id: String, draft: PlayerCommunityDraft) async throws {}
    func deleteCommunity(id: String) async throws {}
    func createEvent(_ draft: CommunityEventDraft, communityID: String) async throws {}
    func deleteEvent(id: String) async throws {}
}
```

- [ ] **Step 2: Implémenter `CommunitiesModel`**

```swift
// NeonCompass/Features/Social/CommunitiesModel.swift
import Foundation
import Observation

@Observable
@MainActor
final class CommunitiesModel {
    var communities: [PlayerCommunity] = []
    var upcomingEvents: [CommunityEvent] = []
    var platformFilter: CommunityPlatform?
    var playstyleFilter: CommunityPlaystyle?

    private let repository: any CommunityListRepository

    init(repository: any CommunityListRepository = SupabaseCommunityListRepository()) {
        self.repository = repository
    }

    var promotedCommunities: [PlayerCommunity] {
        communities.filter(\.isPromoted)
    }

    var filteredCommunities: [PlayerCommunity] {
        communities.filter { community in
            if let pf = platformFilter, community.platform != pf { return false }
            if let sf = playstyleFilter, !community.playstyles.contains(sf) { return false }
            return true
        }
    }

    func load() async {
        communities = (try? await repository.fetchAll()) ?? []
        upcomingEvents = (try? await repository.fetchUpcomingEvents()) ?? []
    }

    func createCommunity(_ draft: PlayerCommunityDraft) async throws {
        let created = try await repository.createCommunity(draft)
        communities.insert(created, at: 0)
    }

    func deleteCommunity(id: String) async throws {
        try await repository.deleteCommunity(id: id)
        communities.removeAll { $0.id == id }
    }

    func createEvent(_ draft: CommunityEventDraft, communityID: String) async throws {
        try await repository.createEvent(draft, communityID: communityID)
        upcomingEvents = (try? await repository.fetchUpcomingEvents()) ?? []
    }

    func deleteEvent(id: String) async throws {
        try await repository.deleteEvent(id: id)
        upcomingEvents.removeAll { $0.id == id }
    }
}
```

- [ ] **Step 3: xcodegen + tests**

```bash
cd /Users/antoine/gta_project && xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/CommunitiesModelTests
```

- [ ] **Step 4: Commit**

```bash
git add NeonCompass/Features/Social/CommunitiesModel.swift \
        NeonCompassTests/Social/CommunitiesModelTests.swift
git commit -m "feat: CommunitiesModel — filtrage, chargement, CRUD communautés"
```

---

### Task 4: `app_config` — clé de portail communautés

**Files:**
- Modify: `NeonCompass/Core/Config/SupabaseAppConfig.swift` (ajouter la clé)

**Interfaces:**
- Produces: `AppConfigKey.communityHubEnabled`

- [ ] **Step 1: Ajouter la clé**

Dans `AppConfigKey` à la fin de l'enum :
```swift
static let communityHubEnabled = "communityHubEnabled"
```

- [ ] **Step 2: Commit**

```bash
git add NeonCompass/Core/Config/SupabaseAppConfig.swift
git commit -m "feat: clé app_config communityHubEnabled"
```

---

### Task 5: UI — `CommunitiesPanel`, `CommunityCard`, `CommunityRow`, `CommunityDetailSheet`

**Files:**
- Create: `NeonCompass/Features/Social/CommunitiesPanel.swift`
- Create: `NeonCompass/Features/Social/CommunityCard.swift`
- Create: `NeonCompass/Features/Social/CommunityRow.swift`
- Create: `NeonCompass/Features/Social/CommunityDetailSheet.swift`
- Create: `NeonCompass/Features/Social/CommunityEventRow.swift`

**Interfaces:**
- Consumes: `CommunitiesModel`, `PlayerCommunity`, `CommunityEvent`, `CommunityPlatform`, `CommunityPlaystyle`, `CommunityEventType`

- [ ] **Step 1: `CommunityCard` — carte du carrousel promu**

```swift
// NeonCompass/Features/Social/CommunityCard.swift
import SwiftUI

struct CommunityCard: View {
    let community: PlayerCommunity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: community.name)
                    .font(NCTypography.cardTitle)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(NCColor.neonCyan)
            }

            HStack(spacing: 6) {
                Text(LocalizedStringKey(community.platform.localizationKey))
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.6))
                Text("·")
                    .foregroundStyle(.white.opacity(0.3))
                Text(verbatim: PlayerCommunity.memberBracket(for: community.memberCount))
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.6))
            }

            HStack(spacing: 4) {
                ForEach(community.playstyles.prefix(3)) { style in
                    Text(LocalizedStringKey(style.localizationKey))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.1), in: .capsule)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(16)
        .frame(width: 220, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}
```

- [ ] **Step 2: `CommunityRow` — ligne de la liste complète**

```swift
// NeonCompass/Features/Social/CommunityRow.swift
import SwiftUI

struct CommunityRow: View {
    let community: PlayerCommunity

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(verbatim: community.name)
                        .font(NCTypography.body)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if community.isPromoted {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(NCColor.neonCyan)
                    }
                }
                HStack(spacing: 4) {
                    Text(LocalizedStringKey(community.platform.localizationKey))
                        .font(NCTypography.cardMeta)
                        .foregroundStyle(.white.opacity(0.5))
                    ForEach(community.playstyles.prefix(2)) { style in
                        Text(LocalizedStringKey(style.localizationKey))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            Spacer()
            if community.discordInvite != nil {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
            }
            Text(verbatim: PlayerCommunity.memberBracket(for: community.memberCount))
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white.opacity(0.4))
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
    }
}
```

- [ ] **Step 3: `CommunityEventRow`**

```swift
// NeonCompass/Features/Social/CommunityEventRow.swift
import SwiftUI

struct CommunityEventRow: View {
    let event: CommunityEvent
    let communityName: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.eventType.systemImage)
                .font(.body)
                .foregroundStyle(NCColor.neonCyan)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: communityName)
                    .font(NCTypography.body)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(event.eventType.localizationKey))
                        .font(NCTypography.cardMeta)
                        .foregroundStyle(.white.opacity(0.5))
                    if let date = event.startsAtDate {
                        Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(NCTypography.cardMeta)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            Spacer()
            Text(LocalizedStringKey(event.platform.localizationKey))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
    }
}
```

- [ ] **Step 4: `CommunityDetailSheet`**

```swift
// NeonCompass/Features/Social/CommunityDetailSheet.swift
import SwiftUI

struct CommunityDetailSheet: View {
    let community: PlayerCommunity
    let events: [CommunityEvent]
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if !events.isEmpty { eventsSection }
                    discordButton
                }
                .padding(20)
            }
            .background(NCColor.nightSky.ignoresSafeArea())
            .navigationTitle(community.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("social.communities.detail.close") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(LocalizedStringKey(community.platform.localizationKey))
                    .font(NCTypography.cardMeta)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.1), in: .capsule)
                Text(verbatim: PlayerCommunity.memberBracket(for: community.memberCount))
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.6))
                if community.isPromoted {
                    Label("Spotlight", systemImage: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(NCColor.neonCyan)
                }
            }
            .foregroundStyle(.white.opacity(0.7))

            HStack(spacing: 4) {
                ForEach(community.playstyles) { style in
                    Text(LocalizedStringKey(style.localizationKey))
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.08), in: .capsule)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    @ViewBuilder
    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("social.communities.detail.events")
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)

            ForEach(events) { event in
                CommunityEventRow(event: event, communityName: community.name)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    @ViewBuilder
    private var discordButton: some View {
        if let invite = community.discordInvite, let url = URL(string: invite) {
            Button {
                openURL(url)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .foregroundStyle(NCColor.neonCyan)
                    Text("social.communities.detail.joinDiscord")
                        .font(NCTypography.body)
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
    }
}
```

- [ ] **Step 5: `CommunitiesPanel`**

```swift
// NeonCompass/Features/Social/CommunitiesPanel.swift
import SwiftUI

struct CommunitiesPanel: View {
    let model: CommunitiesModel

    @State private var selectedCommunity: PlayerCommunity?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !model.promotedCommunities.isEmpty {
                spotlight
            }

            if !model.upcomingEvents.isEmpty {
                eventsPreview
            }

            filters
            communityList
        }
        .sheet(item: $selectedCommunity) { community in
            CommunityDetailSheet(
                community: community,
                events: model.upcomingEvents.filter { $0.communityID == community.id }
            )
        }
    }

    private var spotlight: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("social.communities.spotlight")
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(model.promotedCommunities.prefix(5)) { community in
                        Button { selectedCommunity = community } label: {
                            CommunityCard(community: community)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var eventsPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("social.communities.upcomingEvents")
                .font(NCTypography.cardMeta)
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)

            VStack(spacing: 0) {
                ForEach(model.upcomingEvents.prefix(5)) { event in
                    let name = model.communities.first { $0.id == event.communityID }?.name ?? ""
                    Button { selectCommunity(for: event) } label: {
                        CommunityEventRow(event: event, communityName: name)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(
                    label: "social.communities.filter.platform",
                    value: model.platformFilter?.localizationKey,
                    onClear: { model.platformFilter = nil }
                )
                filterChip(
                    label: "social.communities.filter.playstyle",
                    value: model.playstyleFilter?.localizationKey,
                    onClear: { model.playstyleFilter = nil }
                )
            }
        }
    }

    private func filterChip(label: LocalizedStringKey, value: String?, onClear: @escaping () -> Void) -> some View {
        Menu {
            if label == "social.communities.filter.platform" {
                ForEach(CommunityPlatform.allCases) { p in
                    Button { model.platformFilter = p } label: {
                        Text(LocalizedStringKey(p.localizationKey))
                    }
                }
            } else {
                ForEach(CommunityPlaystyle.allCases) { s in
                    Button { model.playstyleFilter = s } label: {
                        Text(LocalizedStringKey(s.localizationKey))
                    }
                }
            }
            if value != nil {
                Divider()
                Button(role: .destructive, action: onClear) {
                    Text("social.communities.filter.clear")
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let value {
                    Text(LocalizedStringKey(value))
                } else {
                    Text(label)
                }
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .font(NCTypography.cardMeta)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(value != nil ? NCColor.neonCyan : .white.opacity(0.6))
            .background(.white.opacity(value != nil ? 0.12 : 0.06), in: .capsule)
        }
    }

    private var communityList: some View {
        LazyVStack(spacing: 0) {
            ForEach(model.filteredCommunities) { community in
                Button { selectedCommunity = community } label: {
                    CommunityRow(community: community)
                }
                .buttonStyle(.plain)
            }

            if model.filteredCommunities.isEmpty {
                Text("social.communities.empty")
                    .font(NCTypography.body)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            }
        }
    }

    private func selectCommunity(for event: CommunityEvent) {
        selectedCommunity = model.communities.first { $0.id == event.communityID }
    }
}
```

- [ ] **Step 6: xcodegen + build**

```bash
cd /Users/antoine/gta_project && xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build
```

- [ ] **Step 7: Commit**

```bash
git add NeonCompass/Features/Social/CommunitiesPanel.swift \
        NeonCompass/Features/Social/CommunityCard.swift \
        NeonCompass/Features/Social/CommunityRow.swift \
        NeonCompass/Features/Social/CommunityDetailSheet.swift \
        NeonCompass/Features/Social/CommunityEventRow.swift
git commit -m "feat: UI du volet communautés — panel, cards, rows, detail sheet"
```

---

### Task 6: Intégration dans `SocialScreen` — troisième volet

**Files:**
- Modify: `NeonCompass/Features/Social/SocialScreen.swift`

**Interfaces:**
- Consumes: `CommunitiesModel`, `CommunitiesPanel`, `AppConfigKey.communityHubEnabled`

- [ ] **Step 1: Ajouter le cas `.communities` au `Panel`**

Dans `SocialScreen`, ajouter le cas à l'enum `Panel` :
```swift
private enum Panel: String, CaseIterable, Identifiable {
    case events, proposals, communities

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .events: "social.panel.events"
        case .proposals: "social.panel.proposals"
        case .communities: "social.panel.communities"
        }
    }
}
```

- [ ] **Step 2: Ajouter l'état `communitiesModel` et le drapeau config**

Ajouter les propriétés :
```swift
@State private var communitiesModel: CommunitiesModel?
@State private var communityHubEnabled = false
```

- [ ] **Step 3: Modifier `availablePanels` pour inclure `.communities`**

```swift
private var availablePanels: [Panel] {
    var panels: [Panel] = [.events]
    if serverFeatures.isEnabled { panels.append(.proposals) }
    if serverFeatures.isEnabled && communityHubEnabled { panels.append(.communities) }
    return panels
}
```

- [ ] **Step 4: Ajouter le `case .communities` dans le `switch` du body**

Dans `content(_:)`, dans le `switch` :
```swift
case .communities:
    if let communitiesModel {
        CommunitiesPanel(model: communitiesModel)
    } else {
        ProgressView()
    }
```

- [ ] **Step 5: Charger la configuration et le modèle**

Ajouter au `.task` existant, après `loadModel()` :
```swift
communityHubEnabled = (try? await SupabaseAppConfig.shared.bool(
    AppConfigKey.communityHubEnabled, default: false
)) ?? false
```

Ajouter un `.task(id:)` pour le volet communities :
```swift
.task(id: panel) {
    guard panel == .communities else { return }
    if communitiesModel == nil {
        communitiesModel = CommunitiesModel()
    }
    await communitiesModel?.load()
}
```

Ajouter au `refreshable` :
```swift
await communitiesModel?.load()
```

- [ ] **Step 6: Build + test**

```bash
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build
```

- [ ] **Step 7: Commit**

```bash
git add NeonCompass/Features/Social/SocialScreen.swift
git commit -m "feat: volet communautés intégré dans SocialScreen (gardé par app_config)"
```

---

### Task 7: `CreateCommunitySheet` — formulaire de création

**Files:**
- Create: `NeonCompass/Features/Social/CreateCommunitySheet.swift`
- Modify: `NeonCompass/Features/Social/CommunitiesPanel.swift` (ajouter le bouton de création)

**Interfaces:**
- Consumes: `CommunitiesModel`, `PlayerCommunityDraft`, `CommunityPlatform`, `CommunityPlaystyle`

- [ ] **Step 1: Créer le formulaire**

```swift
// NeonCompass/Features/Social/CreateCommunitySheet.swift
import SwiftUI

struct CreateCommunitySheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: CommunitiesModel

    @State private var name = ""
    @State private var platform: CommunityPlatform = .ps5
    @State private var selectedPlaystyles: Set<CommunityPlaystyle> = []
    @State private var selectedLanguages: Set<String> = ["en"]
    @State private var discordInvite = ""
    @State private var memberCount = 1
    @State private var isSubmitting = false
    @State private var error: String?

    private static let supportedLanguages = ["fr", "en", "es", "it", "de"]

    private var isValid: Bool {
        name.count >= 3 && name.count <= 30
            && name.range(of: "^[a-zA-Z0-9 -]+$", options: .regularExpression) != nil
            && !selectedPlaystyles.isEmpty
            && (discordInvite.isEmpty || discordInvite.hasPrefix("https://discord.gg/"))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("social.communities.create.name") {
                    TextField("social.communities.create.namePlaceholder", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section("social.communities.create.platform") {
                    Picker("social.communities.create.platform", selection: $platform) {
                        ForEach(CommunityPlatform.allCases) { p in
                            Text(LocalizedStringKey(p.localizationKey)).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("social.communities.create.playstyles") {
                    ForEach(CommunityPlaystyle.allCases) { style in
                        Toggle(isOn: Binding(
                            get: { selectedPlaystyles.contains(style) },
                            set: { if $0 { selectedPlaystyles.insert(style) } else { selectedPlaystyles.remove(style) } }
                        )) {
                            Text(LocalizedStringKey(style.localizationKey))
                        }
                    }
                }

                Section("social.communities.create.languages") {
                    ForEach(Self.supportedLanguages, id: \.self) { lang in
                        Toggle(isOn: Binding(
                            get: { selectedLanguages.contains(lang) },
                            set: { if $0 { selectedLanguages.insert(lang) } else { selectedLanguages.remove(lang) } }
                        )) {
                            Text(Locale.current.localizedString(forLanguageCode: lang) ?? lang)
                        }
                    }
                }

                Section("social.communities.create.discord") {
                    TextField("https://discord.gg/...", text: $discordInvite)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("social.communities.create.memberCount") {
                    Stepper(value: $memberCount, in: 1...10000) {
                        Text(verbatim: "\(memberCount)")
                    }
                }

                if let error {
                    Section {
                        Text(verbatim: error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("social.communities.create.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("social.communities.create.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("social.communities.create.save") { submit() }
                        .disabled(!isValid || isSubmitting)
                }
            }
        }
    }

    private func submit() {
        isSubmitting = true
        error = nil
        Task {
            do {
                let draft = PlayerCommunityDraft(
                    name: name.trimmingCharacters(in: .whitespaces),
                    platform: platform,
                    playstyles: Array(selectedPlaystyles),
                    languages: Array(selectedLanguages),
                    discordInvite: discordInvite.isEmpty ? nil : discordInvite,
                    memberCount: memberCount
                )
                try await model.createCommunity(draft)
                dismiss()
            } catch {
                self.error = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}
```

- [ ] **Step 2: Ajouter le bouton dans `CommunitiesPanel`**

Dans `CommunitiesPanel`, ajouter :
```swift
@Environment(AuthModel.self) private var authModel
@State private var showCreateSheet = false
```

Ajouter après `communityList` dans le body :
```swift
if authModel.userID != nil {
    createButton
}
```

Et la propriété :
```swift
private var createButton: some View {
    Button { showCreateSheet = true } label: {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle")
                .foregroundStyle(NCColor.neonCyan)
            VStack(alignment: .leading, spacing: 2) {
                Text("social.communities.create.button")
                    .font(NCTypography.body)
                    .foregroundStyle(.white)
                Text("social.communities.create.buttonDetail")
                    .font(NCTypography.cardMeta)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
    .buttonStyle(.plain)
    .sheet(isPresented: $showCreateSheet) {
        CreateCommunitySheet(model: model)
    }
}
```

- [ ] **Step 3: xcodegen + build**

```bash
cd /Users/antoine/gta_project && xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build
```

- [ ] **Step 4: Commit**

```bash
git add NeonCompass/Features/Social/CreateCommunitySheet.swift \
        NeonCompass/Features/Social/CommunitiesPanel.swift
git commit -m "feat: formulaire de création de communauté"
```

---

### Task 8: Localisation — clés dans le String Catalog (5 langues)

**Files:**
- Modify: `NeonCompass/Resources/Localizable.xcstrings`

**Interfaces:**
- Produces: toutes les clés `social.communities.*` et `social.panel.communities` en FR, EN, ES, IT, DE

- [ ] **Step 1: Ajouter les clés**

Les clés à ajouter (EN comme base, traduire en FR/ES/IT/DE) :

| Clé | EN |
|---|---|
| `social.panel.communities` | Communities |
| `social.communities.spotlight` | Featured |
| `social.communities.upcomingEvents` | Upcoming Events |
| `social.communities.filter.platform` | Platform |
| `social.communities.filter.playstyle` | Playstyle |
| `social.communities.filter.clear` | Clear |
| `social.communities.empty` | No communities yet |
| `social.communities.detail.close` | Close |
| `social.communities.detail.events` | Upcoming Events |
| `social.communities.detail.joinDiscord` | Join on Discord |
| `social.communities.create.button` | Create my community |
| `social.communities.create.buttonDetail` | List your crew in the directory |
| `social.communities.create.title` | New Community |
| `social.communities.create.cancel` | Cancel |
| `social.communities.create.save` | Create |
| `social.communities.create.name` | Name |
| `social.communities.create.namePlaceholder` | 3-30 characters |
| `social.communities.create.platform` | Platform |
| `social.communities.create.playstyles` | Playstyles |
| `social.communities.create.languages` | Languages |
| `social.communities.create.discord` | Discord |
| `social.communities.create.memberCount` | Members |
| `social.communities.platform.ps5` | PS5 |
| `social.communities.platform.xbox` | Xbox |
| `social.communities.platform.pc` | PC |
| `social.communities.platform.cross-platform` | Cross-platform |
| `social.communities.playstyle.rp` | Roleplay |
| `social.communities.playstyle.racing` | Racing |
| `social.communities.playstyle.heists` | Heists |
| `social.communities.playstyle.casual` | Casual |
| `social.communities.playstyle.competitive` | Competitive |
| `social.communities.playstyle.exploration` | Exploration |
| `social.communities.playstyle.creative` | Creative |
| `social.communities.eventType.tournament` | Tournament |
| `social.communities.eventType.themed_night` | Themed Night |
| `social.communities.eventType.recruitment` | Recruitment |
| `social.communities.eventType.launch` | Launch |
| `social.communities.eventType.training` | Training |
| `social.communities.eventType.other` | Event |

L'implémenteur doit ouvrir `Localizable.xcstrings` et ajouter chaque clé avec ses traductions. Approche : modifier le JSON du fichier xcstrings directement, en ajoutant chaque clé sous `"strings"` avec les cinq localizations.

- [ ] **Step 2: Lancer `LocalizationCoverageTests`**

```bash
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:NeonCompassTests/LocalizationCoverageTests
```

- [ ] **Step 3: Commit**

```bash
git add NeonCompass/Resources/Localizable.xcstrings
git commit -m "feat(l10n): clés du hub communautaire en 5 langues"
```

---

### Task 9: Build complet + tests de la suite

**Files:**
- Aucun nouveau — vérification transversale

- [ ] **Step 1: xcodegen + build complet**

```bash
cd /Users/antoine/gta_project && xcodegen generate
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' build
```

- [ ] **Step 2: Tests complets**

```bash
xcodebuild -scheme NeonCompass -destination 'platform=iOS Simulator,name=iPhone 17' test
```

- [ ] **Step 3: Vérifier que `Localizable.xcstrings` n'a pas été réécrit par xcodebuild**

```bash
git diff --name-only
```

Si `Localizable.xcstrings` apparaît modifié, restaurer :
```bash
git checkout -- NeonCompass/Resources/Localizable.xcstrings
```

- [ ] **Step 4: Commit final si des ajustements ont été nécessaires**
