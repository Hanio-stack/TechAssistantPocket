import Foundation
import SwiftData
import Testing
@testable import TechAssistantPocket

@MainActor struct ReviewAndRescheduleTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        return calendar
    }
    private var day: Date { calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000)) }
    private func record(start: Date?, end: Date?, result: PlanResult?) -> OccurrenceRecord {
        OccurrenceRecord(id: UUID(), taskID: UUID(), start: start, end: end, result: result, actual: nil)
    }
    @Test func reviewAvailabilityAndOvernightOwnership() {
        let now = day.addingTimeInterval(23 * 3600)
        #expect(!ReviewPolicy.isAvailable(on: day, records: [], now: now, calendar: calendar))
        #expect(!ReviewPolicy.isAvailable(on: day, records: [record(start: nil, end: nil, result: nil)], now: now, calendar: calendar))
        let overnight = record(start: now, end: now.addingTimeInterval(7200), result: .pending)
        #expect(!ReviewPolicy.isAvailable(on: day, records: [overnight], now: now.addingTimeInterval(7200), calendar: calendar))
        let nextDay = now.addingTimeInterval(7201)
        #expect(ReviewPolicy.latestDay(records: [overnight], reviewedKeys: [], now: nextDay, calendar: calendar) == day)
        #expect(!ReviewPolicy.isAvailable(on: nextDay, records: [overnight], now: nextDay, calendar: calendar))
        #expect(ReviewPolicy.latestDay(records: [overnight], reviewedKeys: [ReviewPolicy.dateKey(day, calendar: calendar)], now: nextDay, calendar: calendar) == nil)
        let resolved = record(start: day, end: now, result: .cancelled)
        #expect(ReviewPolicy.isAvailable(on: day, records: [resolved], now: day.addingTimeInterval(3600), calendar: calendar))
        let older = record(start: day.addingTimeInterval(-86400), end: day.addingTimeInterval(-82800), result: .success)
        #expect(ReviewPolicy.latestDay(records: [older, resolved], reviewedKeys: [], now: now, calendar: calendar) == day)
    }
    @Test func addingScheduleInvalidatesReviewButSpontaneousDoesNot() throws {
        let container = try ModelContainer(for: Task.self, TaskOccurrence.self, ReviewRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let repository = TaskRepository(context: ModelContext(container), calendar: calendar)
        let task = Task(title: "読書")
        repository.insert(task)
        let first = TaskOccurrence(taskID: task.id, scheduledStart: day)
        try first.markMissed()
        try repository.insert(first)
        try repository.finishReview(on: day, now: day.addingTimeInterval(3600))
        try repository.save()
        #expect(try repository.reviews().count == 1)
        try repository.insert(TaskOccurrence(taskID: task.id, actualExecutedAt: day.addingTimeInterval(3600)))
        try repository.save()
        #expect(try repository.reviews().count == 1)
        let newPlan = TaskOccurrence(taskID: task.id, scheduledStart: day.addingTimeInterval(7200))
        try repository.insert(newPlan)
        try repository.save()
        #expect(try repository.reviews().isEmpty)
        let records = try repository.allOccurrences().map(\.record)
        #expect(!ReviewPolicy.isAvailable(on: day, records: records, now: day.addingTimeInterval(3600), calendar: calendar))
        #expect(ReviewPolicy.isAvailable(on: day, records: records, now: day.addingTimeInterval(9001), calendar: calendar))
        #expect(throws: TaskRepository.RepositoryError.self) { try repository.finishReview(on: day, now: day.addingTimeInterval(10000)) }
        try newPlan.cancel()
        try repository.finishReview(on: day, now: day.addingTimeInterval(10000))
        try repository.save()
        #expect(try repository.reviews().count == 1)
    }
    @Test(arguments: [-1.0, 0, 1801])
    func reschedulingPreservesFailedSlot(offset: TimeInterval) throws {
        let occurrence = TaskOccurrence(taskID: UUID(), scheduledStart: day)
        occurrence.calendarEventIdentifier = "mirror"
        occurrence.notificationMinutesBefore = 5
        let next = try occurrence.reschedule(to: day.addingTimeInterval(86400), duration: 2700, now: day.addingTimeInterval(offset))
        if offset < 0 {
            #expect(next.id == occurrence.id)
            #expect(occurrence.planResult == .pending)
            #expect(occurrence.calendarEventIdentifier == "mirror")
        } else {
            #expect(next.id != occurrence.id)
            #expect(occurrence.planResult == .missed)
            #expect(occurrence.scheduledStart == day)
            #expect(next.calendarEventIdentifier == nil)
        }
        #expect(next.taskID == occurrence.taskID)
        #expect(next.notificationMinutesBefore == 5)
        #expect(next.scheduledEnd == day.addingTimeInterval(86400 + 2700))
        #expect(next.planResult == .pending)
        #expect(next.actualExecutedAt == nil)
    }
    @Test func noReschedulingOfCompletedHistory() throws {
        let occurrence = TaskOccurrence(taskID: UUID(), scheduledStart: day)
        try occurrence.recordExecution(startedAt: day)
        #expect(throws: TaskOccurrence.ResolutionError.self) {
            try occurrence.reschedule(to: day.addingTimeInterval(86400), duration: 1800, now: day)
        }
    }
    @Test func remindersAreFuturePendingOnlyAndReuseOccurrenceIdentifier() {
        let id = UUID()
        let reminder = ReminderPolicy.reminder(id: id, title: "読書", start: day, result: .pending, minutes: 5, now: day.addingTimeInterval(-600))
        #expect(reminder?.fireDate == day.addingTimeInterval(-300))
        #expect(reminder?.identifier == "pocket." + id.uuidString)
        #expect(ReminderPolicy.reminder(id: id, title: "読書", start: day, result: .success, minutes: 5, now: day.addingTimeInterval(-600)) == nil)
        #expect(ReminderPolicy.reminder(id: id, title: "読書", start: day, result: .pending, minutes: 5, now: day) == nil)
        #expect(ReminderPolicy.reminder(id: id, title: "読書", start: nil, result: nil, minutes: 0, now: day) == nil)
    }
    @Test func reschedulingAnAlreadyReviewedMissDoesNotReopenUnchangedHistory() throws {
        let container = try ModelContainer(for: Task.self, TaskOccurrence.self, ReviewRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let repository = TaskRepository(context: ModelContext(container), calendar: calendar)
        let task = Task(title: "読書")
        repository.insert(task)
        let missed = TaskOccurrence(taskID: task.id, scheduledStart: day)
        try missed.markMissed()
        try repository.insert(missed)
        try repository.finishReview(on: day, now: day.addingTimeInterval(3600))
        try repository.save()
        let next = try repository.reschedule(missed, to: day.addingTimeInterval(86400), duration: 1800, now: day.addingTimeInterval(3600))
        try repository.save()
        #expect(next.id != missed.id)
        #expect(missed.planResult == .missed)
        #expect(try repository.reviews().map(\.dateKey) == [ReviewPolicy.dateKey(day, calendar: calendar)])
    }

}
