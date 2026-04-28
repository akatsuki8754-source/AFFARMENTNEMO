//
//  ReadAloudView.swift
//  音読画面: 自発音読が主役 (Production Effect)、TTSは補助
//  仕様: UX v4 §5 / 04_アファメーション科学的根拠 §1
//

import SwiftUI
import AVFoundation
import UIKit

struct ReadAloudView: View {
    @Environment(AffirmationStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let items: [Affirmation]
    let slot: String

    @State private var index: Int = 0
    @State private var completed = false
    @State private var result: ReadCompletionResult?
    @State private var ttsSpeaking = false
    @State private var synthesizer = AVSpeechSynthesizer()

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            if completed, let result {
                ReadCompleteView(result: result, onClose: {
                    showInterstitialThenDismiss()
                })
                .transition(.opacity)
            } else {
                readingScreen
            }
        }
        .onDisappear {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private var readingScreen: some View {
        VStack(spacing: AppSpacing.lg) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: AppTouchTarget.minimum, height: AppTouchTarget.minimum)
                }
                Spacer()
                Text(headerTitle)
                    .appFont(.caption)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Spacer().frame(width: AppTouchTarget.minimum)
            }
            .padding(.horizontal, AppSpacing.screenEdge)

            Spacer()

            if items.indices.contains(index) {
                Text(items[index].text)
                    .font(.system(size: 28, weight: .semibold, design: .default))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.screenEdge)
                    .accessibilityAddTraits(.isHeader)
            }

            VStack(spacing: AppSpacing.xs) {
                Text("read.production.cue")
                    .appFont(.bodyEmphasis)
                    .foregroundStyle(Color.brandSecondary)
                Text("read.production.note")
                    .appFont(.micro)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            // 進捗インジケータ
            HStack(spacing: 6) {
                ForEach(items.indices, id: \.self) { i in
                    Circle()
                        .fill(i <= index ? Color.brandPrimary : Color.bgTertiary)
                        .frame(width: 8, height: 8)
                }
            }

            VStack(spacing: AppSpacing.sm) {
                PrimaryButton(titleKey: "read.done", action: advance)

                HStack(spacing: AppSpacing.md) {
                    Button(action: speakTTS) {
                        Label("read.tts", systemImage: ttsSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                            .appFont(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .frame(minHeight: AppTouchTarget.minimum)
                    }

                    Button(action: skip) {
                        Label("read.skip", systemImage: "forward")
                            .appFont(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .frame(minHeight: AppTouchTarget.minimum)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.screenEdge)
            .padding(.bottom, AppSpacing.lg)
        }
    }

    private var headerTitle: String {
        let prefix = NSLocalizedString(slot == "morning" ? "read.title.morning" : "read.title.evening", comment: "")
        return "\(prefix) (\(index + 1)/\(items.count))"
    }

    private func advance() {
        if index + 1 < items.count {
            index += 1
        } else {
            // 完了処理
            let r = store.recordRead(slot: slot)
            withAnimation { result = r; completed = true }
        }
    }

    private func skip() {
        advance()
    }

    private func speakTTS() {
        synthesizer.stopSpeaking(at: .immediate)
        guard items.indices.contains(index) else { return }
        let utterance = AVSpeechUtterance(string: items[index].text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        ttsSpeaking = true
        synthesizer.speak(utterance)
        // 簡易: 完了監視は省略 (UIスピナー的扱い)
        Task {
            try? await Task.sleep(for: .seconds(3))
            ttsSpeaking = false
        }
    }

    private func showInterstitialThenDismiss() {
        let stats = store.userStats()
        if let topVC = topViewController() {
            #if canImport(GoogleMobileAds)
            AdMobService.shared.showInterstitialIfReady(from: topVC, stats: stats)
            #endif
        }
        dismiss()
    }

    private func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return nil }
        var top = root
        while let p = top.presentedViewController { top = p }
        return top
    }
}

// MARK: - Completion

struct ReadCompleteView: View {
    let result: ReadCompletionResult
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()

            Text("🎉")
                .font(.system(size: 64))

            Text(LocalizedStringKey(streakMessageKey))
                .appFont(.h2)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)

            VStack(spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "flame.fill").foregroundStyle(Color.brandAccent)
                    Text("complete.streak.\(result.currentStreak)")
                        .appFont(.bodyEmphasis)
                        .foregroundStyle(Color.textPrimary)
                }
                Text("complete.xp.\(result.xpGained)")
                    .appFont(.body)
                    .foregroundStyle(Color.textSecondary)
                if result.leveledUp {
                    Text("complete.levelup.\(result.newLevel)")
                        .appFont(.bodyEmphasis)
                        .foregroundStyle(Color.semanticSuccess)
                }
            }

            Text("complete.tomorrow")
                .appFont(.caption)
                .foregroundStyle(Color.textSecondary)
                .padding(.top, AppSpacing.md)

            Spacer()

            PrimaryButton(titleKey: "complete.home", action: onClose)
                .padding(.horizontal, AppSpacing.screenEdge)
                .padding(.bottom, AppSpacing.lg)
        }
    }

    private var streakMessageKey: String {
        switch result.currentStreak {
        case 1: "complete.msg.day1"
        case 3: "complete.msg.day3"
        case 7: "complete.msg.day7"
        case 14: "complete.msg.day14"
        case 21: "complete.msg.day21"
        case 30: "complete.msg.day30"
        case 100: "complete.msg.day100"
        default: "complete.msg.default"
        }
    }
}
