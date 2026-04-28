//
//  ContentView.swift
//  ルート分岐: 初回 → オンボーディング、以降 → メインタブ
//

import SwiftUI

struct ContentView: View {
    @AppStorage("kotodama.onboarding.completed") private var onboardingCompleted: Bool = false

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
    }
}
