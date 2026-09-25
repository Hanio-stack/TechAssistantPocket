import SwiftUI
import SwiftData

@main
struct TechAssistantPocketApp: App {
    @State private var store: PocketStore?
    private let startupError: String?

    init() {
        do {
            #if DEBUG
            let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
            #else
            let testing = false
            #endif
            let configuration = ModelConfiguration(isStoredInMemoryOnly: testing)
            let container = try ModelContainer(for: Task.self, TaskOccurrence.self, ReviewRecord.self, configurations: configuration)
            let store: PocketStore
            #if DEBUG
            if testing {
                let defaults = UserDefaults(suiteName: "pocket.ui-tests")!
                if !ProcessInfo.processInfo.arguments.contains("--ui-preserve-defaults") { defaults.removePersistentDomain(forName: "pocket.ui-tests") }
                defaults.set("fixture", forKey: "defaultCalendarIdentifier")
                store = PocketStore(container: container, calendarService: FixtureCalendarService(), defaults: defaults, notifications: FixtureNotificationService())
                if ProcessInfo.processInfo.arguments.contains("--ui-denied"), let calendar = store.calendarService as? FixtureCalendarService {
                    calendar.access = .denied
                    store.refreshCalendar()
                }
                if ProcessInfo.processInfo.arguments.contains("--ui-six-fixes") || ProcessInfo.processInfo.arguments.contains("--ui-life-day") {
                    DebugFixtures.seedSixFixes(store, overnight: ProcessInfo.processInfo.arguments.contains("--ui-life-day"))
                }
                if ProcessInfo.processInfo.arguments.contains("--ui-edit-duration") { DebugFixtures.seedDurationEdit(store) }
                if ProcessInfo.processInfo.arguments.contains("--ui-seed") { DebugFixtures.seed(store) }
                if ProcessInfo.processInfo.arguments.contains("--ui-today-focus") {
                    DebugFixtures.seedTodayFocus(store, includeCurrent: !ProcessInfo.processInfo.arguments.contains("--ui-no-current"))
                }
            } else { store = PocketStore(container: container) }
            #else
            store = PocketStore(container: container)
            #endif
            _store = State(initialValue: store)
            startupError = nil
        } catch {
            _store = State(initialValue: nil)
            startupError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let store { ContentView().environment(store) }
            else {
                ContentUnavailableView {
                    Label("データを開けませんでした", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("保存済みデータは削除していません。アプリを再起動してください。\n\(startupError ?? "")")
                }
            }
        }
    }
}
