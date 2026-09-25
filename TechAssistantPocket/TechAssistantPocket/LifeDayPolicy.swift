import Foundation

/// Local wall-clock minutes, independent of persistence and UI. Bedtime is exclusive.
nonisolated struct LifeDayPolicy: Equatable {
    let wakeMinutes: Int
    let bedMinutes: Int

    init?(wakeMinutes: Int, bedMinutes: Int) {
        guard (0..<1440).contains(wakeMinutes), (0..<1440).contains(bedMinutes),
              wakeMinutes != bedMinutes else { return nil }
        self.wakeMinutes = wakeMinutes
        self.bedMinutes = bedMinutes
    }

    static let initial = LifeDayPolicy(wakeMinutes: 480, bedMinutes: 90)!

    func shiftedDay(_ day: Date, by offset: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: day))!
    }

    func interval(on day: Date, calendar: Calendar = .current) -> DateInterval {
        let day = calendar.startOfDay(for: day)
        let endDay = bedMinutes < wakeMinutes ? shiftedDay(day, by: 1, calendar: calendar) : day
        // Calendar resolves nonexistent DST times forward and repeated times to the first occurrence.
        let start = calendar.date(bySettingHour: wakeMinutes / 60, minute: wakeMinutes % 60, second: 0, of: day)!
        let end = calendar.date(bySettingHour: bedMinutes / 60, minute: bedMinutes % 60, second: 0, of: endDay)!
        return DateInterval(start: start, end: max(start, end))
    }

    /// During the sleep gap, show the upcoming life day. Historical timestamps use
    /// this same label, without deleting observations outside the waking interval.
    func day(containing date: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: date)
        let previous = shiftedDay(today, by: -1, calendar: calendar)
        if date < interval(on: previous, calendar: calendar).end { return previous }
        if date >= interval(on: today, calendar: calendar).end { return shiftedDay(today, by: 1, calendar: calendar) }
        return today
    }

    func contains(_ date: Date, on day: Date, calendar: Calendar = .current) -> Bool {
        let range = interval(on: day, calendar: calendar)
        return date >= range.start && date < range.end
    }
}
