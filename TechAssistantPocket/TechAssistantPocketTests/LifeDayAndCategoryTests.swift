import Foundation
import SwiftData
import Testing
@testable import TechAssistantPocket

struct LifeDayAndCategoryTests {
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        value.firstWeekday = 2
        return value
    }
    func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }
    func record(_ task: UUID, _ start: Date?, _ result: PlanResult?, actual: Date? = nil) -> OccurrenceRecord {
        .init(id: UUID(), taskID: task, start: start, end: start?.addingTimeInterval(1800), result: result, actual: actual)
    }

    @Test func overnightLifeDayBoundariesAndNavigation() {
        let policy = LifeDayPolicy.initial
        #expect(policy.interval(on: date(24), calendar: calendar) == DateInterval(start: date(24, 8), end: date(25, 1, 30)))
        #expect(policy.day(containing: date(25, 0, 45), calendar: calendar) == date(24))
        #expect(policy.contains(date(25, 0, 30), on: date(24), calendar: calendar))
        #expect(!policy.contains(date(25, 1, 30), on: date(24), calendar: calendar))
        #expect(!policy.contains(date(25, 2), on: date(24), calendar: calendar))
        #expect(policy.day(containing: date(25, 2), calendar: calendar) == date(25))
        #expect(policy.shiftedDay(date(24), by: 1, calendar: calendar) == date(25))
        #expect(policy.shiftedDay(date(25), by: -1, calendar: calendar) == date(24))
        let sameDay = LifeDayPolicy(wakeMinutes: 420, bedMinutes: 1410)!
        #expect(sameDay.interval(on: date(24), calendar: calendar) == DateInterval(start: date(24, 7), end: date(24, 23, 30)))
        #expect(sameDay.day(containing: date(24, 23, 30), calendar: calendar) == date(25))
        #expect(LifeDayPolicy(wakeMinutes: 480, bedMinutes: 480) == nil)
        #expect(LifeDayPolicy(wakeMinutes: -1, bedMinutes: 90) == nil)
    }

    @Test func lifeDayTimelineAndAnalyticsAgreeAfterMidnight() {
        let policy = LifeDayPolicy.initial
        let midnight = date(25, 0, 30), task = UUID()
        let plan = record(task, midnight, .success, actual: midnight)
        let event = CalendarEvent(identifier: "event", calendarIdentifier: "a", title: "深夜予定", start: midnight, end: date(25, 1))
        let entries = Timeline.entries(on: date(24), records: [plan], events: [event], calendar: calendar, lifeDay: policy)
        #expect(entries.count == 2)
        #expect(Timeline.entries(on: date(25), records: [plan], events: [event], calendar: calendar, lifeDay: policy).isEmpty)
        let weekdays = CategoryAnalyticsEngine.weekdays([plan], lifeDay: policy, calendar: calendar)
        #expect(weekdays[5]?.successes == 1) // Thursday life day, not Friday.
        #expect(weekdays[6] == nil)
        // Sunday after midnight still belongs to the preceding week when Monday begins.
        let sundayNight = record(task, date(28, 0, 30), .success)
        #expect(CategoryAnalyticsEngine.weeklyRate([sundayNight], now: date(27, 20), lifeDay: policy, calendar: calendar).successes == 1)
        #expect(CategoryAnalyticsEngine.weeklyRate([sundayNight], now: date(28, 8), lifeDay: policy, calendar: calendar).total == 0)
    }

    @Test func daylightSavingUsesCalendarDaysRatherThan86400Seconds() {
        var cal = calendar
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let policy = LifeDayPolicy(wakeMinutes: 480, bedMinutes: 210)!
        let spring = cal.date(from: DateComponents(year: 2026, month: 3, day: 7))!
        let fall = cal.date(from: DateComponents(year: 2026, month: 10, day: 31))!
        #expect(policy.interval(on: spring, calendar: cal).duration == 18.5 * 3600)
        #expect(policy.interval(on: fall, calendar: cal).duration == 20.5 * 3600)
    }

    @Test func categoryAggregatesMultipleTasksWithoutChangingSuccessSemantics() {
        let a = UUID(), b = UUID(), c = UUID()
        let records = [record(a, date(24, 10), .success, actual: date(24, 10)),
                       record(b, date(24, 11), .missed), record(b, date(24, 12), .pending),
                       record(b, date(24, 13), .cancelled), record(b, nil, nil, actual: date(24, 18))]
        let groups = CategoryAnalyticsEngine.summaries(tasks: [.init(id: a, category: " BK進捗 "), .init(id: b, category: "BK進捗"), .init(id: c, category: nil)], records: records)
        let group = groups.first { $0.name == "BK進捗" }!
        #expect(group.taskIDs == [a, b])
        #expect(group.plannedRate == SuccessRate(successes: 1, misses: 1))
        #expect(group.executionCount == 2)
        #expect(group.records == records)
        #expect(CategoryAnalyticsEngine.weekdays(group.records, lifeDay: .initial, calendar: calendar)[5] == SuccessRate(successes: 2, misses: 1))
        #expect(InsightsEngine.timeBands(group.records, calendar: calendar)[.evening]?.successes == 1)
        #expect(groups.first { $0.name == "未分類" }?.taskIDs == [c])
    }

    @Test func newTaskUsesCategoryEvidenceButKeepsItsOwnDuration() {
        let old = UUID(), new = UUID(), unrelated = UUID()
        let monday = date(21, 10), saturday = date(26, 18)
        let failures = (1...3).map { record(old, monday.addingTimeInterval(Double(-7 * $0 * 86400)), .missed) }
        let successes = (1...3).map { record(old, nil, nil, actual: saturday.addingTimeInterval(Double(-7 * $0 * 86400))) }
        var plan = record(new, monday, .pending)
        plan.end = monday.addingTimeInterval(2700)
        let summary = CategoryAnalyticsEngine.summaries(tasks: [.init(id: old, category: "制作"), .init(id: new, category: "制作")], records: failures + successes).first!
        let suggestion = SuggestionEngine.suggest(for: plan, history: summary.records, busy: [], now: date(20), calendar: calendar, taskIDs: summary.taskIDs, lifeDay: .initial)
        #expect(suggestion?.start == saturday)
        #expect(suggestion?.end == saturday.addingTimeInterval(2700))
        #expect(suggestion?.occurrenceID == plan.id)
        #expect(SuggestionEngine.suggest(for: plan, history: summary.records, busy: [], now: date(20), calendar: calendar, taskIDs: [new, unrelated], lifeDay: .initial) == nil)
    }

    @MainActor @Test func lifeSettingsPersistAndImmediatelyRefreshCalendarWithoutChangingHistory() throws {
        let container = try ModelContainer(for: Task.self, TaskOccurrence.self, ReviewRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let suite = "life-hours." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = FixtureCalendarService()
        let store = PocketStore(container: container, calendarService: service, defaults: defaults, notifications: FixtureNotificationService())
        #expect(store.lifeDay == nil)
        let a = Task(title: "A", category: "制作"), b = Task(title: "B", category: "制作")
        let first = TaskOccurrence(taskID: a.id, scheduledStart: date(25, 0, 30))
        let second = TaskOccurrence(taskID: b.id, scheduledStart: date(25, 0, 30))
        #expect(store.perform { store.repository.insert(a); store.repository.insert(b); try store.repository.insert(first); try store.repository.insert(second) })
        #expect(store.perform { try first.recordExecution(startedAt: date(25, 0, 30)) })
        #expect(second.planResult == .pending)
        store.displayDay = date(24)
        service.stored = [CalendarEvent(identifier: "night", calendarIdentifier: "a", title: "深夜", start: date(25, 0, 30), end: date(25, 1))]
        store.setLifeHours(wake: 480, bed: 90)
        #expect(store.events.count == 1)
        store.setLifeHours(wake: 420, bed: 1410)
        #expect(store.events.isEmpty)
        let reopened = PocketStore(container: container, calendarService: service, defaults: defaults, notifications: FixtureNotificationService())
        #expect(reopened.lifeDay == LifeDayPolicy(wakeMinutes: 420, bedMinutes: 1410))
        #expect(reopened.occurrences.count == 2)
        #expect(reopened.categorySummaries.first?.plannedRate.successes == 1)
    }
    @MainActor @Test func mirrorExclusionPrecedesDedupeInStoreAndStaleLifeSuggestionIsRejected() async throws {
        let container = try ModelContainer(for: Task.self, TaskOccurrence.self, ReviewRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let suite = "mirror-life." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = FixtureCalendarService()
        let store = PocketStore(container: container, calendarService: service, defaults: defaults, notifications: FixtureNotificationService())
        store.selectedCalendarID = "fixture"
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let start = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: tomorrow)!
        let task = Task(title: "会議", category: "仕事")
        let plan = TaskOccurrence(taskID: task.id, scheduledStart: start)
        plan.notificationMinutesBefore = nil
        #expect(store.perform { store.repository.insert(task); try store.repository.insert(plan) })
        store.syncMirror(plan, title: task.title)
        service.stored.append(CalendarEvent(identifier: "ordinary", calendarIdentifier: "other", title: task.title, start: start, end: start.addingTimeInterval(1800)))
        store.displayDay = tomorrow
        store.refreshCalendar()
        #expect(store.events.map(\.identifier) == ["ordinary"])
        #expect(store.saveTask(task, title: "会議準備", category: "仕事", estimatedDuration: nil, editing: plan, scheduledStart: start, duration: 1800, reminder: nil))
        #expect(plan.notificationMinutesBefore == nil)
        #expect(store.occurrences.count == 1)
        let candidate = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: tomorrow)!
        let suggestion = ScheduleSuggestion(occurrenceID: plan.id, start: candidate, end: candidate.addingTimeInterval(1800), currentEvidence: .init(successes: 0, misses: 3), proposedEvidence: .init(successes: 3, misses: 0))
        store.setLifeHours(wake: 480, bed: 1320)
        await store.applySuggestion(suggestion)
        #expect(plan.scheduledStart == start)
        #expect(store.errorMessage == "生活時間が変更されています。提案を更新してください。")
    }

}
