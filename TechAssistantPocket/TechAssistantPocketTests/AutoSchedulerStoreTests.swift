import Foundation
import SwiftData
import Testing
@testable import TechAssistantPocket

@MainActor struct AutoSchedulerStoreTests {
    final class Clock { var date: Date; init(_ date: Date) { self.date = date } }
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Tokyo")!; return c }
    private func date(_ hour: Int, _ minute: Int = 0) -> Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: hour, minute: minute))! }
    private func setup() throws -> (AutoSchedulerStore, FixtureCalendarService, Clock, ModelContainer, UserDefaults) {
        let container = try PocketSchedulerSchema.container(configuration: ModelConfiguration(isStoredInMemoryOnly: true))
        let defaults = UserDefaults(suiteName: "scheduler.tests.\(UUID())")!
        let settings = SchedulerSettings(wakeMinutes: 480, bedMinutes: 90, work: WorkWindowPolicy(weekday: WorkClockRange(startMinutes: 780, endMinutes: 960), weekend: WorkClockRange(startMinutes: 780, endMinutes: 960)))
        defaults.set(try JSONEncoder().encode(settings), forKey: "autoSchedulerSettings")
        defaults.set("fixture", forKey: "defaultCalendarIdentifier")
        let service = FixtureCalendarService(), clock = Clock(date(13))
        let store = AutoSchedulerStore(container: container, calendarService: service, defaults: defaults, calendar: calendar, clock: { clock.date })
        return (store, service, clock, container, defaults)
    }
    private func seed(_ store: AutoSchedulerStore) {
        #expect(store.saveTask(title: "アニメーション", genre: "BK", priority: 3, minutes: 180))
        #expect(store.saveTask(title: "音楽", genre: "制作", priority: 2, minutes: 60))
        #expect(store.saveTask(title: "読書", genre: "学習", priority: 1, minutes: 30))
    }
    @Test func fullEarlyCompletionFlowRecalculatesAndSynchronizesOwnedEvents() throws {
        let (store, service, clock, _, _) = try setup(); seed(store)
        let first = try #require(store.current)
        #expect(first.title == "アニメーション")
        clock.date = date(15, 20)
        #expect(store.act(.completed, proposalID: first.id))
        let next = try #require(store.current)
        #expect(next.title == "読書" && next.proposedAt == date(15, 20) && next.plannedEnd == date(15, 50))
        #expect(store.backlog.map(\.title).sorted() == ["読書", "音楽"].sorted())
        #expect(store.completed.map(\.title) == ["アニメーション"])
        #expect(store.actions.count == 1 && store.actions[0].occurredAt == date(15, 20))
        #expect(service.stored.first { $0.pocketProposalID == first.id }?.end == date(15, 20))
        #expect(service.stored.first { $0.pocketProposalID == next.id }?.start == date(15, 20))
        clock.date = date(15, 21); store.refresh()
        #expect(store.current?.id == next.id) // Do not compare the full estimate to the shrinking remainder.
        #expect(!store.act(.completed, proposalID: first.id))
        #expect(store.actions.count == 1)
    }
    @Test func skipSurvivesRefreshAndRestartAndReturnsAfterAnotherAction() throws {
        let (store, service, clock, container, defaults) = try setup(); seed(store)
        let first = try #require(store.current)
        #expect(store.act(.skipped, proposalID: first.id))
        #expect(store.backlog.count == 3 && store.current?.title == "音楽")
        store.refresh(); store.refresh()
        let restarted = AutoSchedulerStore(container: container, calendarService: service, defaults: defaults, calendar: calendar, clock: { clock.date })
        #expect(restarted.current?.title == "音楽")
        let second = try #require(restarted.current)
        #expect(restarted.act(.skipped, proposalID: second.id))
        #expect(restarted.current?.title == "アニメーション")
        #expect(restarted.actions.map(\.sequence) == [1, 2])
    }
    @Test func onlyTaskDoesNotBounceAfterSkipAndReturnsNextSession() throws {
        let (store, _, clock, _, _) = try setup()
        #expect(store.saveTask(title: "制作", genre: "BK", priority: 3, minutes: 30))
        #expect(store.act(.skipped, proposalID: try #require(store.current).id))
        store.refresh(); #expect(store.current == nil && store.backlog.count == 1)
        clock.date = calendar.date(byAdding: .day, value: 1, to: date(13))!
        store.refresh(); #expect(store.current?.title == "制作")
    }
    @Test func busyBoundariesAndReadFailuresDoNotPretendCalendarIsEmpty() throws {
        let (store, service, clock, _, _) = try setup()
        service.stored = [CalendarEvent(identifier: "meeting", calendarIdentifier: "ordinary", title: "会議", start: date(13), end: date(14))]
        seed(store); #expect(store.current == nil)
        clock.date = date(14); store.refresh()
        #expect(store.current?.title == "音楽")
        let id = store.current?.id
        service.failReads = true; store.refresh()
        #expect(store.current == nil && store.calendarMessage != nil)
        service.failReads = false; store.refresh()
        #expect(store.current?.id == id)
        #expect(service.stored.contains { $0.identifier == "meeting" && $0.start == date(13) && $0.end == date(14) })
    }
    @Test func writeFailureRetainsActionAndRetriesWithoutDuplicatingEvents() throws {
        let (store, service, clock, _, _) = try setup(); seed(store)
        let first = try #require(store.current)
        service.failWrites = true; clock.date = date(15, 20)
        #expect(store.act(.completed, proposalID: first.id))
        #expect(store.completed.count == 1 && store.actions.count == 1 && store.current?.title == "読書")
        #expect(store.proposals.contains { $0.needsSync })
        service.failWrites = false; store.refresh(); store.refresh()
        #expect(!store.proposals.contains { $0.needsSync })
        #expect(service.stored.count == 2 && store.actions.count == 1)
    }
    @Test func ownershipExcludesMirrorsBeforeDedupeAndNeverAdoptsOrdinaryIDs() throws {
        let (_, service, _, _, _) = try setup()
        let id = UUID()
        let ordinary = CalendarEvent(identifier: "ordinary", calendarIdentifier: "fixture", title: "同じタイトル", start: date(13), end: date(14))
        service.stored = [ordinary]
        let allocation = PocketCalendarAllocation(proposalID: id, title: ordinary.title, start: date(13), end: date(14), lookupEnd: date(14), existingID: ordinary.identifier, calendarID: "fixture")
        let saved = try #require(try service.syncAllocation(allocation, destination: "fixture"))
        #expect(saved.eventIdentifier != ordinary.identifier)
        #expect(CalendarReadPolicy.visibleEvents(service.stored).map(\.identifier) == ["ordinary"])
        #expect(PocketCalendarOwnership.proposalID(from: PocketCalendarOwnership.url(for: id)) == id)
        #expect(PocketCalendarOwnership.proposalID(from: URL(string: "https://proposal/\(id)")) == nil)
        #expect(PocketCalendarOwnership.proposalID(from: URL(string: "pocket://proposal/\(id)?other=1")) == nil)
        _ = try service.syncAllocation(allocation, destination: "fixture")
        #expect(service.stored.count == 2)
    }
    @Test func editingAndCompletionDoNotResurrectAndCategoryHistoryPersists() throws {
        let (store, service, clock, container, defaults) = try setup()
        #expect(store.saveTask(title: "動画", genre: "  アニメ  ", priority: 2, minutes: 30))
        let task = try #require(store.backlog.first)
        #expect(store.saveTask(existing: task, title: "動画2", genre: "BK", priority: 3, minutes: 60))
        #expect(store.tasks.count == 1 && store.states.count == 1)
        #expect(store.categoryNames == ["BK", "アニメ"])
        #expect(store.act(.completed, proposalID: try #require(store.current).id))
        clock.date = calendar.date(byAdding: .day, value: 1, to: clock.date)!
        let restarted = AutoSchedulerStore(container: container, calendarService: service, defaults: defaults, calendar: calendar, clock: { clock.date })
        #expect(restarted.current == nil && restarted.backlog.isEmpty && restarted.completed.count == 1)
        #expect(restarted.categoryNames.contains("アニメ"))
    }
}
