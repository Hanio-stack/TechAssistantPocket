import Foundation
import SwiftData
import Testing
@testable import TechAssistantPocket

@MainActor struct ServiceCoordinationTests {
    private func makeStore(calendar: FixtureCalendarService, notifications: FixtureNotificationService? = nil, defaults: UserDefaults? = nil) throws -> PocketStore {
        let container = try ModelContainer(for: Task.self, TaskOccurrence.self, ReviewRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return PocketStore(container: container, calendarService: calendar, defaults: defaults ?? UserDefaults(suiteName: UUID().uuidString)!, notifications: notifications)
    }
    @Test func failedCalendarWritePreservesLocalDataAndCanRetry() throws {
        let calendar = FixtureCalendarService()
        let store = try makeStore(calendar: calendar)
        store.selectedCalendarID = "missing"
        let task = Task(title: "読書")
        let occurrence = TaskOccurrence(taskID: task.id, scheduledStart: Date().addingTimeInterval(3600))
        #expect(store.perform { store.repository.insert(task); try store.repository.insert(occurrence) })
        store.syncMirror(occurrence, title: task.title)
        #expect(store.activeTasks.count == 1)
        #expect(store.occurrences.count == 1)
        #expect(occurrence.calendarEventIdentifier == nil)
        #expect(store.calendarWriteMessage != nil)
        store.selectedCalendarID = "fixture"
        store.retryCalendar()
        #expect(occurrence.calendarEventIdentifier != nil)
        #expect(occurrence.calendarIdentifier == "fixture")
        #expect(calendar.stored.count == 1)
        store.retryCalendar()
        #expect(calendar.stored.count == 1)
        calendar.stored = [] // external mirror deletion
        store.refreshCalendar()
        #expect(occurrence.calendarEventIdentifier == nil)
        #expect(store.occurrences.count == 1)
        #expect(store.integrationMessage != nil)
        #expect(store.perform { try occurrence.markMissed() })
        // Resolving a Task must not make an earlier failed mirror write impossible to retry.
        store.retryCalendar()
        #expect(calendar.stored.count == 1)
        #expect(occurrence.planResult == .missed)
    }
    @Test func archiveCleansFutureNotificationsAndRetriesFailedMirrorDeletion() async throws {
        let calendar = FixtureCalendarService()
        let notifications = FixtureNotificationService()
        let suite = "test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = try makeStore(calendar: calendar, notifications: notifications, defaults: defaults)
        store.selectedCalendarID = "fixture"
        let task = Task(title: "英語")
        let future = TaskOccurrence(taskID: task.id, scheduledStart: Date().addingTimeInterval(7200))
        future.notificationMinutesBefore = 5
        let past = TaskOccurrence(taskID: task.id, scheduledStart: Date().addingTimeInterval(-3600))
        #expect(store.perform { store.repository.insert(task); try store.repository.insert(future); try store.repository.insert(past) })
        store.syncMirror(future, title: task.title)
        await store.updateNotification(future, title: task.title)
        await store.updateNotification(future, title: task.title)
        #expect(notifications.scheduled.count == 1)
        calendar.failDeletes = true
        #expect(store.archive(task))
        #expect(notifications.scheduled.isEmpty)
        #expect(store.activeTasks.isEmpty)
        #expect(store.occurrences.map(\.id) == [past.id])
        #expect(store.pendingMirrorDeletes.count == 1)
        #expect(store.integrationMessage != nil)
        let restarted = try makeStore(calendar: calendar, notifications: notifications, defaults: defaults)
        #expect(restarted.pendingMirrorDeletes.count == 1)
        calendar.failDeletes = false
        restarted.drainMirrorDeletes()
        #expect(restarted.pendingMirrorDeletes.isEmpty)
        #expect(calendar.stored.isEmpty)
    }
    @Test func ordinaryEventsDoNotCreateTasksOrLocalNotifications() throws {
        let calendar = FixtureCalendarService()
        let notifications = FixtureNotificationService()
        let store = try makeStore(calendar: calendar, notifications: notifications)
        let now = Date()
        try store.calendarService.createEvent(title: "会議", start: now, end: now.addingTimeInterval(3600), calendarID: "fixture", reminderMinutes: 15)
        #expect(calendar.stored.count == 1)
        #expect(calendar.ordinaryAlarm == 15)
        #expect(store.tasks.isEmpty)
        #expect(store.occurrences.isEmpty)
        #expect(notifications.scheduled.isEmpty)
    }
    @Test func selectedCalendarDisappearingPreservesTaskAndRequiresReselection() throws {
        let calendar = FixtureCalendarService()
        let store = try makeStore(calendar: calendar)
        store.selectedCalendarID = "fixture"
        let task = Task(title: "Task")
        #expect(store.perform { store.repository.insert(task) })
        calendar.choices = []
        store.refreshCalendar()
        #expect(store.calendarMessage == CalendarFailure.calendarUnavailable.localizedDescription)
        #expect(store.selectedCalendarID == "fixture")
        #expect(store.activeTasks.count == 1)
    }
    @Test func diskStoreSurvivesReopeningWithReminderAndReview() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = ModelConfiguration(url: directory.appendingPathComponent("test.store"))
        let taskID = UUID()
        do {
            let container = try ModelContainer(for: Task.self, TaskOccurrence.self, ReviewRecord.self, configurations: config)
            let repository = TaskRepository(context: ModelContext(container))
            let task = Task(id: taskID, title: "永続化テスト")
            repository.insert(task)
            let occurrence = TaskOccurrence(taskID: taskID, scheduledStart: Date().addingTimeInterval(-3600))
            occurrence.notificationMinutesBefore = 15
            try occurrence.markMissed()
            try repository.insert(occurrence)
            try repository.finishReview(on: occurrence.scheduledStart!, now: Date())
            try repository.save()
        }
        let reopened = try ModelContainer(for: Task.self, TaskOccurrence.self, ReviewRecord.self, configurations: config)
        let reader = TaskRepository(context: ModelContext(reopened))
        #expect(try reader.tasks().first?.id == taskID)
        #expect(try reader.allOccurrences().first?.notificationMinutesBefore == 15)
        #expect(try reader.reviews().count == 1)
    }
    @Test func suggestionWaitsForApprovalAndRechecksBusyTime() async throws {
        let calendar = FixtureCalendarService()
        let notifications = FixtureNotificationService()
        let store = try makeStore(calendar: calendar, notifications: notifications)
        store.selectedCalendarID = "fixture"
        let now = Date()
        let task = Task(title: "英語")
        let plan = TaskOccurrence(taskID: task.id, scheduledStart: now.addingTimeInterval(3600))
        plan.notificationMinutesBefore = 5
        #expect(store.perform { store.repository.insert(task); try store.repository.insert(plan) })
        store.syncMirror(plan, title: task.title)
        await store.updateNotification(plan, title: task.title)
        let suggestion = ScheduleSuggestion(occurrenceID: plan.id, start: now.addingTimeInterval(7200), end: now.addingTimeInterval(9000),
                                            currentEvidence: SuccessRate(successes: 0, misses: 3), proposedEvidence: SuccessRate(successes: 3, misses: 0))
        #expect(plan.scheduledStart == now.addingTimeInterval(3600))
        calendar.stored.append(CalendarEvent(identifier: "busy", calendarIdentifier: "fixture", title: "会議", start: suggestion.start, end: suggestion.end))
        await store.applySuggestion(suggestion)
        #expect(plan.scheduledStart == now.addingTimeInterval(3600))
        #expect(store.errorMessage != nil)
        calendar.stored.removeAll { $0.identifier == "busy" }
        await store.applySuggestion(suggestion)
        #expect(plan.scheduledStart == suggestion.start)
        #expect(store.occurrences.count == 1)
        #expect(notifications.scheduled[plan.id]?.fireDate == suggestion.start.addingTimeInterval(-300))
        #expect(calendar.stored.count == 1)
    }

}
