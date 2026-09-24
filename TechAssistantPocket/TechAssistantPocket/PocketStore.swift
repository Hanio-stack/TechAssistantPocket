import Foundation
import Observation
import SwiftData

/// UI state and the small coordination point for local persistence and platform services.
@MainActor @Observable
final class PocketStore {
    var currentTime: Date {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--ui-today-focus") { return DebugFixtures.todayReferenceTime }
        #endif
        return Date()
    }

    let repository: TaskRepository
    let calendarService: any CalendarService
    let defaults: UserDefaults
    let notifications: any NotificationScheduling
    var defaultReminder: Int? {
        didSet { defaults.set(defaultReminder, forKey: "defaultNotificationMinutes") }
    }
    var notificationMessage: String?
    var notificationsAuthorized = false
    var calendarWriteMessage: String?
    var calendarChoices: [CalendarChoice] = []
    var calendarAccess: CalendarAccess = .notDetermined
    var selectedCalendarID: String? {
        didSet { defaults.set(selectedCalendarID, forKey: "defaultCalendarIdentifier") }
    }
    var calendarMessage: String?
    var displayDay = Date()
    var pendingMirrorDeletes: [MirrorReference] = []
    var missingMirrorCount: Int { occurrences.filter { $0.scheduledStart != nil && $0.calendarEventIdentifier == nil }.count }
    var integrationMessage: String? {
        if !pendingMirrorDeletes.isEmpty { return "古いカレンダー予定が\(pendingMirrorDeletes.count)件、削除待ちです。設定から再試行してください。" }
        if let calendarWriteMessage { return calendarWriteMessage }
        if let notificationMessage { return notificationMessage }
        if let calendarMessage { return calendarMessage }
        if missingMirrorCount > 0 { return "\(missingMirrorCount)件の Task がカレンダーに未反映です。設定から再試行できます。" }
        return nil
    }

    var categoryNames: [String] = []

