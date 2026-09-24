import SwiftUI
import Combine

struct TodayView: View {
    @Environment(PocketStore.self) private var store
    @State private var day = Date()
    @State private var clockNow = Date()
    private struct TaskAction: Identifiable {
        let task: Task
        let occurrence: TaskOccurrence
        var id: UUID { occurrence.id }
    }
    @State private var taskAction: TaskAction?
    @State private var skipping: TaskOccurrence?
    private struct ReviewSelection: Identifiable { let day: Date; var id: Date { day } }
    @State private var reviewSelection: ReviewSelection?
    @Environment(\.scenePhase) private var scenePhase
    @State private var followingToday = true
    @State private var historyExpanded = false
    @State private var unresolvedExpanded = false
    @State private var needsFocus = true
    @State private var isVisible = false
    @State private var focusRequest = 0
    @State private var previousRecords: [OccurrenceRecord] = []

    private var now: Date {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--ui-today-focus") { return DebugFixtures.todayReferenceTime }
        #endif
        return clockNow
    }
    private var records: [OccurrenceRecord] { store.occurrences.map(\.record) }
    private var events: [CalendarEvent] {
        store.events.filter { event in !store.pendingMirrorDeletes.contains { $0.eventIdentifier == event.identifier } }
    }
    private var presentation: Timeline.Presentation {
        Timeline.presentation(on: day, now: now, records: records, events: events,
                              archivedTaskIDs: Set(store.tasks.filter { $0.archivedAt != nil }.map(\.id)))
    }
    private var dayIdentity: String { ReviewPolicy.dateKey(day) + TimeZone.current.identifier }

