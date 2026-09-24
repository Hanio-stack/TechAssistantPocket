import Foundation
import SwiftData

/// Main-actor SwiftData boundary. Call save() after editing fetched models.
/// Use a dedicated context; saves apply to all changes in that context.
@MainActor
final class TaskRepository {
    private let context: ModelContext
    private let calendar: Calendar

    init(context: ModelContext, calendar: Calendar = .autoupdatingCurrent) {
        self.context = context
        self.calendar = calendar
    }

    func insert(_ task: Task) {
        context.insert(task)
    }

    func insert(_ occurrence: TaskOccurrence) throws {
        let taskID = occurrence.taskID
        guard try context.fetchCount(FetchDescriptor<Task>(
            predicate: #Predicate { $0.id == taskID }
        )) > 0 else {
            throw RepositoryError.taskNotFound
        }
        context.insert(occurrence)
        if let start = occurrence.scheduledStart { try invalidateReview(on: start) }
    }

    func tasks(includeArchived: Bool = false) throws -> [Task] {
        let predicate: Predicate<Task>? = includeArchived ? nil : #Predicate { $0.archivedAt == nil }
        return try context.fetch(FetchDescriptor(predicate: predicate,
                                                 sortBy: [SortDescriptor(\Task.createdAt)]))
    }

    func occurrences(for taskID: UUID) throws -> [TaskOccurrence] {
        try context.fetch(FetchDescriptor(
            predicate: #Predicate<TaskOccurrence> { $0.taskID == taskID },
            sortBy: [SortDescriptor(\TaskOccurrence.createdAt)]
        ))
    }

    /// Returns mirror identifiers for future service cleanup; performs no platform side effects.
    @discardableResult
    func archive(_ task: Task, at now: Date) throws -> [CalendarMirror] {
        let futurePending = try occurrences(for: task.id).filter {
            $0.planResult == .pending && ($0.scheduledStart.map { $0 > now } ?? false)
        }
        let mirrors = futurePending.map {
            CalendarMirror(occurrenceID: $0.id, eventIdentifier: $0.calendarEventIdentifier,
                           calendarIdentifier: $0.calendarIdentifier)
        }
        task.archivedAt = now
        for occurrence in futurePending { context.delete(occurrence) }
        return mirrors
    }

    func allOccurrences() throws -> [TaskOccurrence] {
        try context.fetch(FetchDescriptor<TaskOccurrence>())
    }

    func reviews() throws -> [ReviewRecord] {
        try context.fetch(FetchDescriptor<ReviewRecord>())
    }

    func invalidateReview(on date: Date) throws {
        let key = ReviewPolicy.dateKey(date, calendar: calendar)
        for review in try reviews() where review.dateKey == key { context.delete(review) }
    }

    func finishReview(on day: Date, now: Date) throws {
        let records = try allOccurrences().map(\.record)
        guard ReviewPolicy.isAvailable(on: day, records: records, now: now, calendar: calendar),
              !records.contains(where: { $0.result == .pending && ($0.start.map { calendar.isDate($0, inSameDayAs: day) } ?? false) }) else {
            throw RepositoryError.unresolvedReview
        }
        try invalidateReview(on: day)
        context.insert(ReviewRecord(dateKey: ReviewPolicy.dateKey(day, calendar: calendar), reviewedAt: now))
    }

    func reschedule(_ occurrence: TaskOccurrence, to start: Date, duration: TimeInterval, now: Date) throws -> TaskOccurrence {
        let oldStart = occurrence.scheduledStart
        let wasPending = occurrence.planResult == .pending
        let next = try occurrence.reschedule(to: start, duration: duration, now: now)
        if next.id != occurrence.id { try insert(next) }
        else { try invalidateReview(on: start) }
        if wasPending, let oldStart { try invalidateReview(on: oldStart) }
        return next
    }

    /// Removing an unstarted plan does not erase an execution or a failed slot.
    func removeFuturePlan(_ occurrence: TaskOccurrence, now: Date) throws {
        guard occurrence.planResult == .pending, let start = occurrence.scheduledStart, start > now else {
            throw TaskOccurrence.ResolutionError.invalidSchedule
        }
        try invalidateReview(on: start)
        context.delete(occurrence)
    }

    func save() throws {
        try context.save()
    }

    enum RepositoryError: Error {
        case taskNotFound
        case unresolvedReview
    }

    struct CalendarMirror {
        let occurrenceID: UUID
        let eventIdentifier: String?
        let calendarIdentifier: String?
    }
}
