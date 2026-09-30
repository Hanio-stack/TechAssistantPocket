import Foundation
import Testing
@testable import TechAssistantPocket

struct ActionAnalyticsTests {
    @Test func countsUseObservedActionTimeNotEstimatedWork() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let proposed = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 13))!
        let actions = [TaskActionFact(taskID: UUID(), genre: " 音楽 ", proposedAt: proposed, occurredAt: proposed.addingTimeInterval(8400), kind: .completed),
                       TaskActionFact(taskID: UUID(), genre: "音楽", proposedAt: proposed, occurredAt: proposed.addingTimeInterval(9 * 3600), kind: .skipped)]
        let summary = ActionAnalyticsEngine.summaries(actions, calendar: calendar)
        #expect(summary.count == 1 && summary[0].completed == 1 && summary[0].skipped == 1)
        #expect(summary[0].hours[15]?.completed == 1 && summary[0].hours[22]?.skipped == 1)
        #expect(summary[0].hours[13] == nil)
        #expect(summary[0].weekdays[6]?.completed == 1)
    }
}
