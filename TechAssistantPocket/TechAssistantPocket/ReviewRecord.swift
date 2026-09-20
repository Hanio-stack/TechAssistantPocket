import Foundation
import SwiftData

@Model final class ReviewRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var dateKey: String
    var reviewedAt: Date
    init(dateKey: String, reviewedAt: Date) {
        id = UUID()
        self.dateKey = dateKey
        self.reviewedAt = reviewedAt
    }
}
