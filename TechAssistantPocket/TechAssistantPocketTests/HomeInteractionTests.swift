import Foundation
import Testing
@testable import TechAssistantPocket

struct HomeInteractionTests {
    @Test func statesRespectBoundariesAndSavedResults() {
        let start = Date(timeIntervalSince1970: 1000), end = start.addingTimeInterval(3600)
        var record = OccurrenceRecord(id: UUID(), taskID: UUID(), start: start, end: end, result: .pending)
        #expect(OccurrenceDisplayState.resolve(record, now: start.addingTimeInterval(-1)) == .upcoming)
        #expect(OccurrenceDisplayState.resolve(record, now: start) == .active)
        #expect(OccurrenceDisplayState.resolve(record, now: end) == .active)
        #expect(OccurrenceDisplayState.resolve(record, now: end.addingTimeInterval(1)) == .pastPending)
        record.result = .cancelled
        #expect(OccurrenceDisplayState.resolve(record, now: start.addingTimeInterval(-1)) == .cancelled)
        record.result = .success
        #expect(OccurrenceDisplayState.resolve(record, now: start) == .completed)
        record.result = .missed
        #expect(OccurrenceDisplayState.resolve(record, now: start) == .missed)
        record.result = nil; record.actual = start
        #expect(OccurrenceDisplayState.resolve(record, now: end) == .completed)
    }
    @Test func swipeUsesWidthIntentAndProjection() {
        #expect(SwipeDecisionPolicy.direction(x: -100, y: 10, predictedX: -110, width: 375) == 1)
        #expect(SwipeDecisionPolicy.direction(x: 100, y: 10, predictedX: 110, width: 375) == -1)
        #expect(SwipeDecisionPolicy.direction(x: -35, y: 2, predictedX: -250, width: 375) == 1)
        #expect(SwipeDecisionPolicy.direction(x: -15, y: 0, predictedX: -400, width: 375) == 0)
        #expect(SwipeDecisionPolicy.direction(x: 40, y: 2, predictedX: 50, width: 375) == 0)
        #expect(SwipeDecisionPolicy.direction(x: 100, y: 200, predictedX: 450, width: 375) == 0)
        #expect(SwipeDecisionPolicy.direction(x: 100, y: 0, predictedX: 110, width: 800) == 0)
        #expect(SwipeDecisionPolicy.direction(x: 40, y: 0, predictedX: -300, width: 375) == 0)
        #expect(SwipeDecisionPolicy.direction(x: .nan, y: 0, predictedX: 300, width: 375) == 0)
    }
    @Test @MainActor func futureCancellationPreservesHistoryAndExcludesRate() throws {
        let now = Date(), task = UUID()
        let occurrence = TaskOccurrence(taskID: task, scheduledStart: now.addingTimeInterval(3600), duration: 3600)
        let id = occurrence.id
        try occurrence.cancel()
        #expect(occurrence.id == id)
        #expect(occurrence.planResult == .cancelled)
        #expect(occurrence.actualExecutedAt == nil)
        #expect(OccurrenceDisplayState.resolve(occurrence.record, now: now) == .cancelled)
    }
}
