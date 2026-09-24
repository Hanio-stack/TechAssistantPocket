import Foundation

nonisolated struct CalendarEvent: Identifiable, Equatable {
    let identifier: String
    let calendarIdentifier: String
    let title: String
    let start: Date
    let end: Date
    var isAllDay = false
    var location: String? = nil
    var calendarMetadata: CalendarMetadata? = nil
    // Recurring events can share an EventKit identifier.
    var id: String { calendarIdentifier + ":" + identifier + ":" + String(start.timeIntervalSince1970) }
}

nonisolated struct OccurrenceRecord: Identifiable, Equatable {
    let id: UUID
    let taskID: UUID
    var start: Date?
    var end: Date?
    var result: PlanResult?
    var actual: Date?
    var mirrorID: String? = nil
}

extension TaskOccurrence {
    var record: OccurrenceRecord {
        OccurrenceRecord(id: id, taskID: taskID, start: scheduledStart, end: scheduledEnd,
                         result: planResult, actual: actualExecutedAt, mirrorID: calendarEventIdentifier)
    }
}

nonisolated enum Timeline {
    enum Entry: Identifiable, Equatable {
        case task(OccurrenceRecord)
        case event(CalendarEvent)
        var id: String {
            switch self {
            case .task(let record): "task:" + record.id.uuidString
            case .event(let event): "event:" + event.id
            }
        }
        var start: Date {
            switch self {
            case .task(let record): record.start ?? record.actual ?? .distantPast
            case .event(let event): event.start
            }
        }
        var isAllDay: Bool {
            if case .event(let event) = self { return event.isAllDay }
            return false
        }
        func isCurrent(at now: Date) -> Bool {
            switch self {
            case .task(let record):
                return record.result == .pending && start <= now && (record.end.map { now <= $0 } ?? false)
            case .event(let event): return event.start <= now && now < event.end
            }
        }
    }

    static func entries(on day: Date, records: [OccurrenceRecord], events: [CalendarEvent],
                        calendar: Calendar = .current) -> [Entry] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        // All known mirror IDs, not only today's records: overnight mirrors must stay hidden.
        let mirrors = Set(records.compactMap(\.mirrorID))
        let tasks = records.filter { record in
            guard let date = record.start else { return false }
            return date >= start && date < end
        }.map(Entry.task)
        let ordinary = CalendarReadPolicy.visibleEvents(events).filter {
            !mirrors.contains($0.identifier) && $0.start < end && $0.end > start
        }.map(Entry.event)
        return (tasks + ordinary).sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }

    struct Presentation {
        var upcoming: [Entry] = []
        var unresolved: [Entry] = []
        var history: [Entry] = []
        var focus: Entry?
        var currentTask: Entry?
    }

    static func presentation(on day: Date, now: Date, records: [OccurrenceRecord], events: [CalendarEvent],
                             calendar: Calendar = .current, archivedTaskIDs: Set<UUID> = []) -> Presentation {
        var result = Presentation()
        for entry in entries(on: day, records: records, events: events, calendar: calendar) {
            switch entry {
            case .task(let record):
                if record.result != .pending || archivedTaskIDs.contains(record.taskID) { result.history.append(entry) }
                else if let end = record.end, end < now { result.unresolved.append(entry) }
                else { result.upcoming.append(entry) }
            case .event(let event):
                if event.end <= now { result.history.append(entry) }
                else { result.upcoming.append(entry) }
            }
        }
        // All-day personal events remain in chronological order, but a timed action is
        // a more useful focus than an event spanning the entire day.
        let timed = result.upcoming.filter { !$0.isAllDay }
        result.currentTask = timed.first { entry in
            if case .task = entry { return entry.isCurrent(at: now) }
            return false
        }
        result.focus = result.currentTask ?? timed.first { $0.isCurrent(at: now) } ?? timed.first ?? result.upcoming.first
        return result
    }

    static func dayOffset(horizontal: Double, vertical: Double) -> Int {
        guard abs(horizontal) >= 80, abs(horizontal) > abs(vertical) * 1.8 else { return 0 }
        return horizontal < 0 ? 1 : -1
    }

    static func hasNewlyResolvedTask(before: [OccurrenceRecord], after: [OccurrenceRecord]) -> Bool {
        let pending = Set(before.filter { $0.result == .pending }.map(\.id))
        return after.contains { pending.contains($0.id) && [.success, .missed, .cancelled].contains($0.result) }
    }
}
