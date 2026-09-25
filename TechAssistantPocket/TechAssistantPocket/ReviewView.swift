import SwiftUI

struct ReviewView: View {
    @Environment(PocketStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let day: Date
    @State private var recording: TaskOccurrence?
    private var pending: [TaskOccurrence] {
        store.occurrences.filter { $0.planResult == .pending && ($0.scheduledStart.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false) }
            .sorted { $0.scheduledStart! < $1.scheduledStart! }
    }
    var body: some View {
        NavigationStack {
            List {
                if let message = store.errorMessage { Text(message).foregroundStyle(.red) }
                Section {
                    Text(day.formatted(date: .complete, time: .omitted))
                    Text("未確定の Task だけ確認しましょう。通常の予定は振り返りに含めません。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if pending.isEmpty { Text("すべての Task を確認できました。振り返りを完了しましょう。") }
                ForEach(pending) { occurrence in
                    Section {
                        let task = store.tasks.first { $0.id == occurrence.taskID }
                        Text(CategoryAnalyticsEngine.name(task?.category)).font(.headline)
                        Text(task?.title ?? "Task").font(.subheadline).foregroundStyle(.secondary)
                        OccurrenceSummary(occurrence: occurrence)
                        Button("予定どおりできた") {
                            if let start = occurrence.scheduledStart,
                               store.perform({ try occurrence.recordExecution(startedAt: start) }) {
                                store.notifications.remove(occurrenceID: occurrence.id)
                            }
                        }
                        Text("予定開始時刻を実際の開始として記録します。")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("後でやった") { recording = occurrence }
                        Button("できなかった") {
                            if store.perform({ try occurrence.markMissed() }) { store.notifications.remove(occurrenceID: occurrence.id) }
                        }
                        Button("キャンセルした") {
                            if store.perform({ try occurrence.cancel() }) { store.notifications.remove(occurrenceID: occurrence.id) }
                        }
                    }
                }
                Button("振り返りを完了") {
                    if store.perform({ try store.repository.finishReview(on: day, now: Date()) }) { dismiss() }
                }.disabled(!pending.isEmpty).accessibilityIdentifier("finishReview")
            }
            .navigationTitle("一日を振り返る")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
            .sheet(item: $recording) { occurrence in
                if let task = store.tasks.first(where: { $0.id == occurrence.taskID }) { ExecutionEditor(task: task, occurrence: occurrence, laterOnly: true) }
            }
        }
    }
}
