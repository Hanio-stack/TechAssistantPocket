import Foundation

nonisolated enum CategoryAnalyticsEngine {
    struct TaskInput {
        let id: UUID
        let category: String?
    }
    struct Summary: Identifiable {
        var id: String { name }
        let name: String
        let taskIDs: Set<UUID>
        let records: [OccurrenceRecord]
        var plannedRate: SuccessRate { InsightsEngine.plannedRate(records) }
        var executionCount: Int { records.filter { $0.actual != nil }.count }
    }

    static func name(_ category: String?) -> String {
        let trimmed = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "未分類" : trimmed
    }

    static func summaries(tasks: [TaskInput], records: [OccurrenceRecord]) -> [Summary] {
        let groups = Dictionary(grouping: tasks) { name($0.category) }
        return groups.keys.sorted().map { name in
            let ids = Set(groups[name]!.map(\.id))
            return Summary(name: name, taskIDs: ids, records: records.filter { ids.contains($0.taskID) })
        }
    }

    static func weekdays(_ records: [OccurrenceRecord], lifeDay: LifeDayPolicy?, calendar: Calendar = .current) -> [Int: SuccessRate] {
        InsightsEngine.observations(records) {
            calendar.component(.weekday, from: lifeDay?.day(containing: $0, calendar: calendar) ?? $0)
        }
    }

    static func weeklyRate(_ records: [OccurrenceRecord], now: Date, lifeDay: LifeDayPolicy?, calendar: Calendar = .current) -> SuccessRate {
        let week = InsightsEngine.week(containing: lifeDay?.day(containing: now, calendar: calendar) ?? now, calendar: calendar)
        return InsightsEngine.plannedRate(records.filter { record in
            guard let start = record.start else { return false }
            let day = lifeDay?.day(containing: start, calendar: calendar) ?? start
            return day >= week.start && day < week.end
        })
    }
}
