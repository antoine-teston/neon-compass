import Testing
@testable import NeonCompass

struct SocialHubVisibilityTests {
    @Test func voteModuleNeedsServerAndProposals() {
        #expect(SocialHubVisibility(serverEnabled: true, proposalCount: 2, leaderboardRowCount: 0, heroShowsEvent: true, isProEntitled: false).showsVoteModule)
        #expect(!SocialHubVisibility(serverEnabled: false, proposalCount: 2, leaderboardRowCount: 0, heroShowsEvent: true, isProEntitled: false).showsVoteModule)
        #expect(!SocialHubVisibility(serverEnabled: true, proposalCount: 0, leaderboardRowCount: 0, heroShowsEvent: true, isProEntitled: false).showsVoteModule)
    }

    @Test func leaderboardTileNeedsServerAndRows() {
        #expect(SocialHubVisibility(serverEnabled: true, proposalCount: 0, leaderboardRowCount: 3, heroShowsEvent: true, isProEntitled: false).showsLeaderboardTile)
        #expect(!SocialHubVisibility(serverEnabled: true, proposalCount: 0, leaderboardRowCount: 0, heroShowsEvent: true, isProEntitled: false).showsLeaderboardTile)
        #expect(!SocialHubVisibility(serverEnabled: false, proposalCount: 0, leaderboardRowCount: 3, heroShowsEvent: true, isProEntitled: false).showsLeaderboardTile)
    }

    /// La règle existante conservée : du contenu affiché ET pas d'abonné Pro.
    /// Un état vide n'est pas un écran de liste, la pub n'y a pas sa place.
    @Test func bannerNeedsAnEventAndNoProEntitlement() {
        #expect(SocialHubVisibility(serverEnabled: false, proposalCount: 0, leaderboardRowCount: 0, heroShowsEvent: true, isProEntitled: false).showsBanner)
        #expect(!SocialHubVisibility(serverEnabled: false, proposalCount: 0, leaderboardRowCount: 0, heroShowsEvent: false, isProEntitled: false).showsBanner)
        #expect(!SocialHubVisibility(serverEnabled: false, proposalCount: 0, leaderboardRowCount: 0, heroShowsEvent: true, isProEntitled: true).showsBanner)
    }

    @Test func unvotedCountIgnoresVotedSpots() {
        #expect(SocialHubVisibility.unvotedCount(spotIDs: ["a", "b", "c"], votedIDs: ["b"]) == 2)
        #expect(SocialHubVisibility.unvotedCount(spotIDs: [], votedIDs: ["b"]) == 0)
        #expect(SocialHubVisibility.unvotedCount(spotIDs: ["a"], votedIDs: []) == 1)
    }
}
