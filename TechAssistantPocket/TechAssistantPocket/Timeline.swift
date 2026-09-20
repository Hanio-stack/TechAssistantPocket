import Foundation

nonisolated struct CalendarEvent: Identifiable, Equatable {
    let identifier: String
    let calendarIdentifier: String
    let title: String
    let start: Date
    let end: Date
    var isAllDay = false
    var location: String? = nil
    // Recurring events can share an EventKit identifier.
    var id: String { identifier + ":" + String(start.timeIntervalSince1970) }
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
    enum Entry: Identifiable {
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
        let ordinary = events.filter {
            !mirrors.contains($0.identifier) && $0.start < end && $0.end > start
        }.map(Entry.event)
        return (tasks + ordinary).sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }
}
