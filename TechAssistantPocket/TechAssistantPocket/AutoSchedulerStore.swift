import Foundation
import Observation
import SwiftData

@MainActor @Observable final class AutoSchedulerStore {
    let repository: SchedulerRepository
    let calendarService: any CalendarService
    let defaults: UserDefaults
    private let calendar: Calendar
    private let clock: () -> Date
    private var refreshing = false
    private(set) var settings: SchedulerSettings?
    private(set) var tasks: [Task] = []
    private(set) var states: [BacklogTaskState] = []
    private(set) var proposals: [TaskProposal] = []
    private(set) var actions: [TaskActionRecord] = []
    private(set) var legacyOccurrences: [TaskOccurrence] = []
    private(set) var current: TaskProposal?
    private(set) var emptyMessage = "作業可能時間を設定してください"
    private(set) var calendarMessage: String?
    private(set) var categoryNames: [String] = []
    var errorMessage: String?
    var selectedCalendarID: String? {
        didSet {
            defaults.set(selectedCalendarID, forKey: "defaultCalendarIdentifier")
        }
    }
    var now: Date { clock() }
    var backlog: [Task] {
        tasks.filter { task in task.archivedAt == nil && states.contains { $0.taskID == task.id && $0.completedAt == nil } }
    }
    var completed: [Task] {
        tasks.filter { task in states.contains { $0.taskID == task.id && $0.completedAt != nil } }
            .sorted { (state(for: $0)?.completedAt ?? .distantPast) > (state(for: $1)?.completedAt ?? .distantPast) }
    }
    func state(for task: Task) -> BacklogTaskState? { states.first { $0.taskID == task.id } }

    init(container: ModelContainer, calendarService: (any CalendarService)? = nil,
         defaults: UserDefaults = .standard, calendar: Calendar = .current, clock: @escaping () -> Date = Date.init) {
        repository = SchedulerRepository(container: container)
        self.calendarService = calendarService ?? EventKitAdapter(); self.defaults = defaults; self.calendar = calendar; self.clock = clock
        selectedCalendarID = defaults.string(forKey: "defaultCalendarIdentifier")
        if let data = defaults.data(forKey: "autoSchedulerSettings") {
            settings = try? JSONDecoder().decode(SchedulerSettings.self, from: data)
            if settings?.isValid != true { settings = nil }
        }
        refresh()
    }
    private func load() throws {
        tasks = try repository.tasks(); states = try repository.states()
        proposals = try repository.proposals(); actions = try repository.actions()
        legacyOccurrences = try repository.legacyOccurrences()
        categoryNames = Array(Set(((defaults.stringArray(forKey: "taskCategoryHistory") ?? []) + tasks.compactMap(\.category))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        defaults.set(categoryNames, forKey: "taskCategoryHistory")
    }
    @discardableResult func saveSettings(_ value: SchedulerSettings) -> Bool {
        guard value.isValid else { errorMessage = "開始と終了は異なる時刻にしてください。日跨ぎは設定できます。"; return false }
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: "autoSchedulerSettings")
            defaults.set(value.wakeMinutes, forKey: "lifeWakeMinutes"); defaults.set(value.bedMinutes, forKey: "lifeBedMinutes")
            settings = value
            // Legacy schedules remain history, but no longer prompt the retired execution flow.
            let notifications = NotificationService()
            for occurrence in legacyOccurrences where occurrence.planResult == .pending { notifications.remove(occurrenceID: occurrence.id) }
            refresh(); return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    @discardableResult func saveTask(existing: Task? = nil, title: String, genre: String, priority: Int, minutes: Int) -> Bool {
        do {
            try repository.saveTask(existing: existing, title: title, genre: genre, priority: priority, minutes: minutes, now: now)
            refresh(); return true
        } catch { errorMessage = error.localizedDescription; refresh(); return false }
    }
    @discardableResult func archive(_ task: Task) -> Bool {
        do { try repository.archive(task, at: now); refresh(); return true }
        catch { errorMessage = error.localizedDescription; refresh(); return false }
    }
    @discardableResult func act(_ kind: TaskActionKind, proposalID: UUID) -> Bool {
        guard current?.id == proposalID else { return false }
        do { try repository.record(kind, proposalID: proposalID, at: now); refresh(); return true }
        catch { errorMessage = error.localizedDescription; refresh(); return false }
    }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            try load()
            guard let settings else { current = nil; return }
            let now = now
            let window = settings.work.currentWindow(at: now, calendar: calendar)
            var busy: [DateInterval] = []
            calendarMessage = nil
            if calendarService.access == .full, let window {
                do {
                    let raw = try calendarService.events(from: window.start, to: window.end)
                    let queued = defaults.data(forKey: "pendingMirrorDeletes").flatMap { try? JSONDecoder().decode([MirrorReference].self, from: $0) } ?? []
                    let mirrors = Set(legacyOccurrences.compactMap(\.calendarEventIdentifier) + proposals.compactMap(\.mirrorID) + queued.compactMap(\.eventIdentifier))
                    busy = CalendarReadPolicy.visibleEvents(raw, excludingMirrorIDs: mirrors)
                        .filter { $0.end > $0.start }.map { DateInterval(start: $0.start, end: $0.end) }
                } catch {
                    current = nil; emptyMessage = "カレンダーの確認ができませんでした"
                    calendarMessage = "空き時間を安全に確認できるまで新しいTaskを提案しません。設定から再試行してください。"
                    return
                }
            } else if calendarService.access != .full {
                calendarMessage = "カレンダー未連携：外部予定を考慮していません。設定から連携できます。"
            }
            let available = window.flatMap { SchedulePackingEngine.availableNow(at: now, window: $0, busy: busy) }
            var selected: TaskProposal?
            try repository.transaction {
                for proposal in proposals where proposal.closedAt == nil {
                    let eligible = backlog.contains { $0.id == proposal.taskID }
                    if selected == nil, eligible, let available, let window,
                       proposal.sessionStart == window.start, proposal.proposedAt <= now,
                       now < proposal.plannedEnd, proposal.plannedEnd <= available.end {
                        selected = proposal
                    } else {
                        proposal.closedAt = max(proposal.proposedAt, now); proposal.needsSync = true
                    }
                }
                if selected == nil, let available, let window {
                    let candidates = backlog.compactMap { task -> SchedulingCandidate? in
                        guard let state = state(for: task) else { return nil }
                        return SchedulingCandidate(id: task.id, priority: state.priority, estimatedMinutes: state.estimatedMinutes, createdAt: task.createdAt)
                    }
                    let excluded = TaskSelectionEngine.excludedTask(lastAction: actions.last?.selectionAction, sessionStart: window.start)
                    if let chosen = TaskSelectionEngine.select(from: candidates, available: available, excluding: excluded),
                       let task = backlog.first(where: { $0.id == chosen.id }), let state = state(for: task) {
                        let proposal = TaskProposal(task: task, state: state, at: now, sessionStart: window.start)
                        repository.context.insert(proposal); selected = proposal
                    }
                }
            }
            try load(); current = selected
            if backlog.isEmpty { emptyMessage = "やりたいことを追加しましょう" }
            else if window == nil { emptyMessage = "今は作業可能時間の外です" }
            else if available == nil { emptyMessage = "今はカレンダーの予定があります" }
            else { emptyMessage = "今の空き時間に入るTaskはありません" }
            synchronizeCalendar()
        } catch { current = nil; errorMessage = "保存データを更新できませんでした。\(error.localizedDescription)" }
    }

