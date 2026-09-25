import SwiftUI

/// Discrete selections update the binding immediately; no text-field focus commit is required.
struct ClockFields: View {
    let title: String
    @Binding var minutes: Int
    var identifier: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline)
            HStack {
                Picker("時", selection: Binding(get: { minutes / 60 }, set: { minutes = $0 * 60 + minutes % 60 })) {
                    ForEach(0..<24) { Text("\($0)時").tag($0) }
                }.accessibilityIdentifier(identifier + "Hour")
                Picker("分", selection: Binding(get: { minutes % 60 }, set: { minutes = minutes / 60 * 60 + $0 })) {
                    ForEach(0..<60) { Text(String(format: "%02d分", $0)).tag($0) }
                }.accessibilityIdentifier(identifier + "Minute")
            }.pickerStyle(.menu)
        }
    }
}

struct DateTimeFields: View {
    let title: String
    @Binding var date: Date
    var identifier: String
    private var clock: Binding<Int> {
        Binding(get: {
            Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
        }, set: { minutes in
            if let changed = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: date) {
                date = changed
            }
        })
    }
    var body: some View {
        DatePicker(title + "日", selection: $date, displayedComponents: .date).accessibilityIdentifier(identifier)
        ClockFields(title: title + "時刻", minutes: clock, identifier: identifier)
    }
}
