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
        UserDefaults.standard.register(defaults: [
            "kotodama.autoplay.enabled": true,
            "kotodama.autoplay.mode": "ai",
            "kotodama.tts.voiceGender": "female",
            "kotodama.tts.backgroundAIPlayback": false,
        ])

        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-testing-aiwizard") {
            UserDefaults.standard.set(false, forKey: "kotodama.onboarding.completed")
            UserDefaults.standard.set(false, forKey: "kotodama.autoplay.enabled")
            UserDefaults.standard.set("", forKey: "kotodama.draft.text")
            UserDefaults.standard.set("", forKey: "kotodama.autoplay.lastDay")
        }
        #endif

        // 言語オーバーライド (アプリ内言語切替)
        LocalizationOverride.install()

        // Firebase 初期化
        #if canImport(FirebaseCore)
        FirebaseApp.configure()
        #endif

        _ = NotificationService.shared

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

    @AppStorage("kotodama.onboarding.completed") private var onboardingCompleted: Bool = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(AffirmationStore(context: modelContainer.mainContext))
                .onAppear {
                    // オンボ未完了 → ATT は出さず AdMob だけ起動 (バナーは出るが個別化なし)
                    // オンボ完了 → ATT 要求して AdMob 起動 (個別化広告で収益最適化)
                    if onboardingCompleted {
                        requestATTAndStartAdsIfNeeded()
                    } else {
                        // ATT は出さず AdMob のみ起動 (オンボ中は集中させる)
                        AdMobService.shared.start()
                    }
                }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && onboardingCompleted {
                requestATTAndStartAdsIfNeeded()
            }
        }
        // ユーザー要望: オンボ完了したら必要なタイミングでATT
        .onChange(of: onboardingCompleted) { _, done in
            if done {
                // オンボ完了直後にATT要求 (ホーム到達時に AdMob バナーが出る前)
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    requestATTAndStartAdsIfNeeded()
                }
            }
        }
    }

    /// 1度だけATT要求 → AdMob起動。オンボ完了後にしか呼ばれない
    @MainActor
    private func requestATTAndStartAdsIfNeeded() {
        guard !didRequestATTPersisted, !attInProgress else {
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
