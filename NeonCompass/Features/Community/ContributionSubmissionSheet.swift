import SwiftUI

struct ContributionSubmissionSheet: View {
    let position: NormalizedPoint
    let onSubmit: (POICategory, String) async -> Void
    let onDismiss: () -> Void

    @State private var category: POICategory = .landmark
    @State private var title: String = ""
    @State private var isSubmitting = false

    private var isValid: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 280
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("map.contribution.categoryLabel", selection: $category) {
                    ForEach(POICategory.allCases, id: \.self) { category in
                        Text(category.localizedNameKey).tag(category)
                    }
                }
                TextField("map.contribution.titlePlaceholder", text: $title, axis: .vertical)
                    .lineLimit(3...6)
            }
            .navigationTitle(Text("map.contribution.sheetTitle"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("map.contribution.cancel", action: onDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("map.contribution.submit") {
                        isSubmitting = true
                        Task {
                            await onSubmit(category, title.trimmingCharacters(in: .whitespacesAndNewlines))
                            isSubmitting = false
                        }
                    }
                    .disabled(!isValid || isSubmitting)
                }
            }
        }
    }
}
