import Foundation
import Testing
@testable import TechAssistantPocket

struct CalendarReadPolicyTests {
    private func metadata(id: String = "opaque-id", title: String, kind: CalendarMetadata.SourceKind = .calDAV,
                          subscribed: Bool = false, writable: Bool = false) -> CalendarMetadata {
        CalendarMetadata(identifier: id, title: title, sourceIdentifier: "source-id", sourceTitle: "Account",
                         sourceKind: kind, isSubscribed: subscribed, allowsContentModifications: writable)
    }
    private func event(id: String, calendar: CalendarMetadata, title: String = "敬老の日", allDay: Bool = true) -> CalendarEvent {
        CalendarEvent(identifier: id, calendarIdentifier: calendar.identifier, title: title,
                      start: Date(timeIntervalSince1970: 1_000), end: Date(timeIntervalSince1970: 2_000),
                      isAllDay: allDay, calendarMetadata: calendar)
    }

    @Test func appleAndGoogleHolidayCalendarsAreExcludedWithoutEventTitleRules() {
        let apple = metadata(id: "apple", title: "日本の祝日", kind: .subscribed, subscribed: true)
        let google = metadata(id: "google", title: "Holidays in Japan")
        let events = [event(id: "first", calendar: apple), event(id: "second", calendar: google),
                      event(id: "unknown-holiday-name", calendar: apple, title: "Unknown holiday", allDay: false)]
        #expect(CalendarReadPolicy.visibleEvents(events).isEmpty)
        #expect(CalendarReadPolicy.isHolidayCalendar(metadata(id: "en.japanese%23holiday@group.v.calendar.google.com", title: "Renamed")))
    }

    @Test func personalAllDayAndNonHolidaySubscriptionsRemainVisible() {
        let writable = metadata(title: "日本の祝日", writable: true)
        let subscribed = metadata(id: "school", title: "学校行事", kind: .subscribed, subscribed: true)
        let shared = metadata(id: "shared", title: "家族の予定")
        let events = [event(id: "personal", calendar: writable), event(id: "school-event", calendar: subscribed),
                      event(id: "family", calendar: shared)]
        #expect(CalendarReadPolicy.visibleEvents(events) == events)
        #expect(!CalendarReadPolicy.isHolidayCalendar(metadata(title: "Holiday planning")))
        #expect(!CalendarReadPolicy.isHolidayCalendar(metadata(title: "祝日", kind: .local, writable: true)))
    }

    @Test func exactDuplicatesAreRemovedWithoutMergingCalendarsOrRecurrences() {
        let calendar = metadata(title: "個人", writable: true)
        let first = event(id: "event", calendar: calendar)
        // CalendarEvent dates are immutable: represent a later recurrence with the same event ID.
        let later = CalendarEvent(identifier: first.identifier, calendarIdentifier: first.calendarIdentifier, title: first.title,
                              start: first.start.addingTimeInterval(86400), end: first.end.addingTimeInterval(86400))
        let differentCalendar = event(id: "event", calendar: metadata(id: "other-calendar", title: "個人", writable: true))
        #expect(CalendarReadPolicy.visibleEvents([first, first, later, differentCalendar]) == [first, later, differentCalendar])
    }
}
