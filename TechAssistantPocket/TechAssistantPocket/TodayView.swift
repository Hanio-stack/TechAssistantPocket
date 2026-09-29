import SwiftUI
import Combine

struct TodayView: View {
    @Environment(PocketStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var day = Date()
    @State private var clockNow = Date()
    @State private var followingToday = true
    @State private var expanded = false
    @State private var dragX: CGFloat = 0
    @State private var direction = 1
    @State private var cards: [DeckCard] = []
    @State private var recording: TaskOccurrence?
    @State private var skipping: TaskOccurrence?
    @State private var showingRecords = false
    @State private var reviewDay: ReviewDay?
    private struct ReviewDay: Identifiable { let date: Date; var id: Date { date } }
    private var now: Date {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return store.currentTime }
        #endif
        return clockNow
    }
    private var presentation: Timeline.Presentation {
        Timeline.presentation(on: day, now: now, records: store.occurrences.map(\.record), events: store.events,
                              archivedTaskIDs: Set(store.tasks.filter { $0.archivedAt != nil }.map(\.id)), lifeDay: store.lifeDay)
    }
    private var isToday: Bool { Calendar.current.isDate(day, inSameDayAs: store.lifeDayToday) }
    private var motion: Animation { reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.45, dampingFraction: 0.86) }
    private var pageTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: direction > 0 ? .trailing : .leading),
                                              removal: .move(edge: direction > 0 ? .leading : .trailing))
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    HStack {
                        Button { moveDay(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                            .accessibilityLabel("前の生活日").accessibilityIdentifier("previousDay")
                        Spacer(minLength: 0)
                        VStack(spacing: 4) {
                            Text(day.formatted(.dateTime.month().day().weekday())).font(.subheadline).foregroundStyle(.secondary)
                                .accessibilityIdentifier("homeDate")
                            if !isToday { Button("今日に戻る") { changeDay(store.lifeDayToday) }.font(.caption) }
                        }
                        Spacer(minLength: 0)
                        Button { moveDay(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                            .accessibilityLabel("次の生活日").accessibilityIdentifier("nextDay")
                    }
                    ZStack {
                        deck
                            .id(Calendar.current.startOfDay(for: day))
                            .transition(pageTransition)
                    }
                    .offset(x: reduceMotion ? dragX * 0.12 : dragX)
                    .contentShape(Rectangle())
                    .simultaneousGesture(DragGesture(minimumDistance: 16)
                        .onChanged { value in
                            if abs(value.translation.width) > abs(value.translation.height) * 1.8 {
                                dragX = value.translation.width
                            }
                        }
                        .onEnded { value in
                            let offset = SwipeDecisionPolicy.direction(x: value.translation.width, y: value.translation.height,
                                                                       predictedX: value.predictedEndTranslation.width, width: geometry.size.width)
                            if offset == 0 { withAnimation(motion) { dragX = 0 } }
                            else { moveDay(offset) }
                        })
                    .accessibilityAction(named: "次の生活日") { moveDay(1) }
                    .accessibilityAction(named: "前の生活日") { moveDay(-1) }
                    .frame(minHeight: max(280, geometry.size.height * 0.54), alignment: .center)

                    Button { showingRecords = true } label: {
                        VStack(spacing: 8) {
                            if let event = presentation.upcoming.compactMap({ entry -> CalendarEvent? in
                                if case .event(let event) = entry { return event }; return nil
                            }).first {
                                Text("\(event.start.formatted(date: .omitted, time: .shortened))  \(event.title)")
                                    .font(.subheadline).foregroundStyle(.primary)
                            }
                            Text("予定・履歴・振り返り").font(.subheadline)
                        }.frame(maxWidth: .infinity).padding(.vertical, 12)
                    }.accessibilityIdentifier("homeRecords")
                    if let message = store.integrationMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 24).padding(.bottom, 24)
            }
            .clipped()
        }
        .navigationTitle("Today")
        .onAppear { if followingToday { day = store.lifeDayToday }; refreshCards(animated: false) }
        .onChange(of: store.occurrences.map(\.record)) { _, _ in refreshWhenVisible() }
        .onChange(of: store.tasks.map { "\($0.id):\($0.title):\($0.category ?? ""):\($0.archivedAt != nil)" }) { _, _ in refreshWhenVisible() }
        .onChange(of: store.lifeDay) { _, _ in if followingToday { changeDay(store.lifeDayToday) }; refreshCards() }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { date in
            clockNow = date
            if followingToday && !Calendar.current.isDate(day, inSameDayAs: store.lifeDayToday) { changeDay(store.lifeDayToday) }
            refreshWhenVisible()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { clockNow = Date(); if followingToday { changeDay(store.lifeDayToday) }; refreshWhenVisible() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            clockNow = Date(); if followingToday { changeDay(store.lifeDayToday) }; refreshCards()
        }
        .sheet(item: $recording, onDismiss: { refreshCards() }) { occurrence in
            if let task = store.tasks.first(where: { $0.id == occurrence.taskID }) { ExecutionEditor(task: task, occurrence: occurrence) }
        }
        .sheet(item: $skipping, onDismiss: { refreshCards() }) { occurrence in
            if let task = store.tasks.first(where: { $0.id == occurrence.taskID }) { SkipTaskSheet(task: task, occurrence: occurrence) }
        }
        .sheet(isPresented: $showingRecords, onDismiss: { refreshCards() }) { recordsSheet }
    }

    private var deck: some View {
        VStack(spacing: 18) {
            if cards.isEmpty {
                ContentUnavailableView("この日のTaskはありません", systemImage: "checkmark.circle", description: Text("予定や履歴は下から確認できます。"))
            } else {
                CardStackLayout(expanded: expanded) {
                    ForEach(Array(cards.prefix(4).enumerated()), id: \.element.id) { index, card in
                        cardView(card, index: index)
                            .scaleEffect(expanded ? 1 : 1 - Double(index) * 0.035, anchor: .bottom)
                            .zIndex(Double(10 - index))
                            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity, removal: .move(edge: .trailing).combined(with: .opacity)))
                            .accessibilityHidden(!expanded && index > 0)
                    }
                }
                Button(expanded ? "カードを重ねる" : "カードを広げる（\(cards.count)件）") {
                    withAnimation(motion) { expanded.toggle() }
                }.font(.subheadline).accessibilityIdentifier("expandDeck")
                if expanded && cards.count > 4 { Button("残り\(cards.count - 4)件を見る") { showingRecords = true } }
            }
        }
    }
    private func cardView(_ card: DeckCard, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Button { withAnimation(motion) { expanded.toggle() } } label: {
                VStack(alignment: .leading, spacing: 14) {
                    Text(card.state == .active ? "今" : "次").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(card.category).font(.largeTitle.bold()).foregroundStyle(.tint)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(index == 0 ? "currentTaskCategory" : "deckCategory")
                    Text(card.title).font(.title3).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(index == 0 && card.state == .active ? "currentTaskTitle" : "deckTaskTitle")
                    Text(card.time).font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier(index == 0 ? "todayFocus" : "deckCard-\(card.id)")
            if card.state == .active {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { actions(card) }
                    VStack(spacing: 12) { actions(card) }
                }
            } else if let occurrence = store.occurrences.first(where: { $0.id == card.id }),
                      let task = store.tasks.first(where: { $0.id == occurrence.taskID }) {
                NavigationLink("予定を確認") { OccurrenceDetailView(task: task, occurrence: occurrence) }
                    .accessibilityIdentifier("deckDetails-\(card.id)")
            }
        }.padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.accentColor.opacity(index == 0 ? 0.45 : 0.2)))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
            .allowsHitTesting(index == 0 || expanded)
    }
    @ViewBuilder private func actions(_ card: DeckCard) -> some View {
        Button("スキップ") { skipping = store.occurrences.first { $0.id == card.id } }
            .buttonStyle(.bordered).controlSize(.large).accessibilityIdentifier("skipCurrentTask")
        Button("完了") { recording = store.occurrences.first { $0.id == card.id } }
            .buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("completeCurrentTask")
    }
    private var recordsSheet: some View {
        NavigationStack {
            List {
                Section("予定") { ForEach(presentation.upcoming) { entry in entryRow(entry) } }
                Section("時間を過ぎた未確定") { ForEach(presentation.unresolved) { entry in entryRow(entry) } }
                Section("完了・終了済み") { ForEach(presentation.history) { entry in entryRow(entry) } }
                if let date = ReviewPolicy.latestDay(records: store.occurrences.map(\.record), reviewedKeys: store.reviewedKeys, now: now) {
                    Button("\(date.formatted(date: .abbreviated, time: .omitted))を振り返る（暦日）") { reviewDay = ReviewDay(date: date) }.accessibilityIdentifier("reviewCTA")
                }
            }.navigationTitle("予定と履歴")
                .toolbar { Button("閉じる") { showingRecords = false } }
                .sheet(item: $reviewDay) { ReviewView(day: $0.date) }
        }
    }
    @ViewBuilder private func entryRow(_ entry: Timeline.Entry) -> some View {
        switch entry {
        case .task(let record):
            if let task = store.tasks.first(where: { $0.id == record.taskID }), let occurrence = store.occurrences.first(where: { $0.id == record.id }) {
                NavigationLink { OccurrenceDetailView(task: task, occurrence: occurrence) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(CategoryAnalyticsEngine.name(task.category)).font(.headline)
                        Text(task.title).font(.subheadline)
                        OccurrenceSummary(occurrence: occurrence)
                    }
                }
            }
        case .event(let event):
            VStack(alignment: .leading) { Text(event.title); Text(event.isAllDay ? "終日" : event.start.formatted(date: .omitted, time: .shortened)).font(.caption) }
        }
    }
    private func moveDay(_ offset: Int) {
        direction = offset
        changeDay((store.lifeDay ?? .initial).shiftedDay(day, by: offset))
    }
    private func changeDay(_ next: Date) {
        withAnimation(motion) {
            dragX = 0; expanded = false; day = next
            followingToday = isToday
            store.displayDay = next
            store.refreshCalendar()
            cards = makeCards()
        }
    }
    private func makeCards() -> [DeckCard] {
        presentation.upcoming.compactMap { entry in
            guard case .task(let record) = entry, let task = store.tasks.first(where: { $0.id == record.taskID }) else { return nil }
            return DeckCard(id: record.id, category: CategoryAnalyticsEngine.name(task.category), title: task.title,
                            time: "\(record.start?.formatted(date: .omitted, time: .shortened) ?? "") – \(record.end?.formatted(date: .omitted, time: .shortened) ?? "")",
                            state: OccurrenceDisplayState.resolve(record, now: now))
        }
    }
    private func refreshWhenVisible() { if recording == nil && skipping == nil && !showingRecords { refreshCards() } }
    private func refreshCards(animated: Bool = true) {
        withAnimation(animated ? motion : nil) { cards = makeCards() }
    }
}

