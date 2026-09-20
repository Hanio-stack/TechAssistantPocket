import Foundation
import UserNotifications

nonisolated struct TaskReminder: Equatable {
    let occurrenceID: UUID
    let title: String
    let fireDate: Date
    var identifier: String { "pocket." + occurrenceID.uuidString }
}

@MainActor protocol NotificationScheduling {
    func requestAccess() async throws -> Bool
    func isAuthorized() async -> Bool
    func schedule(_ reminder: TaskReminder) async throws
    func remove(occurrenceID: UUID)
}

@MainActor final class NotificationService: NotificationScheduling {
    private let center = UNUserNotificationCenter.current()
    func requestAccess() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    func isAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }
    func schedule(_ reminder: TaskReminder) async throws {
        try await center.add(Self.request(for: reminder))
    }
    static func request(for reminder: TaskReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = "予定の時間です。実行したら開始時刻を記録しましょう。"
        content.sound = .default
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
    }
    func remove(occurrenceID: UUID) {
        let id = "pocket." + occurrenceID.uuidString
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }
}

nonisolated enum ReminderPolicy {
    static func reminder(id: UUID, title: String, start: Date?, result: PlanResult?, minutes: Int?, now: Date) -> TaskReminder? {
        guard result == .pending, let start, let minutes, minutes >= 0 else { return nil }
        let fireDate = start.addingTimeInterval(-Double(minutes * 60))
        guard fireDate > now else { return nil }
        return TaskReminder(occurrenceID: id, title: title, fireDate: fireDate)
    }
}
