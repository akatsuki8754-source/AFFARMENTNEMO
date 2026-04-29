//
//  AFFARMENTNEMOApp.swift
//  ルート: SwiftData ModelContainer + Firebase + ATT → AdMob 起動 + オンボーディング分岐
//

import SwiftUI
import SwiftData

#if canImport(FirebaseCore)
import FirebaseCore
#endif

#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif

@main
struct AFFARMENTNEMOApp: App {
    let modelContainer: ModelContainer
    @Environment(\.scenePhase) private var scenePhase
    @State private var didRequestATT = false

    init() {
        // Firebase 初期化
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

        // ⚠️ AdMob はここでは起動しない (ATT 後に起動)
        // 匿名サインインのみ先行
        Task { @MainActor in
            await AuthService.shared.signInAnonymouslyIfNeeded()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(AffirmationStore(context: modelContainer.mainContext))
                .onAppear {
                    requestATTAndStartAdsIfNeeded()
                }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                requestATTAndStartAdsIfNeeded()
            }
        }
    }

    /// アクティブ scene が確実に存在する状態で ATT ダイアログ → AdMob 起動 (Apple Guideline 2.1 準拠)
    @MainActor
    private func requestATTAndStartAdsIfNeeded() {
        guard !didRequestATT else { return }
        didRequestATT = true
        ATTService.requestAuthorizationIfNeeded {
            // 許可/拒否どちらでも AdMob は起動 (拒否時は IDFA を取らない非個別化広告)
            AdMobService.shared.start()
        }
    }
}
