import Foundation

nonisolated struct ScheduleSuggestion: Identifiable, Equatable {
    var id: String { occurrenceID.uuidString + String(start.timeIntervalSince1970) }
    let occurrenceID: UUID
    let start: Date
    let end: Date
    let currentEvidence: SuccessRate
    let proposedEvidence: SuccessRate
    var reason: String {
        "現在の曜日・時間帯は\(currentEvidence.total)件中\(currentEvidence.misses)件が予定枠では未実行。候補の曜日・時間帯には\(proposedEvidence.successes)件の成功観測があります。"
    }
}

nonisolated enum SuggestionEngine {
    /// Small, explicit rule: >=3 failed-slot observations at the current condition,
    /// >=3 successes elsewhere, >=25 percentage point improvement, and a free slot.
    static func suggest(for plan: OccurrenceRecord, history: [OccurrenceRecord], busy: [DateInterval],
                        now: Date, calendar: Calendar = .current) -> ScheduleSuggestion? {
        guard plan.result == .pending, let start = plan.start, let end = plan.end, end > start else { return nil }
        let records = history.filter { $0.taskID == plan.taskID }
        let currentCondition = SlotCondition(start, calendar: calendar)
        let currentRecords = records.filter { $0.start.map { SlotCondition($0, calendar: calendar) == currentCondition } ?? false }
        let current = InsightsEngine.plannedRate(currentRecords)
        guard current.total >= 3, let currentRate = current.rate, currentRate <= 0.4 else { return nil }
        let observations = InsightsEngine.observations(records) { SlotCondition($0, calendar: calendar) }
        let duration = end.timeIntervalSince(start)
        // Existing successful start times provide candidate clock times, rather than inventing a schedule.
        let successfulDates = records.compactMap { record -> Date? in
            if record.result == .pending || record.result == .cancelled { return nil }
            return record.actual ?? (record.result == .success ? record.start : nil)
        }.sorted()
        let today = calendar.startOfDay(for: now)
        var candidates: [ScheduleSuggestion] = []
        for offset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for observed in successfulDates {
                let condition = SlotCondition(observed, calendar: calendar)
                guard condition != currentCondition, calendar.component(.weekday, from: day) == condition.weekday,
                      let evidence = observations[condition], evidence.successes >= 3,
                      let rate = evidence.rate, rate >= 2.0 / 3.0, rate - currentRate >= 0.25 else { continue }
                let parts = calendar.dateComponents([.hour, .minute], from: observed)
                guard let candidate = calendar.date(bySettingHour: parts.hour!, minute: parts.minute!, second: 0, of: day),
                      calendar.isDate(candidate, inSameDayAs: day), candidate > now else { continue }
                let candidateEnd = candidate.addingTimeInterval(duration)
                guard isFree(start: candidate, end: candidateEnd, busy: busy) else { continue }
                candidates.append(ScheduleSuggestion(occurrenceID: plan.id, start: candidate, end: candidateEnd,
                                                     currentEvidence: current, proposedEvidence: evidence))
            }
        }
        return candidates.sorted {
            if $0.proposedEvidence.rate != $1.proposedEvidence.rate { return $0.proposedEvidence.rate! > $1.proposedEvidence.rate! }
            return $0.start < $1.start
        }.first
    }

    static func isFree(start: Date, end: Date, busy: [DateInterval]) -> Bool {
        !busy.contains { $0.start < end && $0.end > start }
    }
}
