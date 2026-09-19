import Foundation
import SwiftData
import Testing
@testable import TechAssistantPocket

@MainActor
struct TechAssistantPocketTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func container() throws -> ModelContainer {
        try ModelContainer(for: Task.self, TaskOccurrence.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func defaultsAndSpontaneousExecution() throws {
        let task = Task(title: "英語学習", createdAt: start)
        #expect(task.category == nil)
        #expect(task.estimatedDuration == nil)
        #expect(task.archivedAt == nil)
        let scheduled = TaskOccurrence(taskID: task.id, scheduledStart: start, createdAt: start)
        #expect(scheduled.scheduledEnd == start.addingTimeInterval(1800))
        #expect(scheduled.planResult == .pending)
        #expect(scheduled.actualExecutedAt == nil)
        let spontaneous = TaskOccurrence(taskID: task.id, actualExecutedAt: start, createdAt: start)
        #expect(spontaneous.scheduledStart == nil)
        #expect(spontaneous.scheduledEnd == nil)
        #expect(spontaneous.planResult == nil)
        #expect(spontaneous.actualExecutedAt == start)
        #expect(throws: TaskOccurrence.ResolutionError.self) { try spontaneous.cancel() }
        #expect(throws: TaskOccurrence.ResolutionError.self) { try spontaneous.markMissed() }
        #expect(throws: TaskOccurrence.ResolutionError.self) { try spontaneous.recordExecution(startedAt: start) }
        #expect(spontaneous.actualExecutedAt == start)
    }

    @Test(arguments: [-1.0, 0, 900, 1800, 1801])
    func executionUsesActualStartAndInclusiveBoundaries(offset: TimeInterval) throws {
        let occurrence = TaskOccurrence(taskID: UUID(), scheduledStart: start, createdAt: start)
        try occurrence.recordExecution(startedAt: start.addingTimeInterval(offset))
        #expect(occurrence.planResult == ((0...1800).contains(offset) ? .success : .missed))
        #expect(occurrence.actualExecutedAt == start.addingTimeInterval(offset))
        #expect(occurrence.scheduledStart == start)
        #expect(throws: TaskOccurrence.ResolutionError.self) { try occurrence.cancel() }
        #expect(throws: TaskOccurrence.ResolutionError.self) { try occurrence.markMissed() }
        #expect(throws: TaskOccurrence.ResolutionError.self) { try occurrence.recordExecution(startedAt: start) }
        #expect(occurrence.actualExecutedAt == start.addingTimeInterval(offset))
    }

    @Test func persistedModelsAndEditsRoundTrip() throws {
        let store = try container()
        let context = ModelContext(store)
        context.autosaveEnabled = false
        let repository = TaskRepository(context: context)
        let task = Task(title: "英語", category: "学習", estimatedDuration: 2700, createdAt: start)
        repository.insert(task)
        var ids: [UUID] = []
        for (index, result) in PlanResult.allCases.enumerated() {
            let occurrence = TaskOccurrence(taskID: task.id, scheduledStart: start,
                                            duration: 2700, createdAt: start.addingTimeInterval(Double(index)))
            switch result {
            case .pending: break
            case .success: try occurrence.recordExecution(startedAt: start)
            case .missed: try occurrence.recordExecution(startedAt: start.addingTimeInterval(9000))
            case .cancelled: try occurrence.cancel()
            }
            occurrence.calendarEventIdentifier = "mirror-\(index)"
            occurrence.calendarIdentifier = "calendar"
            ids.append(occurrence.id)
            try repository.insert(occurrence)
        }
        let spontaneous = TaskOccurrence(taskID: task.id, actualExecutedAt: start, createdAt: start.addingTimeInterval(10))
        ids.append(spontaneous.id)
        try repository.insert(spontaneous)
        try repository.save()
        let reader = TaskRepository(context: ModelContext(store))
        let fetched = try #require(reader.tasks().first)
        #expect(fetched.id == task.id)
        #expect(fetched.category == "学習")
        #expect(fetched.estimatedDuration == 2700)
        #expect(fetched.createdAt == start)
        let history = try reader.occurrences(for: task.id)
        #expect(history.map(\.id) == ids)
        #expect(history.prefix(4).compactMap(\.planResult) == PlanResult.allCases)
        #expect(history[0].scheduledEnd == start.addingTimeInterval(2700))
        #expect(history[0].calendarEventIdentifier == "mirror-0")
        #expect(history[0].calendarIdentifier == "calendar")
        #expect(history[2].actualExecutedAt == start.addingTimeInterval(9000))
        #expect(history[3].actualExecutedAt == nil)
        #expect(history[4].scheduledStart == nil)
        #expect(history[4].scheduledEnd == nil)
        #expect(history[4].planResult == nil)
        #expect(history[4].actualExecutedAt == start)
        fetched.title = "英語学習"
        try reader.save()
        #expect(try TaskRepository(context: ModelContext(store)).tasks().first?.title == "英語学習")
    }

    @Test func archiveKeepsHistoryAndOnlyDeletesStrictlyFuturePending() throws {
        let store = try container()
        let repository = TaskRepository(context: ModelContext(store))
        let task = Task(title: "読書", createdAt: start)
        let otherTask = Task(title: "別の Task", createdAt: start)
        repository.insert(task)
        repository.insert(otherTask)
        for offset in [-3600.0, 0, 3600] {
            let occurrence = TaskOccurrence(taskID: task.id, scheduledStart: start.addingTimeInterval(offset), createdAt: start)
            occurrence.calendarEventIdentifier = "mirror"
            occurrence.calendarIdentifier = "calendar"
            try repository.insert(occurrence)
        }
        for result in [PlanResult.success, .missed, .cancelled] {
            let occurrence = TaskOccurrence(taskID: task.id, scheduledStart: start.addingTimeInterval(7200), createdAt: start)
            switch result {
            case .success: try occurrence.recordExecution(startedAt: start.addingTimeInterval(7200))
            case .missed: try occurrence.markMissed()
            case .cancelled: try occurrence.cancel()
            case .pending: break
            }
            try repository.insert(occurrence)
        }
        try repository.insert(TaskOccurrence(taskID: task.id, actualExecutedAt: start, createdAt: start))
        try repository.insert(TaskOccurrence(taskID: otherTask.id, scheduledStart: start.addingTimeInterval(3600), createdAt: start))
        try repository.save()
        let removed = try repository.archive(task, at: start)
        #expect(removed.count == 1)
        #expect(removed.first?.eventIdentifier == "mirror")
        #expect(removed.first?.calendarIdentifier == "calendar")
        try repository.save()
        let reader = TaskRepository(context: ModelContext(store))
        #expect(try reader.tasks().map(\.id) == [otherTask.id])
        let allTasks = try reader.tasks(includeArchived: true)
        #expect(allTasks.count == 2)
        #expect(allTasks.first { $0.id == task.id }?.archivedAt == start)
        let history = try reader.occurrences(for: task.id)
        #expect(history.count == 6)
        #expect(history.filter { $0.planResult == .pending }.count == 2)
        #expect(history.first { $0.planResult == .missed }?.actualExecutedAt == nil)
        #expect(!history.contains { $0.id == removed[0].occurrenceID })
        #expect(try reader.occurrences(for: otherTask.id).count == 1)
    }

    @Test func rejectsOrphans() throws {
        let store = try container()
        let context = ModelContext(store)
        context.autosaveEnabled = false
        let repository = TaskRepository(context: context)
        let missingTaskID = UUID()
        #expect(throws: TaskRepository.RepositoryError.self) {
            try repository.insert(TaskOccurrence(taskID: missingTaskID, scheduledStart: start, createdAt: start))
        }
        try repository.save()
        #expect(try repository.occurrences(for: missingTaskID).isEmpty)
    }
}
