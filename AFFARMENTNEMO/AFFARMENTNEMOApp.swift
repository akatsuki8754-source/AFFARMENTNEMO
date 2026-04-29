//
//  AFFARMENTNEMOApp.swift
//  ルート: SwiftData ModelContainer + Firebase + AdMob 起動 + オンボーディング分岐
//

import SwiftUI
import SwiftData

#if canImport(FirebaseCore)
import FirebaseCore
#endif

@main
struct AFFARMENTNEMOApp: App {
    let modelContainer: ModelContainer

    init() {
        // Firebase 初期化 (GoogleService-Info.plist が必要)
        #if canImport(FirebaseCore)
        FirebaseApp.configure()
        #endif

        do {
            modelContainer = try ModelContainer(
                for: Affirmation.self, ReadLog.self, UserStats.self
            )
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
        AdMobService.shared.start()

        // 匿名サインイン (アプリ全体で UID を保証)
        Task { @MainActor in
            await AuthService.shared.signInAnonymouslyIfNeeded()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(AffirmationStore(context: modelContainer.mainContext))
        }
        .modelContainer(modelContainer)
    }
}
