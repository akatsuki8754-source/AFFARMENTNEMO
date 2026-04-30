//
//  ContentView.swift
//  ルート分岐: 初回 → オンボーディング、以降 → メインタブ
//  ユーザー要望: アプリ起動時に自動で音読を再生 (設定でON/OFF)
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage("kotodama.onboarding.completed") private var onboardingCompleted: Bool = false
    @AppStorage("kotodama.autoplay.enabled") private var autoplayEnabled: Bool = true
    @AppStorage("kotodama.autoplay.mode") private var autoplayMode: String = "ai"
    @AppStorage("kotodama.autoplay.lastDay") private var lastAutoplayDay: String = ""
    @Query(filter: #Predicate<Affirmation> { $0.isActive && $0.includeInRoutine },
           sort: [SortDescriptor(\.orderIndex)])
    private var routineItems: [Affirmation]
    @StateObject private var playbackRouter = RoutinePlaybackRouter.shared
    @State private var showAutoplay = false
    @State private var initialMode: ReadPlaybackMode = .ai
    @State private var didTriggerLaunchAutoplay = false

    private var playableRoutineItems: [Affirmation] {
        routineItems.filter { $0.isAvailableNow() }
    }

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
            ReadAloudView(items: playableRoutineItems, slot: "autoplay", initialMode: initialMode, autoStart: true)
        }
        .onAppear {
            triggerAutoplayIfNeeded()
        }
        .onChange(of: playbackRouter.requestID) { _, _ in
            guard onboardingCompleted, !playableRoutineItems.isEmpty else { return }
            initialMode = playbackRouter.requestedMode
            showAutoplay = true
        }
    }

    private func triggerAutoplayIfNeeded() {
        guard !didTriggerLaunchAutoplay,
              autoplayEnabled,
              onboardingCompleted,
              !playableRoutineItems.isEmpty else { return }
        let today = Self.dayKey()
        guard lastAutoplayDay != today else { return }
        didTriggerLaunchAutoplay = true
        lastAutoplayDay = today
        initialMode = ReadPlaybackMode.fromStorage(autoplayMode)
        // 1秒ディレイで自動起動 (オンボ完了後の最初の起動も対応)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.0))
            showAutoplay = true
        }
    }

    private static func dayKey(_ date: Date = Date()) -> String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
    }
}
