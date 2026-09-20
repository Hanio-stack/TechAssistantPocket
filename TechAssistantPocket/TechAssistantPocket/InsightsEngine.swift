import Foundation

nonisolated enum TimeBand: Int, CaseIterable, Identifiable, Codable {
    case early, morning, afternoon, evening
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .early: "深夜・早朝（0–6時）"
        case .morning: "午前（6–12時）"
        case .afternoon: "午後（12–18時）"
        case .evening: "夜（18–24時）"
        }
    }
    static func at(_ date: Date, calendar: Calendar) -> TimeBand {
        TimeBand(rawValue: calendar.component(.hour, from: date) / 6)!
    }
}

nonisolated struct SuccessRate: Equatable {
    var successes = 0
    var misses = 0
    var total: Int { successes + misses }
    var rate: Double? { total == 0 ? nil : Double(successes) / Double(total) }
    var text: String { rate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—" }
}

nonisolated struct SlotCondition: Hashable {
    let weekday: Int
    let band: TimeBand
    init(_ date: Date, calendar: Calendar) {
        weekday = calendar.component(.weekday, from: date)
        band = TimeBand.at(date, calendar: calendar)
    }
}

nonisolated enum InsightsEngine {
    /// Scheduled slot metrics never include execution-only records, pending or cancelled plans.
    static func plannedRate(_ records: [OccurrenceRecord], interval: DateInterval? = nil) -> SuccessRate {
        var counts = SuccessRate()
        for record in records {
            guard let start = record.start, record.end != nil,
                  interval.map({ start >= $0.start && start < $0.end }) ?? true else { continue }
            if record.result == .success { counts.successes += 1 }
            if record.result == .missed { counts.misses += 1 }
        }
        return counts
    }

    static func week(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date)!
    }

    /// A separate observation series: failed slots plus successful execution observations.
    /// De-duplication is per dimension (weekday, band, or their pair), not across independent dimensions.
    static func observations<Key: Hashable>(_ records: [OccurrenceRecord], key: (Date) -> Key) -> [Key: SuccessRate] {
        var counts: [Key: SuccessRate] = [:]
        for record in records {
            if let planned = record.start, record.end != nil {
                if record.result == .success { counts[key(planned), default: SuccessRate()].successes += 1 }
                if record.result == .missed { counts[key(planned), default: SuccessRate()].misses += 1 }
            }
            if let actual = record.actual, record.result != .cancelled, record.result != .pending {
                let sameSuccessfulSlot = record.result == .success && record.start.map { key($0) == key(actual) } == true
                if !sameSuccessfulSlot { counts[key(actual), default: SuccessRate()].successes += 1 }
            }
        }
        return counts
    }

    static func weekdays(_ records: [OccurrenceRecord], calendar: Calendar = .current) -> [Int: SuccessRate] {
        observations(records) { calendar.component(.weekday, from: $0) }
    }
    static func timeBands(_ records: [OccurrenceRecord], calendar: Calendar = .current) -> [TimeBand: SuccessRate] {
        observations(records) { TimeBand.at($0, calendar: calendar) }
    }
}
