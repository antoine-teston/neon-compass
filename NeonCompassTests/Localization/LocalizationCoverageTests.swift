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

    // MARK: - Accord entre les sites d'appel et les clés du catalogue

    /// `Text("clé \(n)")` ne cherche pas `clé` : SwiftUI construit la clé
    /// `clé %lld`, spécificateur compris. Une entrée de catalogue nommée sans
    /// lui n'est donc jamais trouvée, et l'écran affiche le nom de la clé à la
    /// place de la phrase. Le test de couverture ne voyait rien — l'entrée est
    /// traduite dans les cinq langues, simplement inatteignable.
    ///
    /// Trois clés avaient déjà livré ce défaut (`cheats.unavailable.title`,
    /// `progress.challenge.foundCount`, `progress.challenge.partialData`),
    /// dont deux visibles à l'œil nu en production.
    ///
    /// L'idiome `String(format: String(localized: "clé"), x)` est l'exception
    /// exacte : la recherche se fait sans interpolation, donc sa clé ne porte
    /// pas de spécificateur. Ce test ne le voit pas, et c'est voulu — il ne
    /// s'intéresse qu'aux littéraux qui interpolent.
    @Test func interpolatedCallSitesResolveToACatalogKey() throws {
        let catalog = try Self.loadCatalog()
        let keys = Array((catalog["strings"] as? [String: Any] ?? [:]).keys)
        #expect(!keys.isEmpty)

        for file in try Self.swiftSources() {
            let source = try String(contentsOf: file, encoding: .utf8)
            let name = file.lastPathComponent
            for prefix in Self.interpolatedLocalizedPrefixes(in: source) {
                guard !prefix.isEmpty else {
                    Issue.record("\(name) : une chaîne localisée réduite à sa seule interpolation — passer par Text(verbatim:)")
                    continue
                }
                let isReachable = keys.contains {
                    $0.hasPrefix(prefix) && !Self.formatSpecifiers(in: $0).isEmpty
                }
                #expect(
                    isReachable,
                    "\(name) : '\(prefix)…' interpole une valeur, mais aucune clé du catalogue ne commence par ce préfixe en portant un spécificateur — l'app afficherait le nom de la clé"
                )
            }
        }
    }

    private static func swiftSources() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("NeonCompass")
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// Les préfixes littéraux qui précèdent la première interpolation, un par
    /// site d'appel localisé. `Text(verbatim:)` ne correspond à aucun de ces
    /// ouvrants, et s'exclut donc tout seul.
    private static func interpolatedLocalizedPrefixes(in source: String) -> [String] {
        let openers = ["Text(\"", "Label(\"", "String(localized: \"", "LocalizedStringResource(\""]
        var found: [String] = []
        for opener in openers {
            var searchRange = source.startIndex..<source.endIndex
            while let match = source.range(of: opener, range: searchRange) {
                if let prefix = Self.interpolatedPrefix(in: source, startingAt: match.upperBound) {
                    found.append(prefix)
                }
                searchRange = match.upperBound..<source.endIndex
            }
        }
        return found
    }

    /// Le texte qui précède la première interpolation du littéral ouvert à
    /// `index`, ou `nil` si ce littéral se referme sans rien interpoler. On
    /// s'arrête au `\(` sans lire l'interpolation : son contenu peut lui-même
    /// contenir des guillemets.
    private static func interpolatedPrefix(in source: String, startingAt index: String.Index) -> String? {
        var prefix = ""
        var cursor = index
        while cursor < source.endIndex {
            let character = source[cursor]
            if character == "\"" || character == "\n" { return nil }
            if character == "\\" {
                let escaped = source.index(after: cursor)
                guard escaped < source.endIndex else { return nil }
                if source[escaped] == "(" { return prefix }
                prefix.append(character)
                prefix.append(source[escaped])
                cursor = source.index(after: escaped)
                continue
            }
            prefix.append(character)
            cursor = source.index(after: cursor)
        }
        return nil
    }
}