    func connectCalendar() async {
        do { _ = try await calendarService.requestAccess(); refresh() }
        catch { calendarMessage = error.localizedDescription }
    }
    func changeCalendar(_ id: String?) {
        selectedCalendarID = id
        do {
            try repository.transaction {
                for proposal in proposals where proposal.closedAt == nil { proposal.needsSync = true }
            }
            refresh()
        } catch { errorMessage = error.localizedDescription }
    }
    private func synchronizeCalendar() {
        guard calendarService.access == .full, let bridge = calendarService as? any SchedulerCalendarBridge else { return }
        guard selectedCalendarID != nil else { calendarMessage = "カレンダーは空き時間の確認に使用中です。予定を書き出すには設定で保存先を選んでください。"; return }
        do {
            for proposal in proposals {
                if !proposal.needsSync, proposal.closedAt == nil,
                   try !bridge.hasAllocation(eventID: proposal.mirrorID, proposalID: proposal.id) { proposal.needsSync = true }
                guard proposal.needsSync else { continue }
                let allocation = PocketCalendarAllocation(proposalID: proposal.id, title: proposal.genre.isEmpty ? proposal.title : "\(proposal.genre) / \(proposal.title)",
                    start: proposal.proposedAt, end: proposal.allocationEnd, lookupEnd: proposal.plannedEnd,
                    existingID: proposal.mirrorID, calendarID: proposal.calendarID ?? selectedCalendarID)
                // Only the active allocation follows a newly selected destination; history stays put.
                let reference = try bridge.syncAllocation(allocation, destination: proposal.closedAt == nil ? selectedCalendarID : allocation.calendarID)
                try repository.transaction {
                    proposal.mirrorID = reference?.eventIdentifier
                    proposal.calendarID = reference?.calendarIdentifier
                    proposal.needsSync = false
                }
            }
        } catch { calendarMessage = "Taskは保存済みです。カレンダー反映待ち：\(error.localizedDescription)" }
    }
}
