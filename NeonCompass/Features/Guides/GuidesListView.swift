import SwiftUI

struct GuidesListView: View {
    @Bindable var model: GuidesModel
    let onSelect: (Guide) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(GuideChapter.allCases, id: \.self) { chapter in
                    let chapterGuides = model.guides(in: chapter)
                    if !chapterGuides.isEmpty {
                        chapterSection(chapter, guides: chapterGuides)
                    }
                }
            }
            .padding(16)
        }
        .background(NCColor.nightSky.ignoresSafeArea())
    }

    private func chapterSection(_ chapter: GuideChapter, guides: [Guide]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(chapterTitleKey(chapter))
                .font(NCTypography.body.bold())
                .foregroundStyle(NCColor.neonCyan)

            ForEach(guides) { guide in
                Button {
                    onSelect(guide)
                } label: {
                    Text(guide.title.resolved(for: currentLanguageCode))
                        .font(NCTypography.body)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
            }
        }
    }

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    private func chapterTitleKey(_ chapter: GuideChapter) -> LocalizedStringKey {
        switch chapter {
        case .story: "guides.chapter.story"
        case .sideContent: "guides.chapter.sideContent"
        case .beginner: "guides.chapter.beginner"
        case .money: "guides.chapter.money"
        }
    }
}
