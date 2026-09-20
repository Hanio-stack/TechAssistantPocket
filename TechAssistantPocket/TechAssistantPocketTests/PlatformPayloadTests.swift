import Foundation
import EventKit
import UserNotifications
import Testing
@testable import TechAssistantPocket

@MainActor struct PlatformPayloadTests {
    @Test func taskMirrorClearsCalendarAlarmsIncludingExistingExternalAlarm() {
        let event = EKEvent(eventStore: EKEventStore())
        event.addAlarm(EKAlarm(relativeOffset: -300))
        event.isAllDay = true
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        EventKitAdapter.configureMirror(event, title: "英語", start: start, end: start.addingTimeInterval(1800))
        #expect(event.title == "英語")
        #expect(event.startDate == start)
        #expect(event.endDate == start.addingTimeInterval(1800))
        #expect(!event.isAllDay)
        #expect(event.alarms?.isEmpty ?? true)
    }
    @Test func localNotificationHasStableIDAndAbsoluteCalendarComponents() throws {
        let reminder = TaskReminder(occurrenceID: UUID(), title: "読書", fireDate: Date(timeIntervalSince1970: 1_800_000_000))
        let request = NotificationService.request(for: reminder)
        #expect(request.identifier == reminder.identifier)
        #expect(request.content.title == "読書")
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(!trigger.repeats)
        #expect(trigger.dateComponents.timeZone != nil)
        #expect(trigger.dateComponents.calendar?.date(from: trigger.dateComponents) == reminder.fireDate)
    }
}
