import Foundation

/// Local wall-clock range. The weekday belongs to the day on which work starts.
nonisolated struct WorkClockRange: Codable, Equatable {
    let startMinutes: Int
    let endMinutes: Int
    var isValid: Bool { LifeDayPolicy(wakeMinutes: startMinutes, bedMinutes: endMinutes) != nil }
    func interval(on day: Date, calendar: Calendar) -> DateInterval? {
        LifeDayPolicy(wakeMinutes: startMinutes, bedMinutes: endMinutes)?.interval(on: day, calendar: calendar)
    }
}

nonisolated struct WorkWindowPolicy: Codable, Equatable {
    let weekday: WorkClockRange
    let weekend: WorkClockRange
    var isValid: Bool { weekday.isValid && weekend.isValid }

    func window(on day: Date, calendar: Calendar = .current) -> DateInterval? {
        let dayOfWeek = calendar.component(.weekday, from: day)
        return (dayOfWeek == 1 || dayOfWeek == 7 ? weekend : weekday).interval(on: day, calendar: calendar)
    }

    func currentWindow(at now: Date, calendar: Calendar = .current) -> DateInterval? {
        guard isValid else { return nil }
        let today = calendar.startOfDay(for: now)
        let previous = calendar.date(byAdding: .day, value: -1, to: today)!
        // If different weekday/weekend ranges overlap, retain the older session until it ends.
        return [previous, today].compactMap { window(on: $0, calendar: calendar) }
            .first { $0.start <= now && now < $0.end }
    }

    func remaining(at now: Date, calendar: Calendar = .current) -> DateInterval? {
        currentWindow(at: now, calendar: calendar).map { DateInterval(start: now, end: $0.end) }
    }
}

/// Interval subtraction only: no calendar-provider or task-model dependencies.
nonisolated enum SchedulePackingEngine {
    static func freeIntervals(in window: DateInterval, busy: [DateInterval]) -> [DateInterval] {
        guard window.duration > 0 else { return [] }
        let clipped = busy.compactMap { range -> DateInterval? in
            let start = max(window.start, range.start), end = min(window.end, range.end)
            return end > start ? DateInterval(start: start, end: end) : nil
        }.sorted { $0.start < $1.start }
        var cursor = window.start
        var free: [DateInterval] = []
        for range in clipped {
            if range.start > cursor { free.append(DateInterval(start: cursor, end: range.start)) }
            cursor = max(cursor, range.end)
        }
        if cursor < window.end { free.append(DateInterval(start: cursor, end: window.end)) }
        return free
    }

    static func availableNow(at now: Date, window: DateInterval, busy: [DateInterval]) -> DateInterval? {
        freeIntervals(in: window, busy: busy).first { $0.start <= now && now < $0.end }
            .map { DateInterval(start: now, end: $0.end) }
    }
}

nonisolated struct SchedulingCandidate: Equatable {
    let id: UUID
    let priority: Int
    let estimatedMinutes: Int
    let createdAt: Date
    var isValid: Bool { (1...3).contains(priority) && (5...180).contains(estimatedMinutes) && estimatedMinutes % 5 == 0 }
}

nonisolated enum TaskActionKind: String, Codable { case completed, skipped }

nonisolated struct SelectionAction: Equatable {
    let taskID: UUID
    let kind: TaskActionKind
    let sessionStart: Date
}

nonisolated enum TaskSelectionEngine {
    /// Keep the most recently skipped task out until another action or work session.
    /// Repeated timer/calendar refreshes do not consume the exclusion.
    static func excludedTask(lastAction: SelectionAction?, sessionStart: Date) -> UUID? {
        guard let lastAction, lastAction.kind == .skipped, lastAction.sessionStart == sessionStart else { return nil }
        return lastAction.taskID
    }

    static func select(from candidates: [SchedulingCandidate], available: DateInterval,
                       excluding taskID: UUID? = nil) -> SchedulingCandidate? {
        candidates.filter {
            $0.isValid && $0.id != taskID && Double($0.estimatedMinutes * 60) <= available.duration
        }.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }.first
    }
}
