import Foundation
import SwiftData
import Testing
@testable import TechAssistantPocket

@MainActor struct HomeEditingTests {
    @Test func editMovesOneFuturePlanAndRemovingDateCleansMirror() async throws {
        let container = try ModelContainer(for: Task.self, TaskOccurrence.self, ReviewRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let calendar = FixtureCalendarService()
        let notifications = FixtureNotificationService()
        let suite = "home-edit." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PocketStore(container: container, calendarService: calendar, defaults: defaults, notifications: notifications)
        store.selectedCalendarID = "fixture"
        let now = Date(), task = Task(title: "動画", category: "制作")
        let plan = TaskOccurrence(taskID: task.id, scheduledStart: now.addingTimeInterval(7200))
        #expect(store.perform { store.repository.insert(task); try store.repository.insert(plan) })
        store.syncMirror(plan, title: task.title)
        let mirrorID = plan.calendarEventIdentifier
        let moved = now.addingTimeInterval(86400)
        #expect(store.saveTask(task, title: "動画編集", category: " 制作 ", estimatedDuration: 3600,
                               editing: plan, scheduledStart: moved, duration: 3600, reminder: 5, now: now))
        await store.updateNotification(plan, title: task.title)
        #expect(store.tasks.count == 1 && store.occurrences.count == 1)
        #expect(plan.scheduledStart == moved && plan.scheduledEnd == moved.addingTimeInterval(3600))
        #expect(plan.calendarEventIdentifier == mirrorID && calendar.stored.count == 1)
        #expect(calendar.stored.first?.start == moved)
        #expect(notifications.scheduled[plan.id]?.fireDate == moved.addingTimeInterval(-300))
        #expect(store.categoryNames == ["制作"])
        calendar.failDeletes = true
        #expect(store.saveTask(task, title: task.title, category: "映像", estimatedDuration: 3600,
                               editing: plan, scheduledStart: nil, duration: 3600, reminder: nil, now: now))
        #expect(store.occurrences.isEmpty && store.tasks.count == 1)
        #expect(notifications.scheduled.isEmpty && store.pendingMirrorDeletes.count == 1)
        calendar.failDeletes = false
        store.drainMirrorDeletes()
        #expect(calendar.stored.isEmpty)
        #expect(store.categoryNames == ["制作", "映像"])
        #expect(store.saveTask(task, title: task.title, category: "映像", estimatedDuration: 3600,
                               editing: nil, scheduledStart: moved, duration: 3600, reminder: nil, now: now))
        #expect(store.tasks.count == 1 && store.occurrences.count == 1)
    }

    @Test func startedEditPreservesInsightsHistoryAndTitleOnlyEditDoesNotResolve() throws {
        let container = try ModelContainer(for: Task.self, TaskOccurrence.self, ReviewRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let suite = "started." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PocketStore(container: container, calendarService: FixtureCalendarService(), defaults: defaults,
                                notifications: FixtureNotificationService())
        store.selectedCalendarID = "fixture"
        let now = Date(), task = Task(title: "運動", category: "健康")
        let start = now.addingTimeInterval(-1800)
        let plan = TaskOccurrence(taskID: task.id, scheduledStart: start, duration: 3600)
        #expect(store.perform { store.repository.insert(task); try store.repository.insert(plan) })
        #expect(store.saveTask(task, title: "運動を続ける", category: "健康", estimatedDuration: nil,
                               editing: plan, scheduledStart: start, duration: 3600, reminder: 5, now: now))
        #expect(plan.planResult == .pending && store.occurrences.count == 1)
        #expect(!store.saveTask(task, title: "変えない", category: "健康", estimatedDuration: nil,
                                editing: plan, scheduledStart: nil, duration: 3600, reminder: nil, now: now))
        #expect(task.title == "運動を続ける" && plan.planResult == .pending)
        #expect(store.saveTask(task, title: task.title, category: "健康", estimatedDuration: nil,
                               editing: plan, scheduledStart: now.addingTimeInterval(86400), duration: 3600, reminder: 5, now: now))
        #expect(store.tasks.count == 1 && store.occurrences.count == 2)
        #expect(plan.planResult == .missed)
        #expect(store.occurrences.filter { $0.planResult == .pending }.count == 1)
        #expect(InsightsEngine.plannedRate(store.occurrences.map(\.record)) == SuccessRate(successes: 0, misses: 1))
    }

    @Test func categoryAndTaskStatePersistAcrossDiskReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = ModelConfiguration(url: directory.appendingPathComponent("home.store"))
        let suite = "category." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        do {
            let container = try ModelContainer(for: Task.self, TaskOccurrence.self, ReviewRecord.self, configurations: config)
            let store = PocketStore(container: container, calendarService: FixtureCalendarService(), defaults: defaults, notifications: FixtureNotificationService())
            let task = Task(id: id, title: "制作", category: " アニメーション ")
            let occurrence = TaskOccurrence(taskID: id, scheduledStart: Date().addingTimeInterval(-86400))
            try occurrence.recordExecution(startedAt: occurrence.scheduledStart!)
            #expect(store.perform { store.repository.insert(task); try store.repository.insert(occurrence) })
            #expect(store.perform { task.category = "BK進捗" })
            #expect(store.archive(task))
        }
        let reopened = try ModelContainer(for: Task.self, TaskOccurrence.self, ReviewRecord.self, configurations: config)
        let store = PocketStore(container: reopened, calendarService: FixtureCalendarService(), defaults: UserDefaults(suiteName: suite)!, notifications: FixtureNotificationService())
        #expect(Set(store.categoryNames) == ["アニメーション", "BK進捗"])
        #expect(store.tasks.first?.id == id && store.tasks.first?.archivedAt != nil)
        #expect(store.occurrences.first?.planResult == .success)
        let home = Timeline.presentation(on: Date(), now: Date(), records: store.occurrences.map(\.record), events: [])
        #expect(home.upcoming.isEmpty && home.currentTask == nil)
    }

    @Test func currentTaskWinsOverEventAndOverlappingTasksAreRetained() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 17))!
        let now = start.addingTimeInterval(1800)
        let first = OccurrenceRecord(id: UUID(), taskID: UUID(), start: start, end: start.addingTimeInterval(3600), result: .pending, actual: nil)
        let second = OccurrenceRecord(id: UUID(), taskID: UUID(), start: start.addingTimeInterval(60), end: start.addingTimeInterval(3600), result: .pending, actual: nil)
        let event = CalendarEvent(identifier: "meeting", calendarIdentifier: "personal", title: "会議", start: start.addingTimeInterval(-60), end: start.addingTimeInterval(3600))
        let result = Timeline.presentation(on: now, now: now, records: [first, second], events: [event], calendar: calendar)
        #expect(result.currentTask == .task(first) && result.focus == .task(first))
        #expect(result.upcoming.count == 3)
        let archived = Timeline.presentation(on: now, now: now, records: [first, second], events: [event], calendar: calendar, archivedTaskIDs: [first.taskID])
        #expect(archived.currentTask == .task(second) && archived.history == [.task(first)])
        #expect(Timeline.dayOffset(horizontal: -120, vertical: 20) == 1)
        #expect(Timeline.dayOffset(horizontal: 120, vertical: 20) == -1)
        #expect(Timeline.dayOffset(horizontal: 40, vertical: 120) == 0)
        #expect(Timeline.dayOffset(horizontal: 85, vertical: 75) == 0)
    }
}
