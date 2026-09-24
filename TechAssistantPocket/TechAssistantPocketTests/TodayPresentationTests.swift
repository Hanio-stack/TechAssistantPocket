import Foundation
import Testing
@testable import TechAssistantPocket

struct TodayPresentationTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return value
    }
    private var day: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 21))! }
    private func time(_ hour: Int) -> Date { day.addingTimeInterval(Double(hour) * 3600) }
    private func plan(_ hour: Int, result: PlanResult = .pending) -> OccurrenceRecord {
        OccurrenceRecord(id: UUID(), taskID: UUID(), start: time(hour), end: time(hour).addingTimeInterval(1800),
                         result: result, actual: result == .success ? time(hour) : nil)
    }
    private func event(_ id: String, start: Date, end: Date, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(identifier: id, calendarIdentifier: "personal", title: id, start: start, end: end, isAllDay: allDay)
    }

    @Test func completedTasksAndEndedEventsDoNotPushCurrentTaskDown() {
        let completed = (8...10).map { plan($0, result: .success) }
        let current = plan(16), next = plan(17), overdue = plan(11)
        let records = completed + [current, next, overdue]
        let originalRate = InsightsEngine.plannedRate(records)
        let ended = event("ended-at-noon", start: time(11), end: time(12))
        let meeting = event("meeting", start: time(18), end: time(19))
        let result = Timeline.presentation(on: day, now: time(16), records: records, events: [meeting, ended], calendar: calendar)
        #expect(result.upcoming.map(\.start) == [time(16), time(17), time(18)])
        #expect(result.focus?.id == Timeline.Entry.task(current).id)
        #expect(result.history.count == 4)
        #expect(result.unresolved == [.task(overdue)])
        #expect(overdue.result == .pending)
        #expect(InsightsEngine.plannedRate(records) == originalRate)
        #expect(originalRate == SuccessRate(successes: 3, misses: 0))
        #expect(result.upcoming.count + result.history.count + result.unresolved.count == records.count + 2)
    }

    @Test func nextTimedActionIsFocusedWhilePersonalAllDayEventIsRetained() {
        let next = plan(17)
        let allDay = event("personal-all-day", start: day, end: time(24), allDay: true)
        let result = Timeline.presentation(on: day, now: time(16), records: [next], events: [allDay], calendar: calendar)
        #expect(result.upcoming == [.event(allDay), .task(next)])
        #expect(result.focus == .task(next))
        #expect(result.focus?.isCurrent(at: time(16)) == false)
        let onlyAllDay = Timeline.presentation(on: day, now: time(16), records: [], events: [allDay], calendar: calendar)
        #expect(onlyAllDay.focus == .event(allDay))
    }

    @Test func currentOrdinaryEventAndTaskAreOneChronologicalTimeline() {
        let next = plan(17)
        let ongoing = event("ongoing", start: time(15), end: time(17))
        let result = Timeline.presentation(on: day, now: time(16), records: [next], events: [ongoing], calendar: calendar)
        #expect(result.focus == .event(ongoing))
        #expect(result.upcoming == [.event(ongoing), .task(next)])
    }

    @Test func eventEndIsExclusiveButTaskResolutionWindowRemainsInclusive() {
        let task = plan(16)
        let meeting = event("meeting", start: time(16), end: task.end!)
        let boundary = Timeline.presentation(on: day, now: task.end!, records: [task], events: [meeting], calendar: calendar)
        #expect(boundary.upcoming == [.task(task)])
        #expect(boundary.history == [.event(meeting)])
        #expect(boundary.focus?.isCurrent(at: task.end!) == true)
        let expired = Timeline.presentation(on: day, now: task.end!.addingTimeInterval(0.001), records: [task], events: [], calendar: calendar)
        #expect(expired.upcoming.isEmpty)
        #expect(expired.unresolved == [.task(task)])
        #expect(task.result == .pending)
    }

    @Test func resolutionMovesFocusAndRetainsAllResolvedStatuses() {
        let current = plan(16), next = plan(17)
        for status in [PlanResult.success, .missed, .cancelled] {
            var resolved = current
            resolved.result = status
            let result = Timeline.presentation(on: day, now: time(16), records: [resolved, next], events: [], calendar: calendar)
            #expect(result.focus == .task(next))
            #expect(result.history == [.task(resolved)])
            #expect(Timeline.hasNewlyResolvedTask(before: [current, next], after: [resolved, next]))
        }
        var refreshed = current
        refreshed.mirrorID = "new-mirror-id"
        #expect(!Timeline.hasNewlyResolvedTask(before: [current], after: [refreshed]))
        #expect(!Timeline.hasNewlyResolvedTask(before: [current], after: []))
        #expect(!Timeline.hasNewlyResolvedTask(before: [current], after: [current, next]))
    }

    @Test func dateOwnershipTimezoneAndUnscheduledExecutionAreUnchanged() {
        var overnight = plan(23)
        overnight.end = time(25)
        let spontaneous = OccurrenceRecord(id: UUID(), taskID: UUID(), start: nil, end: nil, result: nil, actual: time(16))
        let mirror = CalendarEvent(identifier: "mirror", calendarIdentifier: "personal", title: "mirror", start: time(23), end: time(25))
        overnight.mirrorID = "mirror"
        let current = Timeline.presentation(on: day, now: time(24), records: [overnight, spontaneous], events: [mirror], calendar: calendar)
        #expect(current.upcoming == [.task(overnight)])
        #expect(Timeline.presentation(on: time(24), now: time(24), records: [overnight], events: [mirror], calendar: calendar).upcoming.isEmpty)
        var losAngeles = calendar
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let early = plan(1)
        let japan = Timeline.entries(on: time(16), records: [early], events: [], calendar: calendar)
        let america = Timeline.entries(on: time(16), records: [early], events: [], calendar: losAngeles)
        #expect(japan.count == 1)
        #expect(america.isEmpty)
    }

    @Test(arguments: [DateComponents(year: 2026, month: 3, day: 8), DateComponents(year: 2026, month: 11, day: 1)])
    func allDayEventsUseLocalDayAcrossDST(components: DateComponents) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let day = calendar.date(from: components)!
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
        let event = event("personal", start: day, end: nextDay, allDay: true)
        let now = calendar.date(bySettingHour: 16, minute: 0, second: 0, of: day)!
        #expect(Timeline.presentation(on: day, now: now, records: [], events: [event], calendar: calendar).upcoming == [.event(event)])
        #expect(Timeline.presentation(on: day, now: nextDay, records: [], events: [event], calendar: calendar).history == [.event(event)])
        #expect(Timeline.entries(on: nextDay, records: [], events: [event], calendar: calendar).isEmpty)
    }
}
