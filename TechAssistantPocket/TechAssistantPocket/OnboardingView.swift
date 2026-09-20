import SwiftUI

struct OnboardingView: View {
    @Environment(PocketStore.self) private var store
    @AppStorage("onboardingCompleted") private var completed = false
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var working = false
    var body: some View {
        @Bindable var store = store
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: step == 0 ? "calendar.badge.checkmark" : (step == 1 ? "calendar" : "bell.badge"))
                        .font(.system(size: 48)).foregroundStyle(.tint).accessibilityHidden(true)
                    Text(step == 0 ? "予定の立て方が、少しずつ上手くなる。" : (step == 1 ? "カレンダーをつなぐ" : "Task の時間をお知らせ"))
                        .font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                    if step == 0 {
                        Text("予定を立て、実行を記録し、一日を振り返る。端末にたまった記録から、あなたが実行しやすい時間を見つけます。")
                        Text("予定を勝手に変更しません。提案を使うかどうかは、あなたが決められます。")
                            .foregroundStyle(.secondary)
                        Button("はじめる") { step = 1 }.buttonStyle(.borderedProminent)
                    } else if step == 1 {
                        Text("今日の予定を読み取り、Task の予定を選んだカレンダーに反映します。連携しなくても Task は使えます。")
                        if store.calendarAccess == .full {
                            Picker("保存先", selection: $store.selectedCalendarID) {
                                Text("選択してください").tag(nil as String?)
                                ForEach(store.calendarChoices) { choice in Text("\(choice.title)（\(choice.source)）").tag(Optional(choice.id)) }
                            }.pickerStyle(.menu)
                            Text("Google カレンダーが見つからない場合は、iPhone の設定に Google アカウントのカレンダーを追加してください。")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button("次へ") { step = 2 }.buttonStyle(.borderedProminent).disabled(store.selectedCalendarID == nil)
                        } else {
                            Button("カレンダーを連携") {
                                working = true
                                _Concurrency.Task { await store.connectCalendar(); working = false }
                            }.buttonStyle(.borderedProminent).disabled(working)
                            if store.calendarAccess == .denied { Text("アクセスは許可されていません。あとから設定で変更できます。").font(.subheadline) }
                        }
                        Button("今は連携せずに続ける") { step = 2 }
                    } else {
                        Text("通知は予定ごとに選べます。通知を許可しなくても、実行の記録や振り返りは使えます。")
                        Button("通知を許可して Today へ") {
                            working = true
                            _Concurrency.Task { await store.connectNotifications(); finish() }
                        }.buttonStyle(.borderedProminent).disabled(working)
                        Button("通知なしで始める") { finish() }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(28)
            }
            .navigationTitle("Pocket")
            .navigationBarTitleDisplayMode(.inline)
        }.interactiveDismissDisabled()
    }
    private func finish() { completed = true; store.refreshCalendar(); dismiss() }
}
