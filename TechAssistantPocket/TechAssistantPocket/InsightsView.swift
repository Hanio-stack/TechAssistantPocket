import SwiftUI

struct InsightsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(PocketStore.self) private var store
    var body: some View {
        List {
            Section {
                let rate = InsightsEngine.plannedRate(store.occurrences.map(\.record), interval: InsightsEngine.week(containing: Date()))
                VStack(alignment: .leading, spacing: 12) {
                    Text("今週の成功率").font(.headline)
                    Text("予定どおりできた割合").font(.subheadline).foregroundStyle(.secondary)
                    if dynamicTypeSize.isAccessibilitySize {
                        Text(rate.text).font(.largeTitle.bold()).foregroundStyle(.tint)
                        Text("\(rate.total)件中\(rate.successes)件").font(.subheadline)
                    } else {
                    HStack {
                        Spacer()
                        ZStack {
                            Circle().stroke(.quaternary, lineWidth: 12)
                            Circle().trim(from: 0, to: rate.rate ?? 0).stroke(.tint, style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(-90))
                            VStack {
                                Text(rate.text).font(.largeTitle.bold())
                                Text("\(rate.total)件中\(rate.successes)件").font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(width: 150, height: 150).padding(.vertical, 12)
                        .accessibilityElement(children: .ignore).accessibilityLabel("今週の予定成功率 \(rate.text)、\(rate.total)件中\(rate.successes)件")
                        Spacer()
                    }
                    }
                    if rate.total == 0 { Text("予定の結果を記録すると、成功率が表示されます。").font(.subheadline).foregroundStyle(.secondary) }
                }.padding(.vertical, 8)
            }
            Section {
                ForEach(store.tasks.filter { $0.archivedAt == nil || !store.history(for: $0).isEmpty }) { task in
                    NavigationLink {
                        TaskInsightView(task: task)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(task.title).font(.headline)
                            Text("予定成功率 \(InsightsEngine.plannedRate(store.history(for: task).map(\.record)).text)\(task.archivedAt == nil ? "" : " · アーカイブ済み")")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                }
                if store.tasks.isEmpty { Text("Task を追加して記録を始めましょう。").foregroundStyle(.secondary) }
            } header: { Text("タスク別") } footer: { Text("タップして曜日・時間帯の傾向を見る") }
        }.navigationTitle("Insights")
    }
}

struct TaskInsightView: View {
    @Environment(PocketStore.self) private var store
    let task: Task
    @State private var suggestion: ScheduleSuggestion?
    @State private var suggestionMessage: String?
    @State private var confirming = false
    @State private var applying = false
    private var records: [OccurrenceRecord] { store.history(for: task).map(\.record) }

    var body: some View {
        List {
            Section("予定成功率") {
                let rate = InsightsEngine.plannedRate(records)
                Text(rate.text).font(.largeTitle.bold()).foregroundStyle(.tint)
                Text("\(rate.total)件中\(rate.successes)件が予定した時間枠で実行できました。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("成功しやすい曜日") {
                let counts = InsightsEngine.weekdays(records)
                ForEach(0..<7) { index in
                    let weekday = (Calendar.current.firstWeekday - 1 + index) % 7 + 1
                    ObservationRow(title: Calendar.current.weekdaySymbols[weekday - 1], counts: counts[weekday] ?? SuccessRate())
                }
            }
            Section {
                let counts = InsightsEngine.timeBands(records)
                ForEach(TimeBand.allCases) { band in ObservationRow(title: band.label, counts: counts[band] ?? SuccessRate()) }
            } header: { Text("成功しやすい時間帯") } footer: {
                Text("曜日・時間帯は、予定枠の成否と実際の開始時刻の観測です。予定なしや後からの実行も含み、同じ条件での成功を二重に数えません。予定成功率とは別の指標です。")
            }
            if task.archivedAt == nil {
                Section("おすすめ") {
                    if let suggestion {
                        Text(suggestion.start.formatted(date: .complete, time: .shortened)).font(.headline)
                            .accessibilityIdentifier("suggestionDate")
                        Text(suggestion.reason).font(.subheadline)
                        Text("この時間はカレンダーと Pocket の予定に重なっていません。変更前に再確認します。")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("この時間に変更する") { confirming = true }.disabled(applying)
                    } else {
                        Text(suggestionMessage ?? "同じ曜日・時間帯の記録を3件以上集めると、改善できそうな予定に提案が表示されます。")
                            .foregroundStyle(.secondary)
                    }
                    Button("提案を更新") { loadSuggestion() }
                }
            }
        }
        .navigationTitle(task.title)
        .onAppear { loadSuggestion() }
        .alert("予定を変更しますか？", isPresented: $confirming) {
            Button("キャンセル", role: .cancel) { }
            Button("この時間に変更する") {
                guard let suggestion else { return }
                applying = true
                _Concurrency.Task {
                    await store.applySuggestion(suggestion)
                    applying = false
                    loadSuggestion()
                }
            }
        } message: {
            if let suggestion { Text("\(suggestion.start.formatted(date: .complete, time: .shortened))へ変更します。開始済みの元の予定は未実行の履歴として残ります。") }
        }
    }
    private func loadSuggestion() {
        do { suggestion = try store.suggestion(for: task); suggestionMessage = nil }
        catch { suggestion = nil; suggestionMessage = error.localizedDescription }
    }
}

private struct ObservationRow: View {
    let title: String
    let counts: SuccessRate
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold())
            ProgressView(value: counts.rate ?? 0)
            Text("\(counts.text) · 成功観測\(counts.successes)件 / 全\(counts.total)件")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 3)
    }
}