    var body: some View {
        let content = presentation
        ScrollViewReader { proxy in
            List {
                Section {
                    DatePicker("表示する日", selection: $day, displayedComponents: .date)
                    HStack {
                        Button("前の日", systemImage: "chevron.left") { moveDay(-1) }.accessibilityIdentifier("previousDay")
                        Spacer()
                        Button(Calendar.current.isDateInToday(day) ? "明日を見る" : "次の日", systemImage: "calendar") { moveDay(1) }
                            .accessibilityIdentifier("nextDay")
                    }.buttonStyle(.borderless)
                    if !Calendar.current.isDateInToday(day) { Button("今日に戻る") { day = Date() } }
                    Text(day.formatted(date: .complete, time: .omitted)).font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("homeDate")
                }.id("todayStart")
                if let message = store.integrationMessage {
                    Section { Text(message).font(.subheadline).foregroundStyle(.secondary) }
                }
                if let current = content.currentTask, case .task(let record) = current,
                   let task = store.tasks.first(where: { $0.id == record.taskID }),
                   let occurrence = store.occurrences.first(where: { $0.id == record.id }) {
                    Section("現在のタスク") {
                        CurrentTaskCard(task: task, occurrence: occurrence, now: now,
                                        skip: { skipping = occurrence },
                                        complete: { taskAction = TaskAction(task: task, occurrence: occurrence) })
                            .id(current.id)
                            .listRowBackground(Color.accentColor.opacity(0.08))
                    }
                }
                Section(content.currentTask == nil ? "次の予定・現在の予定" : "次の予定") {
                    if content.upcoming.isEmpty {
                        Text("この日のこれからの予定はありません").foregroundStyle(.secondary)
                    }
                    ForEach(content.upcoming.filter { $0.id != content.currentTask?.id }) { entry in
                        entryRow(entry, focusID: content.focus?.id).id(entry.id)
                    }
                }
                if !content.unresolved.isEmpty {
                    Section {
                        disclosureHeader("時間を過ぎた未確定 \(content.unresolved.count)件", expanded: $unresolvedExpanded, identifier: "todayUnresolved")
                        if unresolvedExpanded {
                            Text("結果はまだ確定していません。実行を記録するか、振り返りで確認できます。")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(content.unresolved) { entry in entryRow(entry) }
                        }
                    }
                }
                if !content.history.isEmpty {
                    Section {
                        disclosureHeader("完了・終了済み \(content.history.count)件", expanded: $historyExpanded, identifier: "todayHistory")
                        if historyExpanded {
                            ForEach(content.history) { entry in entryRow(entry) }
                        }
                    }
                }
                if let reviewDay = ReviewPolicy.latestDay(records: records, reviewedKeys: store.reviewedKeys, now: now) {
                    Button {
                        reviewSelection = ReviewSelection(day: reviewDay)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(Calendar.current.isDateInToday(reviewDay) ? "今日を振り返る" : (Calendar.current.isDateInYesterday(reviewDay) ? "昨日を振り返る" : "\(reviewDay.formatted(date: .abbreviated, time: .omitted))を振り返る"))
                                .font(.headline)
                            Text("実行した時刻から、次の予定を見つけましょう。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }.accessibilityIdentifier("reviewCTA")
                }

            }
            .background(HomeDaySwipe(enabled: isVisible, onSwipe: moveDay).allowsHitTesting(false))
            .onAppear {
                isVisible = true
                requestFocusAfterResolution(before: previousRecords, after: records)
                previousRecords = records
                if needsFocus { focusRequest += 1 }
            }
            .onDisappear { isVisible = false }
            .onChange(of: records) { old, new in
                requestFocusAfterResolution(before: old, after: new)
                previousRecords = new
            }
            .onChange(of: dayIdentity) { _, _ in
                historyExpanded = false
                unresolvedExpanded = false
                needsFocus = true
                focusRequest += 1
            }
            .task(id: focusRequest) {
                guard isVisible, needsFocus else { return }
                // Wait for the changed sections/navigation return to join the view hierarchy.
                await _Concurrency.Task.yield()
                guard !_Concurrency.Task.isCancelled else { return }
                if let focus = presentation.focus {
                    proxy.scrollTo(focus.id, anchor: .center)
                }
                needsFocus = false
            }
        }
        .navigationTitle("Today")
        .onChange(of: day) { _, day in
            followingToday = Calendar.current.isDateInToday(day)
            store.displayDay = day
            store.refreshCalendar()
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { date in
            clockNow = date
            if followingToday && !Calendar.current.isDate(day, inSameDayAs: date) { day = date }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { clockNow = Date(); if followingToday { day = clockNow } }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            clockNow = Date()
            if followingToday { day = clockNow }
            store.refreshCalendar()
        }
        .refreshable { clockNow = Date(); store.reload(); store.refreshCalendar() }
        .sheet(item: $reviewSelection) { selection in ReviewView(day: selection.day) }
        .sheet(item: $taskAction) { action in
            ExecutionEditor(task: action.task, occurrence: action.occurrence)
        }
        .sheet(item: $skipping) { occurrence in
            if let task = store.tasks.first(where: { $0.id == occurrence.taskID }) {
                SkipTaskSheet(task: task, occurrence: occurrence)
            }
        }
    }

    private func disclosureHeader(_ title: String, expanded: Binding<Bool>, identifier: String) -> some View {
        Button { expanded.wrappedValue.toggle() } label: {
            HStack {
                Text(title).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
            }.foregroundStyle(.primary)
        }
        .accessibilityIdentifier(identifier)
        .accessibilityValue(expanded.wrappedValue ? "展開中" : "折りたたみ")
    }

    private func moveDay(_ offset: Int) {
        if let next = Calendar.current.date(byAdding: .day, value: offset, to: day) { day = next }
    }

    private func requestFocusAfterResolution(before: [OccurrenceRecord], after: [OccurrenceRecord]) {
        let previousDayRecords = before.filter { record in
            record.start.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false
        }
        // The original slot may have expired while its detail was open. Resolution is
        // still an explicit reason to return to the next action, even if its ID is unchanged.
        guard Timeline.hasNewlyResolvedTask(before: previousDayRecords, after: after) else { return }
        needsFocus = true
        if isVisible { focusRequest += 1 }
    }

    @ViewBuilder private func entryRow(_ entry: Timeline.Entry, focusID: String? = nil) -> some View {
        let focused = entry.id == focusID
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
                            if focused { focusLabel(entry) }
                            Text(task.title).font(.headline)
                            Text(entry.start.formatted(date: .omitted, time: .shortened) + " – " + (record.end?.formatted(date: .omitted, time: .shortened) ?? ""))
                            Text(record.result?.label ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 6)
                }.accessibilityIdentifier(focused ? "todayFocus" : "todayRow-" + entry.id)
            }
        case .event(let event):
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar").foregroundStyle(.orange).font(.title3)
                VStack(alignment: .leading, spacing: 5) {
                    if focused { focusLabel(entry) }
                    Text(event.title).font(.headline)
                    Text(event.isAllDay ? "終日 · 予定" : "\(event.start.formatted(date: .omitted, time: .shortened)) · 予定")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let location = event.location, !location.isEmpty { Text(location).font(.caption) }
                }
            }.padding(.vertical, 6)
                .accessibilityIdentifier(focused ? "todayFocus" : "todayRow-" + entry.id)
        }
    }

    private func focusLabel(_ entry: Timeline.Entry) -> some View {
        Text(entry.isCurrent(at: now) ? "今" : "次")
            .font(.subheadline.bold()).foregroundStyle(.tint)
    }
}


private struct CurrentTaskCard: View {
    let task: Task
    let occurrence: TaskOccurrence
    let now: Date
    let skip: () -> Void
    let complete: () -> Void
    @Environment(\.dynamicTypeSize) private var textSize

