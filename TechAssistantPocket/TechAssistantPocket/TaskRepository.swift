import Foundation
import SwiftData

/// Main-actor SwiftData boundary. Call save() after editing fetched models.
/// Use a dedicated context; saves apply to all changes in that context.
@MainActor
final class TaskRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
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

    func save() throws {
        try context.save()
    }

    enum RepositoryError: Error {
        case taskNotFound
    }

    struct CalendarMirror {
        let occurrenceID: UUID
        let eventIdentifier: String?
        let calendarIdentifier: String?
    }
}
