import Foundation

/// Presentation only. Does not change the persisted result or success boundary.
nonisolated enum OccurrenceDisplayState: Equatable {
    case upcoming, active, pastPending, completed, missed, cancelled
    static func resolve(_ record: OccurrenceRecord, now: Date) -> Self {
        switch record.result {
        case .success: return .completed
        case .missed: return .missed
        case .cancelled: return .cancelled
        case .none: return .completed
        case .pending:
            guard let start = record.start, let end = record.end else { return .pastPending }
            if now < start { return .upcoming }
            return now <= end ? .active : .pastPending
        }
    }
}

/// Raw drag facts in points; output is direction, not a date or a data mutation.
nonisolated enum SwipeDecisionPolicy {
    static func direction(x: Double, y: Double, predictedX: Double, width: Double) -> Int {
        guard width > 0, x.isFinite, y.isFinite, predictedX.isFinite,
              abs(x) >= 16, abs(x) > abs(y) * 1.8 else { return 0 }
        let distance = abs(x) >= max(60, width * 0.25)
        let flick = x * predictedX > 0 && abs(x) >= 28 && abs(predictedX) >= width * 0.55
        guard distance || flick else { return 0 }
        return x < 0 ? 1 : -1
    }
}
