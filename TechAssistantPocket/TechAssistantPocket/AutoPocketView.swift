import SwiftUI
import Combine

struct AutoPocketView: View {
    @Environment(AutoSchedulerStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var adding = false
    @State private var settings = false
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") { NavigationStack { AutoHomeView().toolbar { controls } } }
            Tab("Tasks", systemImage: "checklist") { NavigationStack { BacklogTasksView().toolbar { controls } } }
            Tab("Insights", systemImage: "chart.bar") { NavigationStack { ActionInsightsView().toolbar { controls } } }
        }
        .tint(Color(red: 0.46, green: 0.41, blue: 0.90))
        .sheet(isPresented: $adding) { BacklogTaskEditor() }
        .sheet(isPresented: $settings) { AutoSettingsView() }
        .fullScreenCover(isPresented: Binding(get: { store.settings == nil }, set: { _ in })) { AutoSettingsView(setup: true) }
        .onAppear { store.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { store.refresh() } }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in store.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: CalendarServiceChange.notification)) { _ in store.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in store.refresh() }
        .alert("確認してください", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
    @ToolbarContentBuilder private var controls: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("設定", systemImage: "gearshape") { settings = true }.accessibilityIdentifier("autoSettings")
            Button("Taskを追加", systemImage: "plus") { adding = true }.accessibilityIdentifier("autoAdd")
        }
    }
}

struct AutoHomeView: View {
    @Environment(AutoSchedulerStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--ui-auto-reduce-motion") { return true }
        #endif
        return systemReduceMotion
    }
    @State private var drag: CGFloat = 0
    @State private var completedDirection = true
    private var animation: Animation { reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.86) }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    Text("いつやるかはPocketにおまかせ").font(.subheadline).foregroundStyle(.secondary)
                    ZStack {
                        if let proposal = store.current {
                            VStack(alignment: .leading, spacing: 24) {
                                Text(proposal.genre.isEmpty ? "未分類" : proposal.genre)
                                    .font(.largeTitle.bold()).foregroundStyle(.tint)
                                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("proposalGenre")
                                Text(proposal.title).font(.title2).fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("proposalTitle")
                                Text(String(repeating: "★", count: proposal.priority)).font(.title2)
                                    .accessibilityLabel("優先度\(proposal.priority)").accessibilityIdentifier("proposalPriority")
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 16) { buttons(proposal) }
                                    VStack(alignment: .leading, spacing: 16) { buttons(proposal) }
                                }.padding(.top, 16)
                            }
                            .padding(28).frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: max(300, geometry.size.height * 0.53), alignment: .center)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 30))
                            .overlay(RoundedRectangle(cornerRadius: 30).stroke(Color.accentColor.opacity(0.4)))
                            .offset(x: reduceMotion ? drag * 0.12 : drag)
                            .contentShape(Rectangle())
                            .simultaneousGesture(DragGesture(minimumDistance: 16)
                                .onChanged { value in
                                    if abs(value.translation.width) > abs(value.translation.height) * 1.8 { drag = value.translation.width }
                                }
                                .onEnded { value in
                                    let direction = SwipeDecisionPolicy.direction(x: value.translation.width, y: value.translation.height,
                                        predictedX: value.predictedEndTranslation.width, width: geometry.size.width)
                                    if direction == 0 { withAnimation(animation) { drag = 0 } }
                                    else { act(direction < 0 ? .completed : .skipped, proposal: proposal) }
                                })
                            .accessibilityAction(named: "完了") { act(.completed, proposal: proposal) }
                            .accessibilityAction(named: "今はスキップ") { act(.skipped, proposal: proposal) }
                            .id(proposal.id)
                            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: completedDirection ? .trailing : .leading).combined(with: .opacity)))
                        } else {
                            ContentUnavailableView(store.emptyMessage, systemImage: "checkmark.circle",
                                description: Text("TaskはTasksに残ります。空き時間が変わると、Pocketがもう一度選びます。"))
                                .accessibilityIdentifier("schedulerEmpty")
                                .frame(minHeight: max(300, geometry.size.height * 0.53))
                        }
                    }
                    Text("左へスワイプで今はスキップ、右へスワイプで完了")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if let message = store.calendarMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--ui-auto-scenario") {
                        Button("検証時刻を15:20へ") { SchedulerUIFixtureClock.value = SchedulerUIFixtureClock.reference.addingTimeInterval(8400); store.defaults.set(SchedulerUIFixtureClock.value.timeIntervalSince1970, forKey: "fixtureNow"); store.refresh() }
                            .accessibilityIdentifier("advanceSchedulerClock")
                    }
                    #endif
                }.padding(24)
            }.clipped()
        }.navigationTitle("Home")
    }
    @ViewBuilder private func buttons(_ proposal: TaskProposal) -> some View {
        Button("スキップ") { act(.skipped, proposal: proposal) }.buttonStyle(.bordered).controlSize(.large).accessibilityIdentifier("autoSkip")
        Button("完了") { act(.completed, proposal: proposal) }.buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("autoComplete")
    }
    private func act(_ kind: TaskActionKind, proposal: TaskProposal) {
        completedDirection = kind == .completed
        withAnimation(animation) { _ = store.act(kind, proposalID: proposal.id); drag = 0 }
    }
}

