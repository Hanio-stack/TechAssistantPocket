import Foundation

nonisolated enum ReviewPolicy {
    static func dateKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    static func isAvailable(on day: Date, records: [OccurrenceRecord], now: Date, calendar: Calendar = .current) -> Bool {
        guard calendar.startOfDay(for: day) <= calendar.startOfDay(for: now) else { return false }
        let plans = records.filter { $0.start.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
        guard !plans.isEmpty else { return false }
        if plans.allSatisfy({ $0.result == .success || $0.result == .missed || $0.result == .cancelled }) { return true }
        guard let lastEnd = plans.compactMap(\.end).max() else { return false }
        return now > lastEnd
    }

    static func latestDay(records: [OccurrenceRecord], reviewedKeys: Set<String>, now: Date, calendar: Calendar = .current) -> Date? {
        let days = Set(records.compactMap(\.start).map { calendar.startOfDay(for: $0) }).sorted(by: >)
        return days.first {
            !reviewedKeys.contains(dateKey($0, calendar: calendar)) && isAvailable(on: $0, records: records, now: now, calendar: calendar)
        }
    }
}
