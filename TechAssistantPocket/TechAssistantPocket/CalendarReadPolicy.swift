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

    static func visibleEvents(_ events: [CalendarEvent]) -> [CalendarEvent] {
        var seen: Set<String> = []
        return events.filter { event in
            if let calendar = event.calendarMetadata, isHolidayCalendar(calendar) { return false }
            // Do not merge by title/date or external UID: distinct calendars and recurring
            // occurrences may legitimately contain similarly named events.
            return seen.insert(event.id).inserted
        }
    }
}
