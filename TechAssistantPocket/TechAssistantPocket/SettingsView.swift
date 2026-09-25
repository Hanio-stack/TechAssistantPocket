import SwiftUI

struct SettingsView: View {
    @Environment(PocketStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var editingLifeHours = false
    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("生活時間") {
                    Button("起床・就寝を変更") { editingLifeHours = true }
                }
                Section {
                    if store.calendarAccess != .full {
                        Button("カレンダーへのアクセスを許可") { _Concurrency.Task { await store.connectCalendar() } }
                        if store.calendarAccess == .denied {
                            Button("iPhone の設定を開く") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                        }
                    } else {
                        Picker("既定の保存先", selection: $store.selectedCalendarID) {
                            Text("選択してください").tag(nil as String?)
                            ForEach(store.calendarChoices) { choice in Text("\(choice.title)（\(choice.source)）").tag(Optional(choice.id)) }
                        }
                        .onChange(of: store.selectedCalendarID) { _, _ in store.refreshCalendar() }
                        Button("カレンダー反映を再試行") { store.retryCalendar() }
                    }
                    if let message = store.integrationMessage { Text(message).foregroundStyle(.secondary) }
                } header: { Text("カレンダー") } footer: {
                    Text("Google カレンダーがない場合は、iPhone の設定から Google アカウントのカレンダーを追加してください。Task は連携なしでも使えます。")
                }
                Section("Task の通知") {
                    ReminderPicker(minutes: $store.defaultReminder)
                    Text("既存Taskに予定を追加するときの初期値です。新規Taskの初期値は開始時刻です。既存予定の通知は変更しません。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(store.notificationsAuthorized ? "通知は許可されています" : "通知は許可されていません")
                    Button("通知を許可・再予約") { _Concurrency.Task { await store.connectNotifications() } }
                    Button("iPhone の通知設定を開く") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                    if let message = store.notificationMessage { Text(message).foregroundStyle(.secondary) }
                }
            }
            .sheet(isPresented: $editingLifeHours) { LifeHoursView() }
            .navigationTitle("設定")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } }
            .onAppear { store.refreshCalendar() }
            .task { store.notificationsAuthorized = await store.notifications.isAuthorized() }
        }
    }
}
