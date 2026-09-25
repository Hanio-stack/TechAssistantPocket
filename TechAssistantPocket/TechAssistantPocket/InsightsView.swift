import SwiftUI

struct InsightsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(PocketStore.self) private var store
    var body: some View {
        List {
            Section {
                let rate = CategoryAnalyticsEngine.weeklyRate(store.occurrences.map(\.record), now: store.currentTime, lifeDay: store.lifeDay)
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
                ForEach(store.categorySummaries) { summary in
                    NavigationLink {
                        CategoryInsightView(name: summary.name)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(summary.name).font(.headline)
                            Text("予定成功率 \(summary.plannedRate.text) · 実行\(summary.executionCount)件")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                }
                if store.tasks.isEmpty { Text("Task を追加して記録を始めましょう。").foregroundStyle(.secondary) }
            } header: { Text("カテゴリ別") } footer: { Text("タップして曜日・時間帯の傾向を見る") }
        }.navigationTitle("Insights")
    }
}

struct CategoryInsightView: View {
    @Environment(PocketStore.self) private var store
    let name: String
    @State private var suggestion: ScheduleSuggestion?
    @State private var suggestionMessage: String?
    @State private var confirming = false
    @State private var applying = false
    private var summary: CategoryAnalyticsEngine.Summary? { store.categorySummaries.first { $0.name == name } }
    private var records: [OccurrenceRecord] { summary?.records ?? [] }
    private var tasks: [Task] { store.activeTasks.filter { CategoryAnalyticsEngine.name($0.category) == name } }
    private var suggestedTaskTitle: String? {
        guard let id = suggestion?.occurrenceID,
              let plan = store.occurrences.first(where: { $0.id == id }) else { return nil }
        return store.tasks.first { $0.id == plan.taskID }?.title
    }

    var body: some View {
        List {
            Section("予定成功率") {
                let rate = InsightsEngine.plannedRate(records)
                Text(rate.text).font(.largeTitle.bold()).foregroundStyle(.tint)
                Text("実行件数 \(summary?.executionCount ?? 0)件")
                Text("\(rate.total)件中\(rate.successes)件が予定した時間枠で実行できました。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("成功しやすい曜日") {
                let counts = CategoryAnalyticsEngine.weekdays(records, lifeDay: store.lifeDay)
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
            if !tasks.isEmpty {
                Section("おすすめ") {
                    if let suggestion {
                        if let title = suggestedTaskTitle { Text(title).font(.headline) }
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
        .navigationTitle(name)
        .onAppear { loadSuggestion() }
        .onChange(of: store.lifeDay) { _, _ in loadSuggestion() }
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
        do {
            suggestion = nil
            for task in tasks {
                if let found = try store.suggestion(for: task) { suggestion = found; break }
            }
            suggestionMessage = nil
        }
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
            Text("\(counts.total < 3 ? "データ不足" : counts.text) · 成功観測\(counts.successes)件 / 全\(counts.total)件")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 3)
    }
}
