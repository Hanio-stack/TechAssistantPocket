import Foundation

/// Public EventKit calendar/account metadata, without retaining EventKit objects in the UI.
nonisolated struct CalendarMetadata: Equatable {
    enum SourceKind { case local, calDAV, exchange, subscribed, other }
    let identifier: String
    let title: String
    let sourceIdentifier: String
    let sourceTitle: String
    let sourceKind: SourceKind
    let isSubscribed: Bool
    let allowsContentModifications: Bool
}

nonisolated enum CalendarReadPolicy {
    /// EventKit has no public holiday flag or subscription-feed URL. Use calendar-level
    /// evidence conservatively; event titles and all-day status are deliberately irrelevant.
    static func isHolidayCalendar(_ calendar: CalendarMetadata) -> Bool {
        guard !calendar.allowsContentModifications else { return false }
        let identifier = (calendar.identifier.removingPercentEncoding ?? calendar.identifier).lowercased()
        if identifier.hasSuffix("#holiday@group.v.calendar.google.com") { return true }

        guard calendar.isSubscribed || calendar.sourceKind == .subscribed ||
                calendar.sourceKind == .calDAV || calendar.sourceKind == .exchange else { return false }
        let title = calendar.title.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if title == "祝日" || title.hasSuffix("の祝日") { return true }
        if ["holidays", "public holidays", "national holidays", "bank holidays",
            "japanese holidays", "us holidays", "u.s. holidays", "uk holidays"].contains(title) { return true }
        return title.hasPrefix("holidays in ")
    }

    private struct ContentKey: Hashable {
        let title: String
        let start: Date
        let end: Date
        let allDay: Bool
        let location: String
    }

    /// Trim/collapse whitespace and canonicalize Unicode, preserving case and punctuation.
    static func normalized(_ value: String?) -> String {
        (value ?? "").precomposedStringWithCanonicalMapping.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func visibleEvents(_ events: [CalendarEvent], excludingMirrorIDs mirrors: Set<String> = []) -> [CalendarEvent] {
        var seen: Set<ContentKey> = []
        return events.filter { event in
            guard !mirrors.contains(event.identifier) else { return false }
            if let calendar = event.calendarMetadata, isHolidayCalendar(calendar) { return false }
            return seen.insert(ContentKey(title: normalized(event.title), start: event.start, end: event.end,
                                          allDay: event.isAllDay, location: normalized(event.location))).inserted
        }
    }
}
