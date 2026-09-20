import SwiftUI

struct ContentView: View {
    @Environment(PocketStore.self) private var store
    @State private var addingTask = false
    @State private var settings = false
    @State private var addingEvent = false
    @State private var onboarding = false
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        @Bindable var store = store
        TabView {
            Tab("Today", systemImage: "house") { NavigationStack { TodayView().toolbar { Button("設定", systemImage: "gearshape") { settings = true }; addButton } } }
            Tab("Tasks", systemImage: "checklist") { NavigationStack { TasksView().toolbar { Button("設定", systemImage: "gearshape") { settings = true }; addButton } } }
            Tab("Insights", systemImage: "chart.bar") { NavigationStack { InsightsView().toolbar { Button("設定", systemImage: "gearshape") { settings = true }; addButton } } }
        }
        .tint(Color(red: 0.46, green: 0.41, blue: 0.90))
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.refreshCalendar()
                _Concurrency.Task { await store.retryNotifications() }
            }
        }
        .task {
            #if DEBUG
            if !ProcessInfo.processInfo.arguments.contains("--ui-testing") { onboarding = !onboardingCompleted }
            #else
            onboarding = !onboardingCompleted
            #endif
        }
        .fullScreenCover(isPresented: $onboarding) { OnboardingView() }
        .sheet(isPresented: $addingEvent) { EventEditor() }
        .sheet(isPresented: $settings) { SettingsView() }
        .sheet(isPresented: $addingTask) { TaskEditor() }
        .alert("確認してください", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
    private var addButton: some View {
        Menu {
            Button("Task を追加", systemImage: "checkmark.circle") { addingTask = true }
            Button("予定を追加", systemImage: "calendar") { addingEvent = true }
        } label: { Label("追加", systemImage: "plus") }
        .accessibilityIdentifier("globalAdd")
    }
}