    private var remaining: Int { max(0, Int(ceil((occurrence.scheduledEnd ?? now).timeIntervalSince(now) / 60))) }
    private var progress: Double {
        guard let start = occurrence.scheduledStart, let end = occurrence.scheduledEnd, end > start else { return 0 }
        return min(1, max(0, now.timeIntervalSince(start) / end.timeIntervalSince(start)))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if textSize.isAccessibilitySize {
                details
                Text("残り\(remaining)分").font(.headline).fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .center, spacing: 12) { details; Spacer(minLength: 0); remainingTime }
            }
            if textSize.isAccessibilitySize {
                VStack(spacing: 12) { skipButton; completeButton }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { skipButton; completeButton }
                    VStack(spacing: 12) { skipButton; completeButton }
                }
            }
        }
        .padding(.vertical, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("currentTaskCard")
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let category = task.category, !category.isEmpty { Text(category).font(.subheadline).foregroundStyle(.tint) }
            Text(task.title).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("currentTaskTitle")
            if let start = occurrence.scheduledStart, let end = occurrence.scheduledEnd {
                Text(start.formatted(date: .omitted, time: .shortened) + " – " + end.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
    private var remainingTime: some View {
        ZStack {
            Circle().stroke(Color.accentColor.opacity(0.15), lineWidth: 7)
            Circle().trim(from: 0, to: progress).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) { Text("残り").font(.caption); Text("\(remaining)分").font(.headline) }
        }.frame(width: 86, height: 86)
            .accessibilityElement(children: .ignore).accessibilityLabel("残り\(remaining)分")
    }
    private func actionLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) { Image(systemName: symbol); Text(title) }
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
    }
    private var skipButton: some View {
        Button(action: skip) { actionLabel("スキップ", symbol: "xmark")
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16)) }
            .buttonStyle(.plain).foregroundStyle(Color.accentColor).accessibilityIdentifier("skipCurrentTask")
    }
    private var completeButton: some View {
        Button(action: complete) { actionLabel("完了", symbol: "checkmark")
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16)) }
            .buttonStyle(.plain).foregroundStyle(.white).accessibilityIdentifier("completeCurrentTask")
    }
}


private struct SkipTaskSheet: View {
    @Environment(PocketStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let task: Task
    let occurrence: TaskOccurrence
    @State private var rescheduling = false
    @State private var confirmingDelete = false
    var body: some View {
        NavigationStack {
            List {
                Text(task.title).font(.headline)
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


/// Observe horizontal movement without putting a gesture hit surface above the tab bar.
private struct HomeDaySwipe: UIViewRepresentable {
    let enabled: Bool
    let onSwipe: (Int) -> Void
    func makeUIView(context: Context) -> SwipeObserver { SwipeObserver() }
    func updateUIView(_ view: SwipeObserver, context: Context) {
        view.enabled = enabled
        view.onSwipe = onSwipe
        view.attachToList()
    }
    static func dismantleUIView(_ view: SwipeObserver, coordinator: ()) { view.detach() }

    final class SwipeObserver: UIView, UIGestureRecognizerDelegate {
        var enabled = false
        var onSwipe: (Int) -> Void = { _ in }
        private weak var attachedList: UIScrollView?
        private lazy var pan: UIPanGestureRecognizer = {
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(moved(_:)))
            recognizer.delegate = self
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.maximumNumberOfTouches = 1
            return recognizer
        }()
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { detach() }
            else { attachToList() }
        }
        func attachToList() {
            // SwiftUI installs the List beside its background. Attach only to that
            // scroll view, never to the window that also receives tab-bar touches.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil, self.attachedList == nil else { return }
                var ancestor = self.superview
                while let view = ancestor, !(view is UIWindow) {
                    if let list = self.scrollView(in: view) {
                        list.addGestureRecognizer(self.pan)
                        self.attachedList = list
                        return
                    }
                    ancestor = view.superview
                }
            }
        }
        private func scrollView(in view: UIView) -> UIScrollView? {
            if let list = view as? UIScrollView { return list }
            for child in view.subviews {
                if let list = scrollView(in: child) { return list }
            }
            return nil
        }
        func detach() { attachedList?.removeGestureRecognizer(pan); attachedList = nil }
        @objc private func moved(_ recognizer: UIPanGestureRecognizer) {
            guard enabled, recognizer.state == .ended else { return }
            let delta = recognizer.translation(in: self)
            let offset = Timeline.dayOffset(horizontal: delta.x, vertical: delta.y)
            if offset != 0 { onSwipe(offset) }
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard enabled, let window, window.rootViewController?.presentedViewController == nil,
                  bounds.contains(touch.location(in: self)) else { return false }
            var view = touch.view
            while let current = view {
                if current is UIControl || current is UITabBar { return false }
                view = current.superview
            }
            return true
        }
        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            let velocity = pan.velocity(in: self)
            return enabled && abs(velocity.x) > abs(velocity.y) * 1.8
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }
}
