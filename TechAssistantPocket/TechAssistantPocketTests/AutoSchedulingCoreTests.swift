import Foundation
import Testing
@testable import TechAssistantPocket

struct AutoSchedulingCoreTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: "Asia/Tokyo")!; return value
    }
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }
    private var policy: WorkWindowPolicy {
        WorkWindowPolicy(weekday: WorkClockRange(startMinutes: 780, endMinutes: 960),
                         weekend: WorkClockRange(startMinutes: 600, endMinutes: 1080))
    }
    @Test(arguments: [25, 26, 27]) func weekdayAndWeekend(day: Int) {
        let weekend = day != 25
        #expect(policy.currentWindow(at: date(day, 14), calendar: calendar) == DateInterval(start: date(day, weekend ? 10 : 13), end: date(day, weekend ? 18 : 16)))
    }
    @Test(arguments: [12, 13, 14, 16, 17]) func beforeDuringAndAfter(hour: Int) {
        let remaining = policy.remaining(at: date(25, hour), calendar: calendar)
        if (13..<16).contains(hour) { #expect(remaining == DateInterval(start: date(25, hour), end: date(25, 16))) }
        else { #expect(remaining == nil) }
    }
    @Test func overnightUsesStartWeekday() {
        let overnight = WorkWindowPolicy(weekday: WorkClockRange(startMinutes: 1260, endMinutes: 120), weekend: WorkClockRange(startMinutes: 600, endMinutes: 1080))
        #expect(overnight.currentWindow(at: date(26, 1), calendar: calendar) == DateInterval(start: date(25, 21), end: date(26, 2)))
        #expect(overnight.currentWindow(at: date(26, 2), calendar: calendar) == nil)
        #expect(overnight.currentWindow(at: date(25, 20), calendar: calendar) == nil)
    }
    @Test func invalidClockRangesAreRejected() {
        #expect(!WorkClockRange(startMinutes: 0, endMinutes: 0).isValid)
        #expect(!WorkClockRange(startMinutes: -1, endMinutes: 1440).isValid)
    }
    @Test func packingClipsMergesAndAvoidsAllBusyIntervals() {
        let window = DateInterval(start: date(25, 13), end: date(25, 20))
        let busy = [DateInterval(start: date(25, 15), end: date(25, 16)), DateInterval(start: date(25, 18), end: date(25, 19)), DateInterval(start: date(25, 15, 30), end: date(25, 16)), DateInterval(start: date(25, 10), end: date(25, 12))]
        #expect(SchedulePackingEngine.freeIntervals(in: window, busy: busy) == [DateInterval(start: date(25, 13), end: date(25, 15)), DateInterval(start: date(25, 16), end: date(25, 18)), DateInterval(start: date(25, 19), end: date(25, 20))])
        #expect(SchedulePackingEngine.availableNow(at: date(25, 15), window: window, busy: busy) == nil)
        #expect(SchedulePackingEngine.availableNow(at: date(25, 16), window: window, busy: busy)?.end == date(25, 18))
        #expect(SchedulePackingEngine.availableNow(at: date(25, 12), window: window, busy: busy) == nil)
        #expect(SchedulePackingEngine.freeIntervals(in: window, busy: [DateInterval(start: date(25, 12), end: date(25, 21))]).isEmpty)
    }
    private func candidate(_ priority: Int, _ minutes: Int, age: Int = 0) -> SchedulingCandidate {
        SchedulingCandidate(id: UUID(), priority: priority, estimatedMinutes: minutes, createdAt: date(25, 10).addingTimeInterval(Double(age)))
    }
    @Test func priorityThenOldestWins() {
        let low = candidate(1, 30), medium = candidate(2, 30), high = candidate(3, 30, age: 10), newer = candidate(3, 30, age: 20)
        let available = DateInterval(start: date(25, 13), end: date(25, 16))
        #expect(TaskSelectionEngine.select(from: [newer, medium, low, high], available: available) == high)
    }
    @Test(arguments: [5, 30, 180]) func exactDurationBoundary(minutes: Int) {
        let task = candidate(3, minutes)
        let start = date(25, 13)
        #expect(TaskSelectionEngine.select(from: [task], available: DateInterval(start: start, duration: Double(minutes * 60))) == task)
        #expect(TaskSelectionEngine.select(from: [task], available: DateInterval(start: start, duration: Double(minutes * 60 - 1))) == nil)
    }
    @Test func invalidEstimatesNeverEnterSelection() {
        let tasks = [candidate(3, 0), candidate(3, 4), candidate(3, 181), candidate(3, 31), candidate(4, 30)]
        #expect(TaskSelectionEngine.select(from: tasks, available: DateInterval(start: date(25, 13), end: date(25, 16))) == nil)
    }
    @Test func earlyCompletionRecalculatesFromActualClockWithoutMeasuringWork() {
        let animation = candidate(3, 180), music = candidate(2, 60), reading = candidate(1, 30)
        let window = policy.currentWindow(at: date(25, 13), calendar: calendar)!
        #expect(TaskSelectionEngine.select(from: [reading, music, animation], available: window) == animation)
        let remaining = SchedulePackingEngine.availableNow(at: date(25, 15, 20), window: window, busy: [])!
        #expect(remaining.duration == 40 * 60)
        #expect(TaskSelectionEngine.select(from: [music, reading], available: remaining) == reading)
        #expect(TaskSelectionEngine.select(from: [music], available: remaining) == nil)
    }
    @Test func skipPersistsAcrossRecalculationButReturnsAfterAnotherActionOrSession() {
        let first = candidate(3, 30), second = candidate(2, 30), window = DateInterval(start: date(25, 13), end: date(25, 16))
        let skipped = SelectionAction(taskID: first.id, kind: .skipped, sessionStart: window.start)
        let excluded = TaskSelectionEngine.excludedTask(lastAction: skipped, sessionStart: window.start)
        #expect(TaskSelectionEngine.select(from: [first, second], available: window, excluding: excluded) == second)
        #expect(TaskSelectionEngine.select(from: [first], available: window, excluding: excluded) == nil)
        #expect(TaskSelectionEngine.excludedTask(lastAction: skipped, sessionStart: date(26, 10)) == nil)
        let completed = SelectionAction(taskID: second.id, kind: .completed, sessionStart: window.start)
        #expect(TaskSelectionEngine.excludedTask(lastAction: completed, sessionStart: window.start) == nil)
        #expect(TaskSelectionEngine.select(from: [first], available: window) == first)
    }
}
