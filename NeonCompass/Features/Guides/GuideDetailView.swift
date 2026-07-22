import SwiftUI

/// Rendu Markdown natif (AttributedString(markdown:), iOS 15+) — pas de
/// dépendance tierce. Si le texte n'est pas un Markdown valide (cas rare
/// pour du contenu éditorial validé par le CLI admin), on retombe sur le
/// texte brut plutôt que de planter.
struct GuideDetailView: View {
    let guide: Guide

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(guide.title.resolved(for: currentLanguageCode))
                    .font(NCTypography.displayTitle)
                    .foregroundStyle(.white)

                Text(renderedBody)
                    .font(NCTypography.body)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
            }
            .padding(20)
        }
        .background(NCColor.nightSky.ignoresSafeArea())
    }

    private var renderedBody: AttributedString {
        let markdown = guide.body.resolved(for: currentLanguageCode)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }
}
