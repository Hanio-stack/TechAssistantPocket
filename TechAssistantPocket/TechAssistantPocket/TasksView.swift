import SwiftUI

struct TasksView: View {
    @Environment(PocketStore.self) private var store

    var body: some View {
        List {
            if store.activeTasks.isEmpty {
                ContentUnavailableView("やりたいことを追加", systemImage: "checklist",
                                       description: Text("タイトルだけでも保存できます。＋から Task を追加しましょう。"))
            }
            Section("未スケジュール") {
                ForEach(store.unscheduledTasks) { task in taskLink(task) }
            }
            Section("予定のある Task") {
                ForEach(store.activeTasks.filter { task in !store.unscheduledTasks.contains { $0.id == task.id } }) { task in
                    taskLink(task)
                }
            }
        }
        .navigationTitle("Tasks")
    }

    private func taskLink(_ task: Task) -> some View {
        NavigationLink {
            TaskDetailView(task: task)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(task.title).font(.headline)
                if let next = store.history(for: task).filter({ $0.planResult == .pending })
                    .min(by: { $0.scheduledStart! < $1.scheduledStart! }), let start = next.scheduledStart {
                    Text(start.formatted(date: .abbreviated, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                }
            }.padding(.vertical, 4)
        }
    }
}

struct TaskDetailView: View {
    @Environment(PocketStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let task: Task
    @State private var editing = false
    @State private var scheduling = false
    @State private var recording = false
    @State private var archiveConfirmation = false

    var body: some View {
        List {
            Section {
                Button("予定を追加", systemImage: "calendar.badge.plus") { scheduling = true }
                Button("予定なしの実行を記録", systemImage: "checkmark.circle") { recording = true }
            }
            Section("予定と実行の履歴") {
                if store.history(for: task).isEmpty { Text("まだ記録がありません").foregroundStyle(.secondary) }
                ForEach(store.history(for: task)) { occurrence in
                    NavigationLink {
                        OccurrenceDetailView(task: task, occurrence: occurrence)
                    } label: { OccurrenceSummary(occurrence: occurrence) }
                }
            }
            Section {
                Button("Task を削除", role: .destructive) { archiveConfirmation = true }
            } footer: { Text("削除しても過去の実行履歴は残ります。未来の未確定の予定だけを取り除きます。") }
        }
        .navigationTitle(task.title)
        .toolbar { Button("編集") { editing = true } }
        .sheet(isPresented: $editing) { TaskEditor(task: task) }
        .sheet(isPresented: $scheduling) { ScheduleEditor(task: task) }
        .sheet(isPresented: $recording) { ExecutionEditor(task: task, occurrence: nil) }
        .confirmationDialog("Task を削除しますか？", isPresented: $archiveConfirmation, titleVisibility: .visible) {
            Button("削除する", role: .destructive) {
                if store.archive(task) { dismiss() }
            }
        }
    }
}

struct TaskEditor: View {
    @Environment(PocketStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var task: Task?
    @State private var title = ""
    @State private var category = ""
    @State private var enteringCategory = false
    @State private var hasDuration = false
    @State private var minutes = 30
    @State private var scheduled = false
    @State private var start = Date()
    @State private var reminder: Int? = nil
    @State private var selectedOccurrenceID: UUID?
    @State private var initialized = false
    private var pendingPlans: [TaskOccurrence] {
        guard let task else { return [] }
        return store.history(for: task).filter { $0.planResult == .pending }
            .sorted { ($0.scheduledStart ?? .distantFuture) < ($1.scheduledStart ?? .distantFuture) }
    }
    private var selectedPlan: TaskOccurrence? { pendingPlans.first { $0.id == selectedOccurrenceID } }
    private var mayRemoveDate: Bool { selectedPlan.map { ($0.scheduledStart ?? .distantPast) > store.currentTime } ?? true }

    var body: some View {
        NavigationStack {
            Form {
                if let message = store.errorMessage { Text(message).foregroundStyle(.red) }
                Section("やること") {
                    TextField("タイトル", text: $title).accessibilityIdentifier("taskTitle")
                    Menu {
                        Button("カテゴリなし") { category = "" }
                        ForEach(store.categoryNames, id: \.self) { name in
                            Button(name) { category = name }
                        }
                        Button("新しいカテゴリを入力") { category = ""; enteringCategory = true }
                    } label: {
                        LabeledContent("カテゴリ", value: category.isEmpty ? "なし" : category)
                    }.accessibilityIdentifier("categoryMenu")
                    if enteringCategory {
                        TextField("新しいカテゴリ", text: $category).accessibilityIdentifier("newCategory")
                    }
                }
                Section {
                    if pendingPlans.count > 1 {
                        Picker("変更する予定", selection: $selectedOccurrenceID) {
                            ForEach(pendingPlans) { plan in
                                Text(plan.scheduledStart!.formatted(date: .abbreviated, time: .shortened)).tag(Optional(plan.id))
                            }
                        }
                    }
                    Toggle("日時を設定", isOn: $scheduled).disabled(!mayRemoveDate)
                    if !mayRemoveDate { Text("開始済みの予定は履歴を残して日時を変更できます。日時なしには戻せません。")
                        .font(.caption).foregroundStyle(.secondary) }
                    if scheduled { ScheduleFields(start: $start, reminder: $reminder) }
                    Toggle("所要時間を設定", isOn: $hasDuration)
                    if hasDuration || scheduled { DurationPicker(minutes: $minutes) }
                } footer: { Text("日時ありの予定は、所要時間を指定しなければ30分です。") }
            }
            .navigationTitle(task == nil ? "Task を追加" : "Task を編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("saveTask")
                }
            }
            .onAppear {
                guard !initialized else { return }
                initialized = true
                reminder = store.defaultReminder
                if let task {
                    title = task.title; category = task.category ?? ""
                    hasDuration = task.estimatedDuration != nil
                    minutes = Int((task.estimatedDuration ?? 1800) / 60)
                    selectedOccurrenceID = pendingPlans.first?.id
                    loadPlan()
                }
            }
            .onChange(of: selectedOccurrenceID) { _, _ in loadPlan() }
        }
    }

