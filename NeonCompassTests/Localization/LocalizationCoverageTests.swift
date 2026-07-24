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
                let value = (localizations[locale] as? [String: Any])
                    .flatMap { $0["stringUnit"] as? [String: Any] }
                    .flatMap { $0["value"] as? String }
                if value == nil || value?.isEmpty == true {
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

            var specifiersByLocale: [String: [String]] = [:]
            for locale in Self.requiredLocales {
                guard let value = (localizations[locale] as? [String: Any])
                    .flatMap({ $0["stringUnit"] as? [String: Any] })
                    .flatMap({ $0["value"] as? String }) else { continue }
                specifiersByLocale[locale] = Self.formatSpecifiers(in: value)
            }
            guard let reference = specifiersByLocale["en"] else { continue }
            for locale in Self.requiredLocales.dropFirst() {
                guard let specifiers = specifiersByLocale[locale] else { continue }
                #expect(
                    specifiers == reference,
                    "'\(key)': '\(locale)' format specifiers \(specifiers) don't match 'en' \(reference)"
                )
            }
        }
    }

    private static func formatSpecifiers(in value: String) -> [String] {
        let pattern = /%(@|lld|ld|d)/
        return value.matches(of: pattern).map { String(value[$0.range]) }
    }
}
