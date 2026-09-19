import Foundation
import SwiftData

@Model
final class Task {
    @Attribute(.unique) var id: UUID
    var title: String
    var category: String?
    /// Estimated duration in seconds; optional for an unscheduled task.
    var estimatedDuration: TimeInterval?
    var createdAt: Date
    var archivedAt: Date?

    init(id: UUID = UUID(), title: String, category: String? = nil,
         estimatedDuration: TimeInterval? = nil, createdAt: Date = Date(),
         archivedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.category = category
        self.estimatedDuration = estimatedDuration
        self.createdAt = createdAt
        self.archivedAt = archivedAt
    }
}
