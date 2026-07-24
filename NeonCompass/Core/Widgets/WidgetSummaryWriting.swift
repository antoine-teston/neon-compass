/// Abstraction over "persist the widget's summary somewhere the widget
/// extension process can read it". Lets ProgressionModel/CheatsModel push
/// updates without depending on UserDefaults/App Group/WidgetKit directly,
/// matching this codebase's Core-protocol pattern (Firebase, StoreKit, etc.
/// all stay behind a protocol so features are testable without I/O).
protocol WidgetSummaryWriting: Sendable {
    func write(_ summary: WidgetSummary)
}
