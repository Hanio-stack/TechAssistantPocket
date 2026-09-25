import SwiftUI

struct EventEditor: View {
    @Environment(PocketStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var title = ""
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(3600)
    @State private var calendarID: String?
    @State private var reminder: Int?
    @State private var error: String?
    @State private var connecting = false
    var body: some View {
        NavigationStack {
            Form {
                Section("通常の予定") {
                    TextField("タイトル", text: $title).accessibilityIdentifier("eventTitle")
                    DateTimeFields(title: "開始", date: $start, identifier: "eventStart")
                    DateTimeFields(title: "終了", date: $end, identifier: "eventEnd")
                    ReminderPicker(minutes: $reminder)
                }
                Section {
                    if store.calendarAccess == .full {
                        if store.calendarChoices.isEmpty {
                            Text("書き込み可能なカレンダーがありません。iPhone の設定でカレンダーアカウントを追加してください。")
                                .foregroundStyle(.secondary)
                        }
                        Picker("保存先", selection: $calendarID) {
                            Text("選択してください").tag(nil as String?)
                            ForEach(store.calendarChoices) { choice in Text("\(choice.title)（\(choice.source)）").tag(Optional(choice.id)) }
                        }
                    } else {
                        Button("カレンダーへのアクセスを許可") {
                            connecting = true
                            _Concurrency.Task { await store.connectCalendar(); connecting = false }
                        }.disabled(connecting)
                        if store.calendarAccess == .denied {
                            Text("カレンダーへのアクセスは許可されていません。通常の予定を保存するには、iPhone の設定で許可してください。")
                                .foregroundStyle(.secondary).accessibilityIdentifier("calendarDeniedHelp")
                            Button("iPhone の設定を開く") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                        }
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                    if end <= start { Text("終了は開始より後にしてください。").foregroundStyle(.red) }
                } footer: {
                    Text("通常の予定はカレンダーに保存します。完了や成功率の対象にはなりません。通知はカレンダーの通知を使います。")
                }
            }
            .navigationTitle("予定を追加")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do {
                            try store.calendarService.createEvent(title: title.trimmingCharacters(in: .whitespacesAndNewlines), start: start, end: end,
                                                                  calendarID: calendarID, reminderMinutes: reminder)
                            store.refreshCalendar()
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || end <= start || calendarID == nil || store.calendarAccess != .full)
                        .accessibilityIdentifier("saveEvent")
                }
            }
            .onAppear { store.refreshCalendar(); calendarID = store.selectedCalendarID }
        }
    }
}
