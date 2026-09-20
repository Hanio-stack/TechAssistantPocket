import SwiftUI

struct TodayView: View {
    @Environment(PocketStore.self) private var store
    @State private var day = Date()
    @State private var recordingTask: Task?
    private struct ReviewSelection: Identifiable { let day: Date; var id: Date { day } }
    @State private var reviewSelection: ReviewSelection?
    @Environment(\.scenePhase) private var scenePhase
    @State private var followingToday = true

    var body: some View {
        List {
            Section {
                DatePicker("表示する日", selection: $day, displayedComponents: .date)
                if !Calendar.current.isDateInToday(day) { Button("今日に戻る") { day = Date() } }
            }
            if let message = store.integrationMessage {
                Section { Text(message).font(.subheadline).foregroundStyle(.secondary) }
            }
            Section("やることも、予定も、ひとつに。") {
                let entries = Timeline.entries(on: day, records: store.occurrences.map(\.record), events: store.events.filter { event in !store.pendingMirrorDeletes.contains { $0.eventIdentifier == event.identifier } })
                if entries.isEmpty { Text("この日の予定はありません").foregroundStyle(.secondary) }
                ForEach(entries) { entry in
                    switch entry {
                    case .task(let record):
                        if let task = store.tasks.first(where: { $0.id == record.taskID }),
                           let occurrence = store.occurrences.first(where: { $0.id == record.id }) {
                            NavigationLink {
                                OccurrenceDetailView(task: task, occurrence: occurrence)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: record.result == .pending ? "circle" : (record.result == .success ? "checkmark.circle.fill" : "minus.circle"))
                                        .foregroundStyle(.tint).font(.title3)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(task.title).font(.headline)
                                        Text(entry.start.formatted(date: .omitted, time: .shortened))
                                        Text(record.result?.label ?? "").font(.caption).foregroundStyle(.secondary)
                                    }
                                }.padding(.vertical, 6)
                            }
                        }
                    case .event(let event):
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "calendar").foregroundStyle(.orange).font(.title3)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(event.title).font(.headline)
                                Text(event.isAllDay ? "終日 · 予定" : "\(event.start.formatted(date: .omitted, time: .shortened)) · 予定")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                if let location = event.location, !location.isEmpty { Text(location).font(.caption) }
                            }
                        }.padding(.vertical, 6)
                    }
                }
            }
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                if let day = ReviewPolicy.latestDay(records: store.occurrences.map(\.record), reviewedKeys: store.reviewedKeys, now: timeline.date) {
                    Button {
                        reviewSelection = ReviewSelection(day: day)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(Calendar.current.isDateInToday(day) ? "今日を振り返る" : (Calendar.current.isDateInYesterday(day) ? "昨日を振り返る" : "\(day.formatted(date: .abbreviated, time: .omitted))を振り返る"))
                                .font(.headline)
                            Text("実行した時刻から、次の予定を見つけましょう。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }.accessibilityIdentifier("reviewCTA")
                }
            }
            Section("未スケジュール") {
                ForEach(store.unscheduledTasks) { task in
                    HStack {
                        Button { recordingTask = task } label: { Image(systemName: "circle").font(.title2) }
                            .buttonStyle(.borderless).accessibilityLabel("\(task.title)の実行を記録")
                        NavigationLink(task.title) { TaskDetailView(task: task) }
                    }
                }
                if store.unscheduledTasks.isEmpty { Text("未スケジュールの Task はありません").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Today")
        .onChange(of: day) { _, day in
            followingToday = Calendar.current.isDateInToday(day)
            store.displayDay = day; store.refreshCalendar()
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active && followingToday { day = Date() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            if followingToday { day = Date() }
            store.refreshCalendar()
        }
        .refreshable { store.reload(); store.refreshCalendar() }
        .sheet(item: $reviewSelection) { selection in ReviewView(day: selection.day) }
        .sheet(item: $recordingTask) { task in ExecutionEditor(task: task, occurrence: nil) }
    }
}
