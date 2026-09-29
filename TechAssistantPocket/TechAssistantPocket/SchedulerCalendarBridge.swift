import Foundation

nonisolated struct PocketCalendarAllocation {
    let proposalID: UUID
    let title: String
    let start: Date
    let end: Date
    let lookupEnd: Date
    let existingID: String?
    let calendarID: String?
}

nonisolated enum PocketCalendarOwnership {
    static func url(for id: UUID) -> URL { URL(string: "pocket://proposal/\(id.uuidString)")! }
    static func proposalID(from url: URL?) -> UUID? {
        guard let url, url.scheme == "pocket", url.host == "proposal", url.query == nil, url.fragment == nil,
              url.pathComponents.count == 2 else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}

@MainActor protocol SchedulerCalendarBridge: CalendarService {
    func hasAllocation(eventID: String?, proposalID: UUID) throws -> Bool
    func syncAllocation(_ allocation: PocketCalendarAllocation, destination: String?) throws -> MirrorReference?
}
