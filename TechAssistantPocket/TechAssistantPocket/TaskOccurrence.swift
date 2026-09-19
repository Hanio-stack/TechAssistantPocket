import Foundation
import SwiftData

@Model
final class TaskOccurrence {
    @Attribute(.unique) var id: UUID
    var taskID: UUID
    private(set) var scheduledStart: Date?
    private(set) var scheduledEnd: Date?
    private(set) var planResult: PlanResult?
    /// Actual start time supplied by the user, never the completion-button time.
    private(set) var actualExecutedAt: Date?
    var calendarEventIdentifier: String?
    var calendarIdentifier: String?
    var createdAt: Date

    /// Scheduled occurrence. No clock-driven result transitions occur.
    init(id: UUID = UUID(), taskID: UUID, scheduledStart: Date,
         duration: TimeInterval = 30 * 60, createdAt: Date = Date()) {
        precondition(duration.isFinite && duration > 0)
        self.id = id
        self.taskID = taskID
        self.scheduledStart = scheduledStart
        self.scheduledEnd = scheduledStart.addingTimeInterval(duration)
        self.planResult = .pending
        self.createdAt = createdAt
    }

    /// Spontaneous execution has no scheduled plan and no plan result.
    init(id: UUID = UUID(), taskID: UUID, actualExecutedAt: Date,
         createdAt: Date = Date()) {
        self.id = id
        self.taskID = taskID
        self.actualExecutedAt = actualExecutedAt
        self.createdAt = createdAt
    }

    // Phase 1 only resolves pending plans. Corrections and rescheduling are deferred.
    func recordExecution(startedAt: Date) throws {
        try requirePendingPlan()
        guard let scheduledStart, let scheduledEnd else { throw ResolutionError.notPending }
        actualExecutedAt = startedAt
        planResult = (scheduledStart...scheduledEnd).contains(startedAt) ? .success : .missed
    }

    func markMissed() throws {
        try requirePendingPlan()
        planResult = .missed
    }

    func cancel() throws {
        try requirePendingPlan()
        planResult = .cancelled
    }

    private func requirePendingPlan() throws {
        guard planResult == .pending else { throw ResolutionError.notPending }
    }

    enum ResolutionError: Error {
        case notPending
    }
}
