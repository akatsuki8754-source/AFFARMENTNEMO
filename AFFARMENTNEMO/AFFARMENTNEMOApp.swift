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

#if canImport(FirebaseAppCheck)
import FirebaseAppCheck
#endif

#if canImport(FirebasePerformance)
import FirebasePerformance
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
            "kotodama.tts.backgroundAIPlayback": true,  // 審査通過後は常時 ON
        ])

        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-testing-aiwizard") {
            UserDefaults.standard.set(false, forKey: "kotodama.onboarding.completed")
            UserDefaults.standard.set(false, forKey: "kotodama.autoplay.enabled")
            UserDefaults.standard.set("", forKey: "kotodama.draft.text")
            UserDefaults.standard.set("", forKey: "kotodama.autoplay.lastDay")
        }
        if arguments.contains("-ui-testing-timeline") {
            UserDefaults.standard.set(true, forKey: "kotodama.onboarding.completed")
            UserDefaults.standard.set(true, forKey: "kotodama.timeline.firstSeen")
            UserDefaults.standard.set(true, forKey: "kotodama.timeline.canPost")
            UserDefaults.standard.set(true, forKey: "kotodama.eula.accepted")
            UserDefaults.standard.set(false, forKey: "kotodama.autoplay.enabled")
            UserDefaults.standard.set(true, forKey: "kotodama.screenshot.mode")
            UserDefaults.standard.set(2, forKey: "kotodama.debug.startTab")
            UserDefaults.standard.set(false, forKey: "kotodama.debug.openAIWizard")
            UserDefaults.standard.set(false, forKey: "kotodama.debug.autoGenerateAI")
            UserDefaults.standard.set(false, forKey: "kotodama.debug.timelinePostSubmitted")
            if let roomIndex = arguments.firstIndex(of: "-ui-testing-timeline-room"),
               arguments.indices.contains(arguments.index(after: roomIndex)) {
                UserDefaults.standard.set(arguments[arguments.index(after: roomIndex)],
                                          forKey: "kotodama.debug.timelineRoom")
            }
            if let postIndex = arguments.firstIndex(of: "-ui-testing-timeline-post"),
               arguments.indices.contains(arguments.index(after: postIndex)) {
                UserDefaults.standard.set(arguments[arguments.index(after: postIndex)],
                                          forKey: "kotodama.debug.timelinePost")
            } else {
                UserDefaults.standard.set("", forKey: "kotodama.debug.timelinePost")
            }
        }
        #endif

        // 言語オーバーライド (アプリ内言語切替)
        LocalizationOverride.install()

        // App Check Provider (Firebase 初期化前に必ず設定)
        #if canImport(FirebaseAppCheck)
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        // iOS 14+ 推奨 AppAttest、未対応端末は DeviceCheck フォールバック
        AppCheck.setAppCheckProviderFactory(KotodamaAppCheckProviderFactory())
        #endif
        #endif

        // Firebase 初期化
        #if canImport(FirebaseCore)
        FirebaseApp.configure()
        #endif

        // Firebase Performance Monitoring (FirebaseApp.configure() 後)
        #if canImport(FirebasePerformance)
        Performance.sharedInstance().isDataCollectionEnabled = true
        Performance.sharedInstance().isInstrumentationEnabled = true
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
            let affirmationStore = AffirmationStore(context: modelContainer.mainContext)
            ContentView()
                .environment(affirmationStore)
                .onAppear {
                    // デフォルト 20 affirmation を seed (1度だけ)
                    affirmationStore.seedDefaultAffirmationsIfNeeded()
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
