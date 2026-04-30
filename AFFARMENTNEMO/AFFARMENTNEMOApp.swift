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
    /// 永続化: 過去にATT要求した記録を残し、scenePhase=.activeが再度来ても再呼び出ししない
    @AppStorage("kotodama.att.requestedOnce") private var didRequestATTPersisted: Bool = false
    @State private var attInProgress = false

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

    /// 1度だけATT要求 → AdMob起動。永続化フラグで scene 再アクティブ時の重複ダイアログを防ぐ
    @MainActor
    private func requestATTAndStartAdsIfNeeded() {
        guard !didRequestATTPersisted, !attInProgress else {
            // すでに要求済みなら AdMob のみ起動 (毎回起動はOK・冪等)
            AdMobService.shared.start()
            return
        }
        attInProgress = true
        ATTService.requestAuthorizationIfNeeded {
            self.didRequestATTPersisted = true
            self.attInProgress = false
            AdMobService.shared.start()
        }
    }
}