struct BacklogTasksView: View {
    @Environment(AutoSchedulerStore.self) private var store
    @State private var editing: Task?
    var body: some View {
        List {
            Section("未完了 \(store.backlog.count)件") {
                ForEach(store.backlog) { task in
                    Button { editing = task } label: { row(task) }.buttonStyle(.plain).accessibilityIdentifier("backlog-\(task.title)")
                }
                if store.backlog.isEmpty { Text("追加したTaskはPocketが空き時間に選びます。") }
            }
            Section("完了済み \(store.completed.count)件") {
                ForEach(store.completed) { task in
                    NavigationLink { TaskActionHistoryView(taskID: task.id, title: task.title) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            row(task)
                            if let date = store.state(for: task)?.completedAt { Text("完了 \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                        }
                    }.accessibilityIdentifier("completed-\(task.title)")
                }
            }
            if !store.legacyOccurrences.isEmpty || store.tasks.contains(where: { store.state(for: $0) == nil }) {
                Section { NavigationLink("以前のTaskと履歴") { LegacyPocketHistoryView() } }
            }
        }.navigationTitle("Tasks").sheet(item: $editing) { BacklogTaskEditor(task: $0) }
    }
    private func row(_ task: Task) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.category ?? "未分類").font(.headline).fixedSize(horizontal: false, vertical: true)
            Text(task.title).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            if let state = store.state(for: task) { Text(String(repeating: "★", count: state.priority)).font(.subheadline).foregroundStyle(.tint) }
        }.padding(.vertical, 6)
    }
}

