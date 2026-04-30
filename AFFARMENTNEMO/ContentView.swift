//
//  ContentView.swift
//  ルート分岐: 初回 → オンボーディング、以降 → メインタブ
//  ユーザー要望: アプリ起動時に自動で音読を再生 (設定でON/OFF)
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage("kotodama.onboarding.completed") private var onboardingCompleted: Bool = false
    @AppStorage("kotodama.autoplay.enabled") private var autoplayEnabled: Bool = false
    @AppStorage("kotodama.autoplay.mode") private var autoplayMode: String = "self"
    @Query(filter: #Predicate<Affirmation> { $0.isActive && $0.includeInRoutine },
           sort: [SortDescriptor(\.orderIndex)])
    private var routineItems: [Affirmation]
    @State private var showAutoplay = false

    var body: some View {
        ZStack {
            if onboardingCompleted {
                MainTabView()
                    .transition(.opacity)
            } else {
                OnboardingFlowView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: onboardingCompleted)
        .fullScreenCover(isPresented: $showAutoplay) {
            ReadAloudView(items: routineItems, slot: "autoplay")
        }
        .onAppear {
            triggerAutoplayIfNeeded()
        }
    }

    private func triggerAutoplayIfNeeded() {
        guard autoplayEnabled, onboardingCompleted, !routineItems.isEmpty else { return }
        // 1秒ディレイで自動起動 (オンボ完了後の最初の起動も対応)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.0))
            showAutoplay = true
        }
    }
}
