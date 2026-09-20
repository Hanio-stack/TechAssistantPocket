import Foundation

/// A scheduled plan's result, independent of whether execution happened later.
nonisolated enum PlanResult: String, Codable, CaseIterable {
    case pending
    case success
    case missed
    case cancelled
}