struct BacklogTaskEditor: View {
    @Environment(AutoSchedulerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var task: Task? = nil
    @State private var title = ""
    @State private var genre = ""
    @State private var priority = 2
    @State private var minutes = 30
    @State private var initialized = false
    @State private var confirmingDelete = false
    var body: some View {
        NavigationStack {
            Form {
                if let message = store.errorMessage { Text(message).foregroundStyle(.red) }
                Section("ジャンル") {
                    TextField("例：制作・読書", text: $genre, axis: .vertical).accessibilityIdentifier("genreInput")
                    if !store.categoryNames.isEmpty {
                        Menu("使ったジャンルから選ぶ") { ForEach(store.categoryNames, id: \.self) { name in Button(name) { genre = name } } }
                            .accessibilityIdentifier("genreHistory")
                    }
                }
                Section("内容") { TextField("何をやりますか？", text: $title, axis: .vertical).lineLimit(2...6).accessibilityIdentifier("backlogTitleInput") }
                Section("優先度") {
                    Picker("優先度", selection: $priority) { ForEach(1...3, id: \.self) { value in Text(String(repeating: "★", count: value)).tag(value).accessibilityLabel("優先度\(value)") } }
                        .pickerStyle(.segmented).accessibilityIdentifier("backlogPriority")
                }
                Section {
                    Stepper("想定作業時間 \(minutes)分", value: $minutes, in: 5...180, step: 5).accessibilityIdentifier("estimatedMinutes")
                } header: { Text("時間の見積もり") } footer: { Text("Pocketが空き時間に入るTaskを選ぶために使います。実作業時間は記録しません。") }
                if let task, store.state(for: task) != nil {
                    Section { Button("Taskを削除", role: .destructive) { confirmingDelete = true } }
                }
            }
            .navigationTitle(task == nil ? "Taskを追加" : "Taskを編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if store.saveTask(existing: task, title: title, genre: genre, priority: priority, minutes: minutes) { dismiss() }
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("saveBacklogTask")
                }
            }
            .onAppear {
                guard !initialized else { return }; initialized = true
                if let task {
                    title = task.title; genre = task.category ?? ""
                    if let state = store.state(for: task) { priority = state.priority; minutes = state.estimatedMinutes }
                    else if let seconds = task.estimatedDuration { minutes = min(180, max(5, Int((seconds / 300).rounded()) * 5)) }
                }
            }
            .confirmationDialog("Taskを削除しますか？", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("削除する", role: .destructive) { if let task, store.archive(task) { dismiss() } }
            } message: { Text("未完了リストから外します。保存済みの操作履歴は残ります。") }
        }
    }
}

struct TaskActionHistoryView: View {
    @Environment(AutoSchedulerStore.self) private var store
    let taskID: UUID
    let title: String
    var body: some View {
        List { ForEach(store.actions.filter { $0.taskID == taskID }.reversed(), id: \.proposalID) { action in actionRow(action) } }
            .navigationTitle(title)
    }
}

private func actionRow(_ action: TaskActionRecord) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(action.genre.isEmpty ? "未分類" : action.genre).font(.headline)
        Text(action.title)
        Text(String(repeating: "★", count: action.priority)).foregroundStyle(.tint)
        Text(action.kind == .completed ? "完了" : "スキップ").font(.subheadline.bold())
        Text(action.occurredAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
        Text("提示 \(action.proposedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
    }.fixedSize(horizontal: false, vertical: true)
}

