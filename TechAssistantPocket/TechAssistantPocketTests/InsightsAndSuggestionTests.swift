import Foundation
import Testing
@testable import TechAssistantPocket

struct InsightsAndSuggestionTests {
    let taskID = UUID()
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }
    var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 10))! }
    func record(_ start: Date?, _ result: PlanResult?, actual: Date? = nil) -> OccurrenceRecord {
        OccurrenceRecord(id: UUID(), taskID: taskID, start: start, end: start?.addingTimeInterval(1800), result: result, actual: actual)
    }
    @Test func plannedDenominatorExcludesUnscheduledPendingAndCancelled() {
        let records = [record(monday, .success, actual: monday), record(monday, .missed),
                       record(monday, .missed, actual: monday.addingTimeInterval(8 * 3600)),
                       record(nil, nil, actual: monday), record(monday, .cancelled), record(monday, .pending)]
        let result = InsightsEngine.plannedRate(records)
        #expect(result.successes == 1)
        #expect(result.misses == 2)
        #expect(result.total == 3)
        #expect(result.rate == 1.0 / 3.0)
        #expect(InsightsEngine.plannedRate([]).rate == nil)
        let week = InsightsEngine.week(containing: monday, calendar: calendar)
        let boundary = [record(week.start, .success), record(week.end, .missed), record(week.start.addingTimeInterval(-1), .missed)]
        #expect(InsightsEngine.plannedRate(boundary, interval: week).total == 1)
    }
    @Test func actualExecutionTendenciesAndNoDoubleCounting() {
        let evening = monday.addingTimeInterval(8 * 3600)
        let records = [record(monday, .success, actual: monday.addingTimeInterval(300)), record(monday, .missed),
                       record(monday, .missed, actual: evening), record(nil, nil, actual: evening)]
        let bands = InsightsEngine.timeBands(records, calendar: calendar)
        #expect(bands[.morning] == SuccessRate(successes: 1, misses: 2))
        #expect(bands[.evening] == SuccessRate(successes: 2, misses: 0))
        #expect(InsightsEngine.weekdays(records, calendar: calendar)[2] == SuccessRate(successes: 3, misses: 2))
        // A miss followed by execution in the same band retains both observations.
        let lateInSameBand = record(monday, .missed, actual: monday.addingTimeInterval(3600))
        #expect(InsightsEngine.timeBands([lateInSameBand], calendar: calendar)[.morning] == SuccessRate(successes: 1, misses: 1))
    }
    @Test func suggestionRequiresBothEvidenceAndFreeTime() {
        let plan = record(monday, .pending)
        let saturday = monday.addingTimeInterval(5 * 86400)
        let now = monday.addingTimeInterval(-86400)
        let failures = (1...3).map { record(monday.addingTimeInterval(Double(-7 * $0 * 86400)), .missed) }
        let successes = (1...3).map { record(nil, nil, actual: saturday.addingTimeInterval(Double(-7 * $0 * 86400))) }
        #expect(SuggestionEngine.suggest(for: plan, history: Array(failures.prefix(2)) + successes, busy: [], now: now, calendar: calendar) == nil)
        #expect(SuggestionEngine.suggest(for: plan, history: failures + Array(successes.prefix(2)), busy: [], now: now, calendar: calendar) == nil)
        let suggestion = SuggestionEngine.suggest(for: plan, history: failures + successes, busy: [], now: now, calendar: calendar)
        #expect(suggestion?.start == saturday)
        #expect(suggestion?.end == saturday.addingTimeInterval(1800))
        #expect(suggestion?.proposedEvidence.successes == 3)
        #expect(SuggestionEngine.suggest(for: plan, history: failures + successes,
                                         busy: [DateInterval(start: now, duration: 15 * 86400)], now: now, calendar: calendar) == nil)
        #expect(SuggestionEngine.isFree(start: saturday, end: saturday.addingTimeInterval(1800), busy: [DateInterval(start: saturday.addingTimeInterval(-1800), end: saturday)]))
        let otherTask = failures.map { OccurrenceRecord(id: $0.id, taskID: UUID(), start: $0.start, end: $0.end, result: $0.result, actual: nil) }
        #expect(SuggestionEngine.suggest(for: plan, history: otherTask + successes, busy: [], now: now, calendar: calendar) == nil)
    }
}
