//
//  AFFARMENTNEMOApp.swift
//  ルート: SwiftData ModelContainer + AdMob 起動 + オンボーディング分岐
//

import SwiftUI
import SwiftData

@main
struct AFFARMENTNEMOApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(
                for: Affirmation.self, ReadLog.self, UserStats.self
            )
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
        AdMobService.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(AffirmationStore(context: modelContainer.mainContext))
        }
        .modelContainer(modelContainer)
    }
}