    private func loadPlan() {
        guard let plan = selectedPlan, let date = plan.scheduledStart, let end = plan.scheduledEnd else { return }
        scheduled = true
        start = date
        minutes = Int(end.timeIntervalSince(date) / 60)
        reminder = plan.notificationMinutesBefore
    }

    private func save() {
        if store.saveTask(task, title: title, category: category,
                          estimatedDuration: hasDuration ? Double(minutes * 60) : nil,
                          editing: selectedPlan, scheduledStart: scheduled ? start : nil,
                          duration: Double(minutes * 60), reminder: reminder, now: store.currentTime) { dismiss() }
    }
}

struct ScheduleFields: View {
    @Binding var start: Date
    @Binding var reminder: Int?
    var minimumDate: Date? = nil
    var body: some View {
        Group {
            if let minimumDate { DatePicker("開始", selection: $start, in: minimumDate...) }
            else { DatePicker("開始", selection: $start) }
        }.accessibilityIdentifier("scheduleStart")
        ReminderPicker(minutes: $reminder)
    }
}

struct DurationPicker: View {
    @Binding var minutes: Int
    var body: some View { Stepper("所要時間 \(minutes)分", value: $minutes, in: 5...720, step: 5) }
}

struct ScheduleEditor: View {
    @Environment(PocketStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let task: Task
    var occurrence: TaskOccurrence? = nil
    @State private var start = Date()
    @State private var reminder: Int? = nil
    @State private var minutes = 30
    var body: some View {
        NavigationStack {
            Form {
                if let message = store.errorMessage { Text(message).foregroundStyle(.red) }
                Text(task.title).font(.headline)
                ScheduleFields(start: $start, reminder: $reminder, minimumDate: store.currentTime)
                DurationPicker(minutes: $minutes)
                if let occurrence, (occurrence.scheduledStart ?? .distantFuture) <= store.currentTime {
                    Text("元の予定枠は未達成の履歴として残り、同じTaskに新しい予定枠を設定します。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(occurrence == nil ? "予定を追加" : "予定を変更")
            .onAppear {
                reminder = store.defaultReminder
                start = occurrence?.scheduledStart ?? store.currentTime.addingTimeInterval(3600)
                if start <= store.currentTime { start = store.currentTime.addingTimeInterval(3600) }
                if let occurrence {
                    minutes = Int((occurrence.scheduledEnd!.timeIntervalSince(occurrence.scheduledStart!)) / 60)
                    reminder = occurrence.notificationMinutesBefore
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var next: TaskOccurrence?
                        if store.perform({
                            if let occurrence {
                                next = try store.repository.reschedule(occurrence, to: start, duration: Double(minutes * 60), now: store.currentTime)
                            } else {
                                let added = TaskOccurrence(taskID: task.id, scheduledStart: start, duration: Double(minutes * 60))
                                try store.repository.insert(added)
                                next = added
                            }
                            next?.notificationMinutesBefore = reminder
                        }), let next {
                            if let occurrence { store.notifications.remove(occurrenceID: occurrence.id) }
                            store.syncMirror(next, title: task.title)
                            _Concurrency.Task { await store.updateNotification(next, title: task.title) }
                            store.refreshCalendar()
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

struct ExecutionEditor: View {
    @Environment(PocketStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let task: Task
    let occurrence: TaskOccurrence?
    var laterOnly = false
    @State private var actual = Date()
    var body: some View {
        NavigationStack {
            Form {
                if let message = store.errorMessage { Text(message).foregroundStyle(.red) }
                Text(task.title).font(.headline)
                Section {
                    DatePicker("実際に開始した時刻", selection: $actual, in: ...store.currentTime)
                    if laterOnly, let end = occurrence?.scheduledEnd, actual <= end {
                        Text("「後でやった」は予定の終了より後の開始時刻を入力してください。予定枠内なら「予定どおりできた」を選べます。")
                            .font(.caption).foregroundStyle(.red)
                    }
                } footer: { Text("完了した時刻ではなく、実際に始めたおおよその時刻を記録します。") }
            }
            .navigationTitle("実行を記録")
            .onAppear { actual = store.currentTime }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("記録") {
                        if store.perform({
                            if let occurrence { try occurrence.recordExecution(startedAt: actual) }
                            else { try store.repository.insert(TaskOccurrence(taskID: task.id, actualExecutedAt: actual)) }
                        }) {
                            if let occurrence { store.notifications.remove(occurrenceID: occurrence.id) }
                            dismiss()
                        }
                    }.disabled(laterOnly && actual <= (occurrence?.scheduledEnd ?? .distantPast))
                }
            }
        }
    }
}

struct OccurrenceDetailView: View {
    @Environment(PocketStore.self) private var store
    let task: Task
    let occurrence: TaskOccurrence
    @State private var recording = false
    @State private var rescheduling = false
    var body: some View {
        List {
            OccurrenceSummary(occurrence: occurrence)
            if occurrence.planResult == .pending {
                Button("実行を記録") { recording = true }
                Button("できなかった") { if store.perform({ try occurrence.markMissed() }) { store.notifications.remove(occurrenceID: occurrence.id) } }
                Button("キャンセルした") { if store.perform({ try occurrence.cancel() }) { store.notifications.remove(occurrenceID: occurrence.id) } }
            }
            if task.archivedAt == nil && (occurrence.planResult == .pending || (occurrence.planResult == .missed && occurrence.actualExecutedAt == nil)) {
                Button("予定を変更") { rescheduling = true }
            }
        }
        .navigationTitle(task.title)
        .sheet(isPresented: $rescheduling) { ScheduleEditor(task: task, occurrence: occurrence) }
        .sheet(isPresented: $recording) { ExecutionEditor(task: task, occurrence: occurrence) }
    }
}

struct OccurrenceSummary: View {
    let occurrence: TaskOccurrence
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let start = occurrence.scheduledStart, let end = occurrence.scheduledEnd {
                Text(start.formatted(date: .abbreviated, time: .shortened))
                Text("終了 \(end.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
            } else { Text("予定なしの実行") }
            Text(occurrence.planResult?.label ?? "実行済み").font(.subheadline).foregroundStyle(.secondary)
            if let actual = occurrence.actualExecutedAt {
                Text("実際の開始 \(actual.formatted(date: .abbreviated, time: .shortened))").font(.caption)
            }
        }.padding(.vertical, 4)
    }
}

extension PlanResult {
    var label: String {
        switch self {
        case .pending: "未確定"
        case .success: "予定どおりできた"
        case .missed: "予定枠ではできなかった"
        case .cancelled: "キャンセル"
        }
    }
}

struct ReminderPicker: View {
    @Binding var minutes: Int?
    var body: some View {
        Picker("通知", selection: $minutes) {
            Text("なし").tag(nil as Int?)
            Text("開始時刻").tag(Optional(0))
            Text("5分前").tag(Optional(5))
            Text("15分前").tag(Optional(15))
            Text("30分前").tag(Optional(30))
        }
    }
}
