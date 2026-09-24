#if DEBUG
import Foundation

/// Deterministic, isolated services used only by explicit UI-test launch arguments.
/// Neither service requests permissions nor reads/writes the user's calendars or notifications.
@MainActor final class FixtureCalendarService: CalendarService {
    var access: CalendarAccess = .full
    var choices = [CalendarChoice(id: "fixture", title: "テスト用カレンダー", source: "端末内")]
    var stored: [CalendarEvent] = []
    var failWrites = false
    var failDeletes = false
    var ordinaryAlarm: Int?
    func requestAccess() async throws -> Bool { access == .full }
    func calendars() -> [CalendarChoice] { access == .full ? choices : [] }
    func events(from start: Date, to end: Date) throws -> [CalendarEvent] {
        guard access == .full else { throw CalendarFailure.accessRequired }
        return CalendarReadPolicy.visibleEvents(stored.filter { $0.start < end && $0.end > start })
    }
    func mirrorExists(_ identifier: String) throws -> Bool {
        guard access == .full else { throw CalendarFailure.accessRequired }
        return stored.contains { $0.identifier == identifier }
    }
    func saveMirror(title: String, occurrenceID: UUID, start: Date, end: Date, existingID: String?, calendarID: String?) throws -> MirrorReference {
        guard access == .full else { throw CalendarFailure.accessRequired }
        guard let calendarID, choices.contains(where: { $0.id == calendarID }), !failWrites else { throw CalendarFailure.calendarUnavailable }
        let id = existingID ?? UUID().uuidString
        stored.removeAll { $0.identifier == id }
        stored.append(CalendarEvent(identifier: id, calendarIdentifier: calendarID, title: title, start: start, end: end))
        return MirrorReference(occurrenceID: occurrenceID, eventIdentifier: id, calendarIdentifier: calendarID)
    }
    func removeMirror(_ reference: MirrorReference) throws {
        guard !failDeletes else { throw CalendarFailure.calendarUnavailable }
        stored.removeAll { $0.identifier == reference.eventIdentifier }
    }
    func createEvent(title: String, start: Date, end: Date, calendarID: String?, reminderMinutes: Int?) throws {
        guard let calendarID, choices.contains(where: { $0.id == calendarID }), !failWrites else { throw CalendarFailure.calendarUnavailable }
        guard end > start else { throw CalendarFailure.invalidDates }
        ordinaryAlarm = reminderMinutes
        stored.append(CalendarEvent(identifier: UUID().uuidString, calendarIdentifier: calendarID, title: title, start: start, end: end))
    }
}

@MainActor final class FixtureNotificationService: NotificationScheduling {
    var authorized = true
    var scheduled: [UUID: TaskReminder] = [:]
    func requestAccess() async throws -> Bool { authorized }
    func isAuthorized() async -> Bool { authorized }
    func schedule(_ reminder: TaskReminder) async throws { scheduled[reminder.occurrenceID] = reminder }
    func remove(occurrenceID: UUID) { scheduled.removeValue(forKey: occurrenceID) }
}

@MainActor enum DebugFixtures {
    static var todayReferenceTime: Date {
        Calendar.current.date(bySettingHour: 16, minute: 0, second: 0, of: Date())!
    }

    static func seedTodayFocus(_ store: PocketStore, includeCurrent: Bool) {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: todayReferenceTime)
        func time(_ hour: Int) -> Date { calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)! }
        store.perform {
            for hour in 6..<10 {
                let task = Task(title: "完了したTask\(hour)")
                store.repository.insert(task)
                let occurrence = TaskOccurrence(taskID: task.id, scheduledStart: time(hour))
                try occurrence.recordExecution(startedAt: time(hour))
                try store.repository.insert(occurrence)
            }
            for hour in [11, 16, 17, 18] where includeCurrent || hour != 16 {
                let task = Task(title: "\(hour)時のTask")
                store.repository.insert(task)
                try store.repository.insert(TaskOccurrence(taskID: task.id, scheduledStart: time(hour)))
            }
        }
        if let fixture = store.calendarService as? FixtureCalendarService {
            fixture.stored += [
                CalendarEvent(identifier: "ended", calendarIdentifier: "fixture", title: "12時に終了した予定", start: time(11), end: time(12)),
                CalendarEvent(identifier: "personal-all-day", calendarIdentifier: "fixture", title: "自分の終日予定", start: day,
                              end: calendar.date(byAdding: .day, value: 1, to: day)!, isAllDay: true)
            ]
            for source in ["apple", "google"] {
                let metadata = CalendarMetadata(identifier: source, title: "日本の祝日", sourceIdentifier: source,
                                                sourceTitle: source, sourceKind: .calDAV, isSubscribed: source == "apple",
                                                allowsContentModifications: false)
                fixture.stored.append(CalendarEvent(identifier: source + "-holiday", calendarIdentifier: source, title: "敬老の日",
                                                    start: day, end: calendar.date(byAdding: .day, value: 1, to: day)!,
                                                    isAllDay: true, calendarMetadata: metadata))
            }
        }
        store.retryCalendar()
    }

    static func seedDurationEdit(_ store: PocketStore) {
        let now = Date()
        // Keep the current plan on the displayed day even just after midnight.
        let startedAt = max(now.addingTimeInterval(-600), Calendar.current.startOfDay(for: now))
        let task = Task(title: "所要時間保持の確認", category: "制作", estimatedDuration: 600)
        let started = Task(title: "開始済み所要時間保持", estimatedDuration: 600)
        store.perform {
            store.repository.insert(task)
            try store.repository.insert(TaskOccurrence(taskID: task.id,
                scheduledStart: now.addingTimeInterval(7200), duration: 1800))
            store.repository.insert(started)
            // Rounding this started slot during title editing would attempt an invalid reschedule.
            try store.repository.insert(TaskOccurrence(taskID: started.id,
                scheduledStart: startedAt, duration: 1830))
        }
        store.retryCalendar()
    }

    static func seed(_ store: PocketStore) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let task = Task(title: "英語学習と長い日本語タイトルの表示確認")
        let reading = Task(title: "本を読む")
        store.perform {
            store.repository.insert(task)
            store.repository.insert(reading)
            // Three failures in one condition, three successful executions in another.
            for week in 1...3 {
                let date = calendar.date(byAdding: .day, value: -7 * week, to: today)!.addingTimeInterval(10 * 3600)
                let missed = TaskOccurrence(taskID: task.id, scheduledStart: date)
                try missed.markMissed()
                try store.repository.insert(missed)
                try store.repository.insert(TaskOccurrence(taskID: task.id, actualExecutedAt: date.addingTimeInterval(8 * 3600)))
            }
            let next = TaskOccurrence(taskID: task.id, scheduledStart: today.addingTimeInterval(10 * 3600))
            try store.repository.insert(next)
            let future = TaskOccurrence(taskID: task.id, scheduledStart: calendar.date(byAdding: .day, value: 7, to: today)!.addingTimeInterval(10 * 3600))
            try store.repository.insert(future)
            // A resolved previous day makes the contextual Review available at every wall-clock time.
            let previous = TaskOccurrence(taskID: reading.id, scheduledStart: today.addingTimeInterval(-86400 + 3600))
            try previous.markMissed()
            try store.repository.insert(previous)
        }
        if let fixture = store.calendarService as? FixtureCalendarService {
            fixture.stored.append(CalendarEvent(identifier: "ordinary-fixture", calendarIdentifier: "fixture", title: "友達と昼食", start: today.addingTimeInterval(12 * 3600), end: today.addingTimeInterval(13 * 3600)))
        }
        store.retryCalendar()
    }
}
#endif
