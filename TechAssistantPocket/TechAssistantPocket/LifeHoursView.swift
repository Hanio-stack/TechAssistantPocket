import SwiftUI

struct LifeHoursView: View {
    @Environment(PocketStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var wake = LifeDayPolicy.initial.wakeMinutes
    @State private var bed = LifeDayPolicy.initial.bedMinutes
    var setup = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ClockFields(title: "起床", minutes: $wake, identifier: "lifeWake")
                    ClockFields(title: "就寝", minutes: $bed, identifier: "lifeBed")
                    if wake == bed { Text("起床と就寝は異なる時刻を選んでください。").foregroundStyle(.red) }
                } header: { Text("生活時間") } footer: {
                    Text("Homeは起床から就寝までを1日として表示します。起床より早い就寝時刻は翌日の時刻です。就寝後は次の生活日を表示します。")
                }
            }
            .navigationTitle(setup ? "生活時間を設定" : "生活時間")
            .onAppear {
                wake = store.lifeDay?.wakeMinutes ?? LifeDayPolicy.initial.wakeMinutes
                bed = store.lifeDay?.bedMinutes ?? LifeDayPolicy.initial.bedMinutes
            }
            .toolbar {
                if !setup { ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { store.setLifeHours(wake: wake, bed: bed); dismiss() }
                        .disabled(wake == bed).accessibilityIdentifier("saveLifeHours")
                }
            }
        }.interactiveDismissDisabled(setup)
    }
}
