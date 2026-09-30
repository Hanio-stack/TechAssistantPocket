import Foundation

nonisolated struct TaskActionFact: Equatable {
    let taskID: UUID
    let genre: String
    let proposedAt: Date
    let occurredAt: Date
    let kind: TaskActionKind
}

nonisolated enum ActionAnalyticsEngine {
    struct Counts: Equatable {
        var completed = 0
        var skipped = 0
        mutating func add(_ kind: TaskActionKind) { if kind == .completed { completed += 1 } else { skipped += 1 } }
    }
    struct Summary: Identifiable, Equatable {
        var id: String { genre }
        let genre: String
        let completed: Int
        let skipped: Int
        let weekdays: [Int: Counts]
        let hours: [Int: Counts]
    }
    /// Bins describe when the action was observed, not when or how long work happened.
    static func summaries(_ facts: [TaskActionFact], calendar: Calendar = .current) -> [Summary] {
        Dictionary(grouping: facts) {
            let genre = $0.genre.trimmingCharacters(in: .whitespacesAndNewlines)
            return genre.isEmpty ? "未分類" : genre
        }.map { genre, facts in
            var total = Counts(), weekdays: [Int: Counts] = [:], hours: [Int: Counts] = [:]
            for fact in facts {
                total.add(fact.kind)
                weekdays[calendar.component(.weekday, from: fact.occurredAt), default: Counts()].add(fact.kind)
                hours[calendar.component(.hour, from: fact.occurredAt), default: Counts()].add(fact.kind)
            }
            return Summary(genre: genre, completed: total.completed, skipped: total.skipped, weekdays: weekdays, hours: hours)
        }.sorted { $0.genre < $1.genre }
    }
}
