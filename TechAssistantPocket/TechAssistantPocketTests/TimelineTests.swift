import Foundation
import Testing
@testable import TechAssistantPocket

struct TimelineTests {
    @Test func mergesOrdinaryEventsAndUsesStartDayForOvernightTasks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let yesterday = today.addingTimeInterval(-3600)
        let overnight = OccurrenceRecord(id: UUID(), taskID: UUID(), start: yesterday,
                                         end: today.addingTimeInterval(3600), result: .pending, actual: nil, mirrorID: "mirror")
        let task = OccurrenceRecord(id: UUID(), taskID: UUID(), start: today.addingTimeInterval(36000),
                                   end: today.addingTimeInterval(37800), result: .pending, actual: nil)
        let mirror = CalendarEvent(identifier: "mirror", calendarIdentifier: "c", title: "Task mirror", start: yesterday, end: today.addingTimeInterval(3600))
        let event = CalendarEvent(identifier: "ordinary", calendarIdentifier: "c", title: "会議", start: today.addingTimeInterval(32400), end: today.addingTimeInterval(34200))
        let entries = Timeline.entries(on: today, records: [overnight, task], events: [mirror, event], calendar: calendar)
        #expect(entries.count == 2)
        #expect(entries.first?.id == "event:" + event.id)
        #expect(entries.last?.id == "task:" + task.id.uuidString)
        #expect(Timeline.entries(on: yesterday, records: [overnight, task], events: [mirror, event], calendar: calendar).count == 1)
    }
}
