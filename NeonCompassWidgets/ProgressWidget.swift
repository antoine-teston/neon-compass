import SwiftUI
import WidgetKit

struct ProgressEntry: TimelineEntry {
    let date: Date
    let summary: WidgetSummary?
}

/// Plain `TimelineProvider` (not `AppIntentTimelineProvider`) — this widget
/// has no user-configurable options, so the simpler, non-interactive shape
/// is still the right one; `AppIntentTimelineProvider`/`ControlWidget` exist
/// for configurable widgets and Control Center controls, not needed here.
struct ProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProgressEntry {
        ProgressEntry(date: .now, summary: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (ProgressEntry) -> Void) {
        completion(ProgressEntry(date: .now, summary: WidgetSummary.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProgressEntry>) -> Void) {
        let entry = ProgressEntry(date: .now, summary: WidgetSummary.load())
        // Refresh hourly — this data doesn't change fast enough to justify
        // a tighter policy, and WidgetKit's own reload budget is limited.
        // `AppGroupWidgetSummaryWriter.write` still forces an immediate
        // reload after every app-side update, so this is just the ceiling
        // for staleness when the app hasn't been opened.
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600))))
    }
}

struct ProgressWidgetView: View {
    let entry: ProgressEntry

    var body: some View {
        if let summary = entry.summary, summary.isProEntitled {
            VStack(spacing: 8) {
                ProgressRing(progress: summary.overallProgress)
                    .frame(width: 44, height: 44)
                if let favoriteCheatTitle = summary.favoriteCheatTitle {
                    Text(favoriteCheatTitle)
                        .font(.caption2)
                        .lineLimit(1)
                }
            }
            .padding()
        } else {
            VStack(spacing: 4) {
                Image(systemName: "lock.fill")
                Text("widget.upsell")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

struct ProgressWidget: Widget {
    let kind = "ProgressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProgressProvider()) { entry in
            ProgressWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    NCColor.nightSky
                }
        }
        .configurationDisplayName("widget.displayName")
        .description("widget.description")
        .supportedFamilies([.systemSmall])
    }
}