private struct DeckCard: Identifiable, Equatable {
    let id: UUID
    let category: String
    let title: String
    let time: String
    let state: OccurrenceDisplayState
}

/// Measures full content at the proposed width, so Japanese and Dynamic Type can grow vertically.
struct CardStackLayout: Layout {
    var expanded: Bool
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) }
        let width = proposal.width ?? sizes.map(\.width).max() ?? 0
        let gaps = CGFloat(max(0, sizes.count - 1))
        let height: CGFloat
        if expanded { height = sizes.reduce(CGFloat.zero) { $0 + $1.height } + gaps * 16 }
        else { height = (sizes.map(\.height).max() ?? 0) + gaps * 22 }
        return CGSize(width: width, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        let maximum = subviews.map { $0.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height }.max() ?? 0
        for (index, view) in subviews.enumerated() {
            let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            let top = expanded ? y : bounds.minY + maximum - size.height + CGFloat(index) * 22
            view.place(at: CGPoint(x: bounds.minX, y: top), proposal: ProposedViewSize(width: bounds.width, height: size.height))
            y += expanded ? size.height + 16 : 22
        }
    }
}
struct SkipTaskSheet: View {
    @Environment(PocketStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let task: Task
    let occurrence: TaskOccurrence
    @State private var rescheduling = false
    @State private var confirmingDelete = false
    var body: some View {
        NavigationStack {
            List {
                Text(CategoryAnalyticsEngine.name(task.category)).font(.headline)
                Text(task.title).font(.subheadline).foregroundStyle(.secondary)
                Button("日時を変更") { rescheduling = true }
                Button("Taskを削除", role: .destructive) { confirmingDelete = true }
                Button("キャンセル", role: .cancel) { dismiss() }
            }
            .navigationTitle("スキップ")
            .sheet(isPresented: $rescheduling, onDismiss: {
                if occurrence.planResult != .pending { dismiss() }
            }) { ScheduleEditor(task: task, occurrence: occurrence) }
            .alert("Taskを削除しますか？", isPresented: $confirmingDelete) {
                Button("削除する", role: .destructive) { if store.archive(task) { dismiss() } }
                Button("キャンセル", role: .cancel) { }
            } message: {
                Text("Taskをアーカイブし、未来の未確定の予定を削除します。開始済みの予定と実行履歴は保持されます。")
            }
        }
    }
}
