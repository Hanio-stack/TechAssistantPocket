import Foundation
import EventKit

nonisolated struct CalendarChoice: Identifiable, Equatable {
    let id: String
    let title: String
    let source: String
}

nonisolated struct MirrorReference: Codable, Hashable {
    let occurrenceID: UUID
    let eventIdentifier: String?
    let calendarIdentifier: String?
}

nonisolated enum CalendarAccess { case notDetermined, full, denied }

nonisolated enum CalendarFailure: LocalizedError {
    case accessRequired, selectCalendar, calendarUnavailable, invalidDates
    var errorDescription: String? {
        switch self {
        case .accessRequired: "カレンダーへのアクセスが必要です。設定から許可してください。Task は端末に保存されています。"
        case .selectCalendar: "保存先のカレンダーを選択してください。"
        case .calendarUnavailable: "以前使用していたカレンダーが見つからないか、書き込めません。設定で保存先を選び直してください。"
        case .invalidDates: "終了は開始より後にしてください。"
        }
    }
}

@MainActor protocol CalendarService {
    var access: CalendarAccess { get }
    func requestAccess() async throws -> Bool
    func calendars() -> [CalendarChoice]
    func events(from start: Date, to end: Date) throws -> [CalendarEvent]
    func mirrorExists(_ identifier: String) throws -> Bool
    func saveMirror(title: String, occurrenceID: UUID, start: Date, end: Date,
                    existingID: String?, calendarID: String?) throws -> MirrorReference
    func removeMirror(_ reference: MirrorReference) throws
    func createEvent(title: String, start: Date, end: Date, calendarID: String?, reminderMinutes: Int?) throws
}

@MainActor final class EventKitAdapter: CalendarService {
    private let eventStore = EKEventStore()
    var access: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .full
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
    func requestAccess() async throws -> Bool { try await eventStore.requestFullAccessToEvents() }
    func calendars() -> [CalendarChoice] {
        guard access == .full else { return [] }
        return eventStore.calendars(for: .event).filter(\.allowsContentModifications).map {
            CalendarChoice(id: $0.calendarIdentifier, title: $0.title, source: $0.source.title)
        }.sorted { $0.title < $1.title }
    }
    private func requireAccess() throws {
        guard access == .full else { throw CalendarFailure.accessRequired }
    }
    private func writableCalendar(_ identifier: String?) throws -> EKCalendar {
        try requireAccess()
        guard let identifier, !identifier.isEmpty else { throw CalendarFailure.selectCalendar }
        guard let calendar = eventStore.calendar(withIdentifier: identifier), calendar.allowsContentModifications else {
            throw CalendarFailure.calendarUnavailable
        }
        return calendar
    }
    func events(from start: Date, to end: Date) throws -> [CalendarEvent] {
        try requireAccess()
        let calendars = eventStore.calendars(for: .event).filter { !CalendarReadPolicy.isHolidayCalendar(Self.metadata(for: $0)) }
        // Passing nil means all calendars, so an empty eligible set must return immediately.
        guard !calendars.isEmpty else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let events = eventStore.events(matching: predicate).compactMap { event -> CalendarEvent? in
            guard let id = event.eventIdentifier else { return nil }
            return CalendarEvent(identifier: id, calendarIdentifier: event.calendar.calendarIdentifier,
                                 title: event.title ?? "予定", start: event.startDate, end: event.endDate,
                                 isAllDay: event.isAllDay, location: event.location,
                                 calendarMetadata: Self.metadata(for: event.calendar))
        }
        // Preserve raw identities until the coordinator can exclude all known Pocket mirrors.
        return events
    }
    static func metadata(for calendar: EKCalendar) -> CalendarMetadata {
        let source = calendar.source
        let kind: CalendarMetadata.SourceKind
        switch source?.sourceType {
        case .local: kind = .local
        case .calDAV: kind = .calDAV
        case .exchange: kind = .exchange
        case .subscribed: kind = .subscribed
        default: kind = .other
        }
        return CalendarMetadata(identifier: calendar.calendarIdentifier, title: calendar.title,
                                sourceIdentifier: source?.sourceIdentifier ?? "", sourceTitle: source?.title ?? "",
                                sourceKind: kind, isSubscribed: calendar.isSubscribed || calendar.type == .subscription,
                                allowsContentModifications: calendar.allowsContentModifications)
    }
    func mirrorExists(_ identifier: String) throws -> Bool {
        try requireAccess()
        return eventStore.event(withIdentifier: identifier) != nil
    }
    func saveMirror(title: String, occurrenceID: UUID, start: Date, end: Date,
                    existingID: String?, calendarID: String?) throws -> MirrorReference {
        let calendar = try writableCalendar(calendarID)
        guard end > start else { throw CalendarFailure.invalidDates }
        let event = existingID.flatMap { eventStore.event(withIdentifier: $0) } ?? EKEvent(eventStore: eventStore)
        event.calendar = calendar
        Self.configureMirror(event, title: title, start: start, end: end)
        try eventStore.save(event, span: .thisEvent)
        return MirrorReference(occurrenceID: occurrenceID, eventIdentifier: event.eventIdentifier,
                               calendarIdentifier: event.calendar.calendarIdentifier)
    }
    static func configureMirror(_ event: EKEvent, title: String, start: Date, end: Date) {
        event.title = title
        // Turn off all-day normalization before assigning the authoritative dates.
        event.isAllDay = false
        event.startDate = start
        event.endDate = end
        // An existing mirror may have acquired alarms outside Pocket; always clear them.
        event.alarms = nil
    }

    func removeMirror(_ reference: MirrorReference) throws {
        guard let id = reference.eventIdentifier else { return }
        try requireAccess()
        guard let event = eventStore.event(withIdentifier: id) else { return }
        guard event.calendar.allowsContentModifications else { throw CalendarFailure.calendarUnavailable }
        try eventStore.remove(event, span: .thisEvent)
    }
    func createEvent(title: String, start: Date, end: Date, calendarID: String?, reminderMinutes: Int?) throws {
        let calendar = try writableCalendar(calendarID)
        guard end > start else { throw CalendarFailure.invalidDates }
        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = title
        event.startDate = start
        event.endDate = end
        if let minutes = reminderMinutes { event.addAlarm(EKAlarm(relativeOffset: -Double(minutes * 60))) }
        try eventStore.save(event, span: .thisEvent)
    }
}
