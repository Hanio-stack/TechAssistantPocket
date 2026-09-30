#if DEBUG
import Foundation
import SwiftData

@MainActor enum SchedulerUIFixtureClock {
    static var reference: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 13))! }
    static var value = reference
}

@MainActor enum SchedulerUIFixtures {
    static func container() throws -> ModelContainer {
        let root = URL.applicationSupportDirectory.appendingPathComponent("SchedulerUITests", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if ProcessInfo.processInfo.arguments.contains("--ui-auto-reset") {
            // Only explicit UI-test data in this dedicated directory is reset.
            for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) { try FileManager.default.removeItem(at: url) }
            UserDefaults(suiteName: "pocket.scheduler.ui-tests")!.removePersistentDomain(forName: "pocket.scheduler.ui-tests")
        }
        return try PocketSchedulerSchema.container(configuration: ModelConfiguration(url: root.appendingPathComponent("scheduler.store")))
    }
    static func store(container: ModelContainer) throws -> AutoSchedulerStore {
        let args = ProcessInfo.processInfo.arguments
        let defaults = UserDefaults(suiteName: "pocket.scheduler.ui-tests")!
        let persistedNow = defaults.double(forKey: "fixtureNow")
        SchedulerUIFixtureClock.value = persistedNow == 0 ? SchedulerUIFixtureClock.reference : Date(timeIntervalSince1970: persistedNow)
        if args.contains("--ui-auto-outside") { SchedulerUIFixtureClock.value = SchedulerUIFixtureClock.reference.addingTimeInterval(4 * 3600) }
        if args.contains("--ui-auto-no-fit") { SchedulerUIFixtureClock.value = SchedulerUIFixtureClock.reference.addingTimeInterval(8400) }
        if !args.contains("--ui-auto-setup"), defaults.data(forKey: "autoSchedulerSettings") == nil {
            let range = WorkClockRange(startMinutes: 780, endMinutes: 960)
            defaults.set(try JSONEncoder().encode(SchedulerSettings(wakeMinutes: 480, bedMinutes: 90, work: WorkWindowPolicy(weekday: range, weekend: range))), forKey: "autoSchedulerSettings")
        }
        defaults.set("fixture", forKey: "defaultCalendarIdentifier")
        let service = FixtureCalendarService()
        if args.contains("--ui-auto-busy") {
            service.stored = [CalendarEvent(identifier: "busy", calendarIdentifier: "ordinary", title: "外部会議", start: SchedulerUIFixtureClock.reference, end: SchedulerUIFixtureClock.reference.addingTimeInterval(10800))]
        }
        let store = AutoSchedulerStore(container: container, calendarService: service, defaults: defaults, clock: { SchedulerUIFixtureClock.value })
        if store.tasks.isEmpty && !args.contains("--ui-auto-empty") && !args.contains("--ui-auto-setup") {
            let long = args.contains("--ui-auto-long")
            _ = store.saveTask(title: long ? "ゲームに登場する敵キャラクターの攻撃アニメーションを仕上げる" : "アニメーション", genre: long ? "ゲーム制作とアニメーションの進捗管理" : "BK", priority: 3, minutes: 180)
            if !args.contains("--ui-auto-no-fit") {
                _ = store.saveTask(title: "音楽", genre: "制作", priority: 2, minutes: 60)
                _ = store.saveTask(title: "読書", genre: "学習", priority: 1, minutes: 30)
            }
        }
        return store
    }
}
#endif