    /// Retain used names even after the last Task using one is edited or archived.
    private func rememberCategories() {
        let names = (defaults.stringArray(forKey: "taskCategoryHistory") ?? []) + tasks.compactMap(\.category)
        categoryNames = Array(Set(names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })).sorted()
        defaults.set(categoryNames, forKey: "taskCategoryHistory")
    }

    var tasks: [Task] = []
    var occurrences: [TaskOccurrence] = []
    var reviewedKeys: Set<String> = []
    var events: [CalendarEvent] = []
    var errorMessage: String?

    init(container: ModelContainer, calendarService: (any CalendarService)? = nil, defaults: UserDefaults = .standard, notifications: (any NotificationScheduling)? = nil) {
        self.notifications = notifications ?? NotificationService()
        self.calendarService = calendarService ?? EventKitAdapter()
        self.defaults = defaults
        self.defaultReminder = defaults.object(forKey: "defaultNotificationMinutes") as? Int
        self.selectedCalendarID = defaults.string(forKey: "defaultCalendarIdentifier")
        if let data = defaults.data(forKey: "pendingMirrorDeletes"),
           let queued = try? JSONDecoder().decode([MirrorReference].self, from: data) { pendingMirrorDeletes = queued }

        let context = ModelContext(container)
        context.autosaveEnabled = false
        repository = TaskRepository(context: context)
        reload()
        refreshCalendar()
    }

    var activeTasks: [Task] { tasks.filter { $0.archivedAt == nil } }
    var unscheduledTasks: [Task] {
        activeTasks.filter { task in
            !occurrences.contains { $0.taskID == task.id && $0.planResult == .pending }
        }
    }

    func reload() {
        do {
            tasks = try repository.tasks(includeArchived: true)
            rememberCategories()
            occurrences = try repository.allOccurrences()
            reviewedKeys = Set(try repository.reviews().map(\.dateKey))
        } catch { errorMessage = error.localizedDescription }
    }

    @discardableResult
    func perform(_ operation: () throws -> Void) -> Bool {
        do {
            try operation()
            try repository.save()
            reload()
            return true
        } catch {
            errorMessage = "保存できませんでした。\(error.localizedDescription)"
            return false
        }
    }

    func refreshCalendar() {
        calendarAccess = calendarService.access
        calendarChoices = calendarService.calendars()
        guard calendarAccess == .full else {
            events = []
            calendarMessage = "カレンダーを連携すると、通常の予定も表示できます。"
            return
        }
        do {
            if let selectedCalendarID, !calendarChoices.contains(where: { $0.id == selectedCalendarID }) {
                calendarMessage = CalendarFailure.calendarUnavailable.localizedDescription
            } else { calendarMessage = selectedCalendarID == nil ? CalendarFailure.selectCalendar.localizedDescription : nil }
            let start = Calendar.current.startOfDay(for: displayDay)
            events = try calendarService.events(from: start, to: Calendar.current.date(byAdding: .day, value: 1, to: start)!)
            var changed = false
            for occurrence in occurrences {
                if let id = occurrence.calendarEventIdentifier, try !calendarService.mirrorExists(id) {
                    occurrence.calendarEventIdentifier = nil
                    occurrence.calendarIdentifier = nil
                    changed = true
                }
            }
            if changed { try repository.save() }
        } catch {
            events = []
            calendarMessage = error.localizedDescription
        }
    }

    func connectCalendar() async {
        do { _ = try await calendarService.requestAccess(); refreshCalendar() }
        catch { calendarMessage = error.localizedDescription }
    }

    func syncMirror(_ occurrence: TaskOccurrence, title: String) {
        guard let start = occurrence.scheduledStart, let end = occurrence.scheduledEnd else { return }
        do {
            let ref = try calendarService.saveMirror(title: title, occurrenceID: occurrence.id, start: start, end: end,
                                                    existingID: occurrence.calendarEventIdentifier, calendarID: selectedCalendarID)
            occurrence.calendarEventIdentifier = ref.eventIdentifier
            occurrence.calendarIdentifier = ref.calendarIdentifier
            try repository.save()
            calendarWriteMessage = nil
        } catch { calendarWriteMessage = "Task は保存済みです。" + error.localizedDescription }
    }

    func retryCalendar() {
        calendarWriteMessage = nil
        drainMirrorDeletes()
        for occurrence in occurrences where occurrence.scheduledStart != nil {
            if let task = tasks.first(where: { $0.id == occurrence.taskID }) { syncMirror(occurrence, title: task.title) }
        }
        refreshCalendar()
    }

    func archive(_ task: Task) -> Bool {
        let now = currentTime
        let future = history(for: task).filter { $0.planResult == .pending && ($0.scheduledStart ?? .distantPast) > now }
        let refs = future.map { MirrorReference(occurrenceID: $0.id, eventIdentifier: $0.calendarEventIdentifier, calendarIdentifier: $0.calendarIdentifier) }
        guard perform({ try repository.archive(task, at: now) }) else { return false }
        for reference in refs { notifications.remove(occurrenceID: reference.occurrenceID) }
        pendingMirrorDeletes.append(contentsOf: refs)
        persistMirrorDeletes()
        drainMirrorDeletes()
        refreshCalendar()
        return true
    }

    /// Shared Task-editor save: one local save, then retryable Calendar / notification effects.
    func saveTask(_ task: Task?, title: String, category: String, estimatedDuration: TimeInterval?,
                  editing original: TaskOccurrence?, scheduledStart: Date?, duration: TimeInterval,
                  reminder: Int?, now: Date = Date()) -> Bool {
        let target = task ?? Task(title: title)
        let originalID = original?.id
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty, duration.isFinite, duration > 0, target.archivedAt == nil,
              original.map({ $0.taskID == target.id && $0.planResult == .pending }) ?? true else { return false }
        let removed = scheduledStart == nil ? original.map {
            MirrorReference(occurrenceID: $0.id, eventIdentifier: $0.calendarEventIdentifier, calendarIdentifier: $0.calendarIdentifier)
        } : nil
        guard perform({
            if let original {
                if let start = scheduledStart {
                    var next = original
                    if original.scheduledStart != start || original.scheduledEnd != start.addingTimeInterval(duration) {
                        next = try repository.reschedule(original, to: start, duration: duration, now: now)
                    }
                    next.notificationMinutesBefore = reminder
                } else { try repository.removeFuturePlan(original, now: now) }
            }
            target.title = normalizedTitle
            let name = category.trimmingCharacters(in: .whitespacesAndNewlines)
            target.category = name.isEmpty ? nil : name
            target.estimatedDuration = estimatedDuration
            if task == nil { repository.insert(target) }
            if original == nil, let start = scheduledStart {
                let next = TaskOccurrence(taskID: target.id, scheduledStart: start, duration: duration)
                next.notificationMinutesBefore = reminder
                try repository.insert(next)
            }
        }) else { return false }
        if let originalID { notifications.remove(occurrenceID: originalID) }
        if let removed {
            pendingMirrorDeletes.append(removed)
            persistMirrorDeletes()
            drainMirrorDeletes()
        }
        for occurrence in history(for: target) where occurrence.scheduledStart != nil {
            syncMirror(occurrence, title: target.title)
            _Concurrency.Task { await updateNotification(occurrence, title: target.title) }
        }
        refreshCalendar()
        return true
    }

    private func persistMirrorDeletes() {
        defaults.set(try? JSONEncoder().encode(pendingMirrorDeletes), forKey: "pendingMirrorDeletes")
    }

    func drainMirrorDeletes() {
        for reference in pendingMirrorDeletes {
            do {
                try calendarService.removeMirror(reference)
                pendingMirrorDeletes.removeAll { $0 == reference }
            } catch { calendarMessage = "古いカレンダー予定を削除できません。設定から再試行してください。" }
        }
        persistMirrorDeletes()
    }

    func updateNotification(_ occurrence: TaskOccurrence, title: String) async {
        notifications.remove(occurrenceID: occurrence.id)
        guard let reminder = ReminderPolicy.reminder(id: occurrence.id, title: title, start: occurrence.scheduledStart,
                                                     result: occurrence.planResult, minutes: occurrence.notificationMinutesBefore, now: Date()) else { return }
        notificationsAuthorized = await notifications.isAuthorized()
        // Authorization is asynchronous: an occurrence may have been archived or resolved while waiting.
        guard occurrences.contains(where: { $0.id == occurrence.id && $0.planResult == .pending }),
              ReminderPolicy.reminder(id: occurrence.id, title: title, start: occurrence.scheduledStart,
                                      result: occurrence.planResult, minutes: occurrence.notificationMinutesBefore, now: Date()) == reminder else { return }
        guard notificationsAuthorized else {
            notificationMessage = "通知は許可されていません。設定から許可すると、通知を予約できます。"
            return
        }
        do {
            try await notifications.schedule(reminder)
            if !occurrences.contains(where: { $0.id == occurrence.id && $0.planResult == .pending }) {
                notifications.remove(occurrenceID: occurrence.id)
            }
            notificationMessage = nil
        }
        catch { notificationMessage = "Task は保存済みですが、通知を予約できませんでした。設定から再試行してください。" }
    }

    func connectNotifications() async {
        do { notificationsAuthorized = try await notifications.requestAccess() }
        catch { notificationMessage = error.localizedDescription }
        await retryNotifications()
    }

    func retryNotifications() async {
        notificationsAuthorized = await notifications.isAuthorized()
        for occurrence in occurrences {
            if let task = tasks.first(where: { $0.id == occurrence.taskID }) { await updateNotification(occurrence, title: task.title) }
        }
    }

    private func busyIntervals(excluding occurrence: TaskOccurrence, from start: Date, to end: Date) throws -> [DateInterval] {
        let calendarEvents = try calendarService.events(from: start, to: end)
        let mirrors = Set(occurrences.compactMap(\.calendarEventIdentifier) + pendingMirrorDeletes.compactMap(\.eventIdentifier))
        let ordinary = calendarEvents.filter { !mirrors.contains($0.identifier) }.map { DateInterval(start: $0.start, end: $0.end) }
        let pocket = occurrences.filter { $0.id != occurrence.id && $0.planResult == .pending }.compactMap { record -> DateInterval? in
            guard let start = record.scheduledStart, let end = record.scheduledEnd else { return nil }
            return DateInterval(start: start, end: end)
        }
        return ordinary + pocket
    }

    func suggestion(for task: Task) throws -> ScheduleSuggestion? {
        guard task.archivedAt == nil else { return nil }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 15, to: now)!
        for occurrence in history(for: task).filter({ $0.planResult == .pending }).sorted(by: { $0.scheduledStart! < $1.scheduledStart! }) {
            let busy = try busyIntervals(excluding: occurrence, from: now, to: end)
            if let suggestion = SuggestionEngine.suggest(for: occurrence.record, history: history(for: task).map(\.record), busy: busy, now: now) { return suggestion }
        }
        return nil
    }

    func applySuggestion(_ suggestion: ScheduleSuggestion) async {
        guard let occurrence = occurrences.first(where: { $0.id == suggestion.occurrenceID }), occurrence.planResult == .pending,
              let task = tasks.first(where: { $0.id == occurrence.taskID }), task.archivedAt == nil else { return }
        do {
            let busy = try busyIntervals(excluding: occurrence, from: suggestion.start, to: suggestion.end)
            guard suggestion.start > Date(), SuggestionEngine.isFree(start: suggestion.start, end: suggestion.end, busy: busy) else {
                errorMessage = "候補の時間に別の予定が入りました。提案を更新してください。"; return
            }
            var next: TaskOccurrence?
            guard perform({ next = try repository.reschedule(occurrence, to: suggestion.start, duration: suggestion.end.timeIntervalSince(suggestion.start), now: Date()) }), let next else { return }
            notifications.remove(occurrenceID: occurrence.id)
            syncMirror(next, title: task.title)
            await updateNotification(next, title: task.title)
            refreshCalendar()
        } catch { errorMessage = error.localizedDescription }
    }

    func history(for task: Task) -> [TaskOccurrence] {
        occurrences.filter { $0.taskID == task.id }.sorted {
            ($0.scheduledStart ?? $0.actualExecutedAt ?? $0.createdAt) >
            ($1.scheduledStart ?? $1.actualExecutedAt ?? $1.createdAt)
        }
    }
}
