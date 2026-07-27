import Testing
import Foundation

struct LocalizationCoverageTests {
    private static let requiredLocales = ["en", "fr", "es", "it", "de"]

    private static func loadCatalog() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("NeonCompass/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: url)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    @Test func everyKeyHasAllFiveLocales() throws {
        let catalog = try Self.loadCatalog()
        let strings = catalog["strings"] as? [String: Any] ?? [:]
        #expect(!strings.isEmpty)

        for (key, entry) in strings {
            guard let entry = entry as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any] else {
                Issue.record("'\(key)' has no localizations dictionary")
                continue
            }
            for locale in Self.requiredLocales {
                let values = Self.values(in: localizations[locale])
                if values.isEmpty || values.contains(where: \.isEmpty) {
                    Issue.record("'\(key)' is missing a non-empty '\(locale)' translation")
                }
            }
        }
    }

    @Test func formatSpecifiersMatchAcrossLocales() throws {
        let catalog = try Self.loadCatalog()
        let strings = catalog["strings"] as? [String: Any] ?? [:]

        for (key, entry) in strings {
            guard let entry = entry as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any] else { continue }

            // Toutes les variantes d'une même clé partagent nécessairement les
            // mêmes spécificateurs (« %lld trouvé » / « %lld trouvés »), donc
            // une seule référence suffit — et si l'anglais en produisait
            // plusieurs distincts, on ne saurait pas à laquelle comparer.
            let englishSpecifiers = Set(Self.values(in: localizations["en"]).map { Self.formatSpecifiers(in: $0) })
            guard englishSpecifiers.count == 1, let reference = englishSpecifiers.first else { continue }

            for locale in Self.requiredLocales.dropFirst() {
                for value in Self.values(in: localizations[locale]) {
                    let specifiers = Self.formatSpecifiers(in: value)
                    #expect(
                        specifiers == reference,
                        "'\(key)': '\(locale)' format specifiers \(specifiers) don't match 'en' \(reference)"
                    )
                }
            }
        }
    }

    /// Valeurs traduites d'une langue, qu'elle soit portée par un `stringUnit`
    /// unique ou éclatée en variantes (pluriel, largeur d'appareil…). Les
    /// entrées au pluriel rangent leurs valeurs sous
    /// `variations.plural.{one,other,…}.stringUnit`, donc un lookup direct de
    /// `stringUnit` les verrait comme non traduites.
    private static func values(in localization: Any?) -> [String] {
        guard let localization = localization as? [String: Any] else { return [] }
        if let value = (localization["stringUnit"] as? [String: Any])?["value"] as? String {
            return [value]
        }
        guard let variations = localization["variations"] as? [String: Any] else { return [] }
        return variations.values
            .compactMap { $0 as? [String: Any] }
            .flatMap(\.values)
            .compactMap { ($0 as? [String: Any])?["stringUnit"] as? [String: Any] }
            .compactMap { $0["value"] as? String }
    }

    private static func formatSpecifiers(in value: String) -> [String] {
        let pattern = /%(@|lld|ld|d)/
        return value.matches(of: pattern).map { String(value[$0.range]) }
    }
}
