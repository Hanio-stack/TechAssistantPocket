import Foundation
import SwiftData
import Testing
@testable import TechAssistantPocket

@MainActor struct SchedulerPersistenceTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func memory() throws -> SchedulerRepository {
        SchedulerRepository(container: try PocketSchedulerSchema.container(configuration: ModelConfiguration(isStoredInMemoryOnly: true)))
    }
    @Test func completionAndSkipSaveFactsAtomicallyWithoutChangingLegacyHistory() throws {
        let repository = try memory()
        let task = try repository.saveTask(title: "  制作  ", genre: "  BK  ", priority: 3, minutes: 180, now: now)
        let state = try #require(repository.states().first)
        #expect(task.title == "制作" && task.category == "BK")
        let proposal = TaskProposal(task: task, state: state, at: now, sessionStart: now)
        try repository.transaction { repository.context.insert(proposal) }
        try repository.record(.skipped, proposalID: proposal.id, at: now.addingTimeInterval(10))
        #expect(state.completedAt == nil)
        let second = TaskProposal(task: task, state: state, at: now.addingTimeInterval(20), sessionStart: now)
        try repository.transaction { repository.context.insert(second) }
        let completedAt = now.addingTimeInterval(8400)
        try repository.record(.completed, proposalID: second.id, at: completedAt)
        #expect(state.completedAt == completedAt)
        let actions = try repository.actions()
        #expect(actions.map(\.kind) == [.skipped, .completed])
        #expect(actions.map(\.occurredAt) == [now.addingTimeInterval(10), completedAt])
        #expect(actions.map(\.proposedAt) == [now, now.addingTimeInterval(20)])
        #expect(actions.map(\.sequence) == [1, 2])
        #expect(try repository.legacyOccurrences().isEmpty)
        #expect(throws: SchedulerRepository.Failure.self) { try repository.record(.completed, proposalID: second.id, at: completedAt) }
        #expect(try repository.actions().count == 2)
        let fields = try #require(PocketSchedulerSchema.schema.entities.first { $0.name == "TaskActionRecord" }).properties.map(\.name)
        #expect(!fields.contains { $0.lowercased().contains("duration") || $0.lowercased().contains("elapsed") || $0.lowercased().contains("actual") })
    }
    @Test func editsRetainTaskIdentityAndInvalidateOnlyAllocation() throws {
        let repository = try memory()
        let task = try repository.saveTask(title: "制作", genre: "BK", priority: 2, minutes: 60, now: now)
        let state = try #require(repository.states().first)
        let proposal = TaskProposal(task: task, state: state, at: now, sessionStart: now)
        try repository.transaction { repository.context.insert(proposal) }
        let edited = try repository.saveTask(existing: task, title: "動画", genre: "制作", priority: 3, minutes: 30, now: now.addingTimeInterval(60))
        #expect(edited.id == task.id)
        #expect(try repository.tasks().count == 1 && repository.states().count == 1)
        #expect(proposal.closedAt == now.addingTimeInterval(60))
        #expect(try repository.actions().isEmpty)
    }
    @Test func oldStoreOpensWithAdditiveSchemaAndNewFactsSurviveRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("pocket.store")
        let taskID = UUID(), occurrenceID = UUID()
        try autoreleasepool {
            let old = try ModelContainer(for: Task.self, TaskOccurrence.self, ReviewRecord.self, configurations: ModelConfiguration(url: url))
            let context = ModelContext(old)
            context.insert(Task(id: taskID, title: "旧Task", category: "履歴", createdAt: now))
            let occurrence = TaskOccurrence(id: occurrenceID, taskID: taskID, scheduledStart: now)
            try occurrence.recordExecution(startedAt: now)
            context.insert(occurrence)
            context.insert(ReviewRecord(dateKey: "2026-09-25", reviewedAt: now))
            try context.save()
        }
        try autoreleasepool {
            let repository = SchedulerRepository(container: try PocketSchedulerSchema.container(configuration: ModelConfiguration(url: url)))
            #expect(try repository.tasks().first?.id == taskID)
            #expect(try repository.states().isEmpty) // No automatic resurrection into the backlog.
            let history = try #require(repository.legacyOccurrences().first)
            #expect(history.id == occurrenceID && history.planResult == .success && history.actualExecutedAt == now)
            #expect(try repository.context.fetch(FetchDescriptor<ReviewRecord>()).count == 1)
            let new = try repository.saveTask(title: "新Task", genre: "音楽", priority: 3, minutes: 30, now: now)
            let proposal = TaskProposal(task: new, state: try #require(repository.states().first), at: now, sessionStart: now)
            try repository.transaction { repository.context.insert(proposal) }
            try repository.record(.completed, proposalID: proposal.id, at: now.addingTimeInterval(60))
        }
        try autoreleasepool {
            let repository = SchedulerRepository(container: try PocketSchedulerSchema.container(configuration: ModelConfiguration(url: url)))
            #expect(try repository.tasks().count == 2)
            #expect(try repository.states().first?.completedAt == now.addingTimeInterval(60))
            #expect(try repository.actions().first?.kind == .completed)
            #expect(try repository.legacyOccurrences().first?.id == occurrenceID)
        }
    }
}
