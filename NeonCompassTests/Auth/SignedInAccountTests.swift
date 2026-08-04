import Testing
@testable import NeonCompass

struct SignedInAccountTests {
    @Test func knownProvidersMapToTheirCase() {
        #expect(SignedInAccount.Provider.from("apple") == .apple)
        #expect(SignedInAccount.Provider.from("google") == .google)
        #expect(SignedInAccount.Provider.from("email") == .email)
    }

    /// Supabase peut rendre la casse qu'il veut ; l'app ne doit pas en dépendre.
    @Test func providerMatchingIgnoresCase() {
        #expect(SignedInAccount.Provider.from("Apple") == .apple)
        #expect(SignedInAccount.Provider.from("GOOGLE") == .google)
    }

    /// Un fournisseur ajouté côté Supabase avant l'app ne doit pas faire
    /// disparaître la ligne d'identité : elle dit « connecté », sans préciser.
    @Test func anUnknownProviderIsCarriedThroughInsteadOfDropped() {
        #expect(SignedInAccount.Provider.from("github") == .other("github"))
        #expect(SignedInAccount.Provider.from(nil) == .other(""))
    }

    @Test func labelKeysAreDistinct() {
        let keys = [
            SignedInAccount.Provider.apple.labelKey,
            SignedInAccount.Provider.google.labelKey,
            SignedInAccount.Provider.email.labelKey,
            SignedInAccount.Provider.other("x").labelKey,
        ]
        #expect(Set(keys).count == 4)
    }
}
