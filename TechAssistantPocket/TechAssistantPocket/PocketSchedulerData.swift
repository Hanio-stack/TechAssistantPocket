import Foundation
import SwiftData

/// Additive metadata: legacy Task and TaskOccurrence retain their original meanings.
@Model final class BacklogTaskState {
    @Attribute(.unique) var taskID: UUID
    var priority: Int
    var estimatedMinutes: Int
    var completedAt: Date?
    init(taskID: UUID, priority: Int, estimatedMinutes: Int) {
        self.taskID = taskID; self.priority = priority; self.estimatedMinutes = estimatedMinutes
    }
}

/// Allocation metadata for Calendar synchronization, never a measurement of work.
@Model final class TaskProposal {
    @Attribute(.unique) var id: UUID
    var taskID: UUID
    var title: String
    var genre: String
    var priority: Int
    var proposedAt: Date
    var plannedEnd: Date
    var sessionStart: Date
    var closedAt: Date?
    var mirrorID: String?
    var calendarID: String?
    var needsSync: Bool
    init(task: Task, state: BacklogTaskState, at now: Date, sessionStart: Date) {
        id = UUID(); taskID = task.id; title = task.title; genre = task.category ?? ""
        priority = state.priority; proposedAt = now
        plannedEnd = now.addingTimeInterval(Double(state.estimatedMinutes * 60))
        self.sessionStart = sessionStart; needsSync = true
    }
    var allocationEnd: Date { min(plannedEnd, closedAt ?? plannedEnd) }
}

/// Observed user actions only. No actual/elapsed work-duration field.
@Model final class TaskActionRecord {
    @Attribute(.unique) var proposalID: UUID
    var taskID: UUID
    var title: String
    var genre: String
    var priority: Int
    var proposedAt: Date
    var occurredAt: Date
    var kindRaw: String
    var sessionStart: Date
    var sequence: Int
    init(proposal: TaskProposal, kind: TaskActionKind, at now: Date, sequence: Int) {
        proposalID = proposal.id; taskID = proposal.taskID; title = proposal.title
        genre = proposal.genre; priority = proposal.priority; proposedAt = proposal.proposedAt
        occurredAt = now; kindRaw = kind.rawValue; sessionStart = proposal.sessionStart; self.sequence = sequence
    }
    var kind: TaskActionKind? { TaskActionKind(rawValue: kindRaw) }
    var selectionAction: SelectionAction? { kind.map { SelectionAction(taskID: taskID, kind: $0, sessionStart: sessionStart) } }
}

@MainActor enum PocketSchedulerSchema {
    static var schema: Schema { Schema([Task.self, TaskOccurrence.self, ReviewRecord.self, BacklogTaskState.self, TaskProposal.self, TaskActionRecord.self]) }
    static func container(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: [configuration])
    }
}

nonisolated struct SchedulerSettings: Codable, Equatable {
    var wakeMinutes: Int
    var bedMinutes: Int
    var work: WorkWindowPolicy
    var isValid: Bool { LifeDayPolicy(wakeMinutes: wakeMinutes, bedMinutes: bedMinutes) != nil && work.isValid }
    static let initial = SchedulerSettings(wakeMinutes: 480, bedMinutes: 90,
        work: WorkWindowPolicy(weekday: WorkClockRange(startMinutes: 1260, endMinutes: 60),
                               weekend: WorkClockRange(startMinutes: 780, endMinutes: 1080)))
}

@MainActor final class SchedulerRepository {
    let context: ModelContext
    init(container: ModelContainer) { context = ModelContext(container); context.autosaveEnabled = false }
    func tasks() throws -> [Task] { try context.fetch(FetchDescriptor<Task>(sortBy: [SortDescriptor(\Task.createdAt)])) }
    func states() throws -> [BacklogTaskState] { try context.fetch(FetchDescriptor<BacklogTaskState>()) }
    func proposals() throws -> [TaskProposal] { try context.fetch(FetchDescriptor<TaskProposal>()) }
    func actions() throws -> [TaskActionRecord] { try context.fetch(FetchDescriptor<TaskActionRecord>(sortBy: [SortDescriptor(\TaskActionRecord.sequence)])) }
    func legacyOccurrences() throws -> [TaskOccurrence] { try context.fetch(FetchDescriptor<TaskOccurrence>()) }

    /// All local changes are committed together; failures roll back the dedicated context.
    func transaction(_ operation: () throws -> Void) throws {
        do { try operation(); try context.save() }
        catch { context.rollback(); throw error }
    }

    @discardableResult func saveTask(existing: Task? = nil, title: String, genre: String, priority: Int,
                                    minutes: Int, now: Date) throws -> Task {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let genre = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, SchedulingCandidate(id: UUID(), priority: priority, estimatedMinutes: minutes, createdAt: now).isValid else { throw Failure.invalidTask }
        let task = existing ?? Task(title: title, createdAt: now)
        try transaction {
            if existing == nil { context.insert(task) }
            task.title = title; task.category = genre.isEmpty ? nil : genre
            if let state = try states().first(where: { $0.taskID == task.id }) {
                guard state.completedAt == nil, task.archivedAt == nil else { throw Failure.inactiveTask }
                state.priority = priority; state.estimatedMinutes = minutes
            } else {
                guard task.archivedAt == nil else { throw Failure.inactiveTask }
                context.insert(BacklogTaskState(taskID: task.id, priority: priority, estimatedMinutes: minutes))
            }
            // Editing invalidates the allocation without inventing an action fact.
            for proposal in try proposals() where proposal.taskID == task.id && proposal.closedAt == nil {
                proposal.closedAt = max(proposal.proposedAt, now); proposal.needsSync = true
            }
        }
        return task
    }

    func record(_ kind: TaskActionKind, proposalID: UUID, at now: Date) throws {
        try transaction {
            let history = try actions()
            guard !history.contains(where: { $0.proposalID == proposalID }),
                  let proposal = try proposals().first(where: { $0.id == proposalID && $0.closedAt == nil }),
                  let state = try states().first(where: { $0.taskID == proposal.taskID && $0.completedAt == nil }),
                  let task = try tasks().first(where: { $0.id == state.taskID && $0.archivedAt == nil }),
                  now >= proposal.proposedAt else { throw Failure.inactiveTask }
            _ = task
            context.insert(TaskActionRecord(proposal: proposal, kind: kind, at: now, sequence: (history.last?.sequence ?? 0) + 1))
            proposal.closedAt = now; proposal.needsSync = true
            if kind == .completed { state.completedAt = now }
        }
    }

    func archive(_ task: Task, at now: Date) throws {
        try transaction {
            task.archivedAt = now
            for proposal in try proposals() where proposal.taskID == task.id && proposal.closedAt == nil {
                proposal.closedAt = max(now, proposal.proposedAt); proposal.needsSync = true
            }
        }
    }
    enum Failure: LocalizedError {
        case invalidTask, inactiveTask
        var errorDescription: String? {
            switch self {
            case .invalidTask: "内容・優先度1〜3・想定時間5〜180分（5分刻み）を確認してください。"
            case .inactiveTask: "このTaskの状態が変わりました。Homeを更新してください。"
            }
        }
    }
}
