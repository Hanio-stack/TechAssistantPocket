//
//  TechAssistantPocketApp.swift
//  TechAssistantPocket
//
//  Created by 腐った卵 on 2026/09/19.
//

import SwiftUI
import SwiftData

@main
struct TechAssistantPocketApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Task.self,
            TaskOccurrence.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
