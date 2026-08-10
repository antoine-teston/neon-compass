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
        guard let client else { throw CommunityListError.notConfigured }
        return try await client
            .from("communities")
            .insert(draft)
            .select()
            .single()
            .execute()
            .value
    }

    func updateCommunity(id: String, draft: PlayerCommunityDraft) async throws {
        guard let client else { throw CommunityListError.notConfigured }
        try await client
            .from("communities")
            .update(draft)
            .eq("id", value: id)
            .execute()
    }

    func deleteCommunity(id: String) async throws {
        guard let client else { throw CommunityListError.notConfigured }
        try await client
            .from("communities")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    func createEvent(_ draft: CommunityEventDraft, communityID: String) async throws {
        guard let client else { throw CommunityListError.notConfigured }
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
        guard let client else { throw CommunityListError.notConfigured }
        try await client
            .from("community_events")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}
