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
                    TextField("social.communities.create.discordPlaceholder", text: $discordInvite)
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