struct ActionInsightsView: View {
    @Environment(AutoSchedulerStore.self) private var store
    var body: some View {
        List {
            Section {
                Text("完了 \(store.actions.filter { $0.kind == .completed }.count)件").font(.title2.bold())
                Text("スキップ \(store.actions.filter { $0.kind == .skipped }.count)件").foregroundStyle(.secondary)
                Text("カード操作から自動で記録します。実作業時間や、予定どおりできた割合ではありません。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(ActionAnalyticsEngine.summaries(store.actions.compactMap(\.fact))) { summary in
                Section(summary.genre) {
                    Text("完了 \(summary.completed)件・スキップ \(summary.skipped)件")
                    ForEach(store.actions.filter { ($0.genre.isEmpty ? "未分類" : $0.genre) == summary.genre }.reversed(), id: \.proposalID) { action in
                        DisclosureGroup(action.title) { actionRow(action) }
                    }
                }
            }
            if store.actions.isEmpty { Text("Taskを完了・スキップすると、ここに記録されます。") }
        }.navigationTitle("Insights")
    }
}

struct LegacyPocketHistoryView: View {
    @Environment(AutoSchedulerStore.self) private var store
    @State private var adopting: Task?
    var body: some View {
        List {
            Text("以前の予定・実行・成否はそのまま保持しています。新しい操作履歴とは集計を分けています。")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(store.tasks.filter { task in store.state(for: task) == nil || store.legacyOccurrences.contains { $0.taskID == task.id } }) { task in
                Section {
                    Text(task.category ?? "未分類").font(.headline)
                    Text(task.title)
                    ForEach(store.legacyOccurrences.filter { $0.taskID == task.id }) { OccurrenceSummary(occurrence: $0) }
                    if task.archivedAt == nil && store.state(for: task) == nil {
                        Button("未完了Taskとして使う") { adopting = task }
                    }
                }
            }
        }.navigationTitle("以前の履歴").sheet(item: $adopting) { BacklogTaskEditor(task: $0) }
    }
}

struct AutoSettingsView: View {
    @Environment(AutoSchedulerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var setup = false
    @State private var wake = 480
    @State private var bed = 90
    @State private var weekdayStart = 1260
    @State private var weekdayEnd = 60
    @State private var weekendStart = 780
    @State private var weekendEnd = 1080
    @State private var initialized = false
    var body: some View {
        NavigationStack {
            Form {
                if let message = store.errorMessage { Text(message).foregroundStyle(.red) }
                Section {
                    Text("やることだけ登録すれば、Pocketが空き時間から今やる1つを選びます。")
                    if setup { Text("以前の履歴は保持します。旧予定の通知は停止し、Taskの日時を自分で決める操作は不要になります。") .font(.caption).foregroundStyle(.secondary) }
                }
                Section("生活時間") {
                    clock("起床", value: $wake, id: "workWake")
                    clock("就寝", value: $bed, id: "workBed")
                }
                Section("平日の作業可能時間（月〜金）") {
                    clock("開始", value: $weekdayStart, id: "weekdayStart")
                    clock("終了", value: $weekdayEnd, id: "weekdayEnd")
                }
                Section {
                    clock("開始", value: $weekendStart, id: "weekendStart")
                    clock("終了", value: $weekendEnd, id: "weekendEnd")
                } header: { Text("休日の作業可能時間（土・日）") } footer: { Text("21:00〜02:00のような日跨ぎも設定できます。作業可能時間がTask選出の範囲です。") }
                Section("カレンダー") {
                    if store.calendarService.access != .full {
                        Button("カレンダーを連携") { _Concurrency.Task { await store.connectCalendar() } }
                        Text("未連携の場合、外部予定は考慮されません。許可後はすべての対象カレンダーから空き時間を確認します。") .font(.caption)
                    } else {
                        Picker("Pocket予定の保存先", selection: Binding(get: { store.selectedCalendarID }, set: { store.changeCalendar($0) })) {
                            Text("選択してください").tag(nil as String?)
                            ForEach(store.calendarService.calendars()) { Text($0.title).tag(Optional($0.id)) }
                        }
                    }
                    Button("再読み込み・同期") { store.refresh() }
                    if let message = store.calendarMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(setup ? "Pocketをはじめる" : "設定")
            .toolbar {
                if !setup { ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let value = SchedulerSettings(wakeMinutes: wake, bedMinutes: bed, work: WorkWindowPolicy(
                            weekday: WorkClockRange(startMinutes: weekdayStart, endMinutes: weekdayEnd), weekend: WorkClockRange(startMinutes: weekendStart, endMinutes: weekendEnd)))
                        if store.saveSettings(value) { dismiss() }
                    }.accessibilityIdentifier("saveWorkSettings")
                }
            }
            .interactiveDismissDisabled(setup)
            .onAppear {
                guard !initialized else { return }; initialized = true
                let value = store.settings ?? SchedulerSettings.initial
                wake = store.settings?.wakeMinutes ?? (store.defaults.object(forKey: "lifeWakeMinutes") as? Int ?? value.wakeMinutes)
                bed = store.settings?.bedMinutes ?? (store.defaults.object(forKey: "lifeBedMinutes") as? Int ?? value.bedMinutes)
                weekdayStart = value.work.weekday.startMinutes; weekdayEnd = value.work.weekday.endMinutes
                weekendStart = value.work.weekend.startMinutes; weekendEnd = value.work.weekend.endMinutes
            }
        }
    }
    private func clock(_ title: String, value: Binding<Int>, id: String) -> some View {
        DisclosureGroup {
            CompactTimePicker(title: title, minutes: value, identifier: id)
        } label: {
            HStack { Text(title); Spacer(); Text(String(format: "%02d:%02d", value.wrappedValue / 60, value.wrappedValue % 60)).foregroundStyle(.secondary) }
        }.accessibilityIdentifier(id)
    }
}
