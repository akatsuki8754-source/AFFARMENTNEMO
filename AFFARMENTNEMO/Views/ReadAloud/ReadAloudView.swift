//
//  ReadAloudView.swift
//  音読画面: 自発音読が主役 (Production Effect)、TTSは補助
//  仕様: UX v4 §5 / 04_アファメーション科学的根拠 §1
//

import SwiftUI
import AVFoundation
import UIKit
import Combine

/// TTS イベントログ + AIモード時の自動進行通知
@MainActor
final class TTSLogger: NSObject, AVSpeechSynthesizerDelegate, ObservableObject {
    static let shared = TTSLogger()
    @Published var lastEvent: String = "idle"
    /// 完了時のコールバック (ReadAloud から登録、AIモードで次へ進む)
    var onFinish: (() -> Void)?

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) {
        print("[TTS] didStart len=\(u.speechString.count)")
        Task { @MainActor in self.lastEvent = "didStart \(u.speechString.count)文字" }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        print("[TTS] didFinish")
        Task { @MainActor in
            self.lastEvent = "didFinish"
            self.onFinish?()
        }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        print("[TTS] didCancel")
        Task { @MainActor in self.lastEvent = "didCancel" }
    }
}

/// 3つの再生モード (ユーザー要望)
enum ReadPlaybackMode: String, CaseIterable, Identifiable {
    case selfRead   // 自分で読み上げる (音声なし、UIで促進、「読みました」で進行)
    case ai         // AIで再生 (TTS) — 自動進行
    case recorded   // 録音再生 — 自動進行

    var id: String { rawValue }
    var label: String {
        switch self {
        case .selfRead: "音読をする"
        case .ai: "AIで読み上げる"
        case .recorded: "録音した音声で流す"
        }
    }
    var icon: String {
        switch self {
        case .selfRead: "person.fill"
        case .ai: "speaker.wave.2.fill"
        case .recorded: "waveform"
        }
    }

    var storageValue: String {
        switch self {
        case .selfRead: "self"
        case .ai: "ai"
        case .recorded: "recorded"
        }
    }

    static func fromStorage(_ value: String) -> ReadPlaybackMode {
        switch value {
        case "recorded": return .recorded
        case "self", "selfRead": return .selfRead
        default: return .ai
        }
    }
}

struct ReadAloudView: View {
    @Environment(AffirmationStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let items: [Affirmation]
    let slot: String
    var initialMode: ReadPlaybackMode? = nil
    var autoStart: Bool = false

    @State private var index: Int = 0
    @State private var completed = false
    @State private var result: ReadCompletionResult?
    @State private var ttsSpeaking = false
    @State private var synthesizer = AVSpeechSynthesizer()
    @State private var playbackMode: ReadPlaybackMode = .selfRead
    @StateObject private var rec = RecordingService.shared
    @State private var autoPlayInProgress = false
    @AppStorage("kotodama.autoplay.mode") private var autoplayMode: String = "ai"
    @AppStorage("kotodama.autoplay.enabled") private var autoplayEnabled: Bool = true

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            if completed, let result {
                ReadCompleteView(result: result, onClose: {
                    showInterstitialThenDismiss()
                })
                .responsivePage()
                .transition(.opacity)
            } else {
                readingScreen
                    .responsivePage()
            }
        }
        .onAppear {
            // 起動時自動再生モードがあれば適用
            if let initialMode {
                playbackMode = initialMode
            } else if slot == "autoplay" && autoplayEnabled {
                playbackMode = ReadPlaybackMode.fromStorage(autoplayMode)
            }
            if autoStart || (slot == "autoplay" && autoplayEnabled) {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.5))
                    if playbackMode == .ai { speakTTS() }
                    else if playbackMode == .recorded { playRecording() }
                }
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
                // 長文時に画面切れしないようスクロール可能領域に
                ScrollView(.vertical, showsIndicators: true) {
                    Text(items[index].text)
                        .font(.system(size: 28, weight: .semibold, design: .default))
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.screenEdge)
                        .padding(.vertical, AppSpacing.md)
                        .accessibilityAddTraits(.isHeader)
                        .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.visible)
                .frame(maxHeight: 360)
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

            VStack(spacing: AppSpacing.md) {
                // 3 モード選択 (ユーザー要望: ワンタップで切替、途中でも切替可能)
                HStack(spacing: AppSpacing.xs) {
                    ForEach(ReadPlaybackMode.allCases) { mode in
                        Button {
                            switchMode(to: mode)
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: mode.icon)
                                    .font(.system(size: 18, weight: .medium))
                                Text(mode.label)
                                    .appFont(.micro)
                            }
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .foregroundStyle(playbackMode == mode ? Color.bgPrimary : Color.textSecondary)
                            .background(playbackMode == mode ? Color.brandPrimary : Color.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.buttonSecondary))
                        }
                        .disabled(mode == .recorded && !canPlayRecording)
                        .opacity(mode == .recorded && !canPlayRecording ? 0.4 : 1)
                    }
                }

                // 主役: 「読みました」(self) または「次へ」(AI/録音 自動進行中)
                Button(action: primaryAction) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: primaryButtonIcon)
                            .font(.system(size: 24, weight: .semibold))
                        Text(primaryButtonLabel)
                            .appFont(.h3)
                    }
                    .foregroundStyle(Color.bgPrimary)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Color.brandPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
                }

                Button(action: skip) {
                    Label("read.skip", systemImage: "forward")
                        .appFont(.body)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: AppTouchTarget.buttonHeight)
                        .background(Color.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.buttonSecondary))
                }
            }
            .padding(.horizontal, AppSpacing.screenEdge)
            .padding(.bottom, AppSpacing.lg)
        }
    }

    private var headerTitle: String {
        let prefix: String
        switch slot {
        case "morning":
            prefix = NSLocalizedString("read.title.morning", comment: "")
        case "evening":
            prefix = NSLocalizedString("read.title.evening", comment: "")
        default:
            prefix = "今日の言葉"
        }
        return "\(prefix) (\(index + 1)/\(items.count))"
    }

    /// 現在のアファメに録音があるか
    private var canPlayRecording: Bool {
        guard items.indices.contains(index),
              let fn = items[index].recordingFileName else { return false }
        return rec.hasRecording(fileName: fn)
    }

    private var primaryButtonIcon: String {
        switch playbackMode {
        case .selfRead: "checkmark.circle.fill"
        case .ai: ttsSpeaking ? "stop.circle.fill" : "play.fill"
        case .recorded: rec.isPlaying ? "stop.circle.fill" : "play.fill"
        }
    }

    private var primaryButtonLabel: LocalizedStringKey {
        switch playbackMode {
        case .selfRead: "read.done"   // 「読みました」
        case .ai: ttsSpeaking ? "停止" : "AIで読み上げる"
        case .recorded: rec.isPlaying ? "停止" : "録音を再生"
        }
    }

    private func primaryAction() {
        switch playbackMode {
        case .selfRead:
            advance()
        case .ai:
            if ttsSpeaking {
                synthesizer.stopSpeaking(at: .immediate)
                ttsSpeaking = false
            } else {
                speakTTS()
            }
        case .recorded:
            if rec.isPlaying {
                rec.stopPlaying()
            } else {
                playRecording()
            }
        }
    }

    private func switchMode(to mode: ReadPlaybackMode) {
        // 現在の再生を中断してモード切替
        synthesizer.stopSpeaking(at: .immediate)
        rec.stopPlaying()
        ttsSpeaking = false
        playbackMode = mode
    }

    private func advance() {
        synthesizer.stopSpeaking(at: .immediate)
        rec.stopPlaying()
        ttsSpeaking = false

        if index + 1 < items.count {
            index += 1
            // ユーザー要望: AI/録音 自動切替時に1秒間を空ける (連続で繋がって聞こえる問題対策)
            if playbackMode == .ai {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.0))
                    if playbackMode == .ai { speakTTS() }
                }
            } else if playbackMode == .recorded {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.0))
                    if playbackMode == .recorded { playRecording() }
                }
            }
        } else {
            let r = store.recordRead(slot: slot)
            withAnimation { result = r; completed = true }
        }
    }

    private func skip() {
        advance()
    }

    private func playRecording() {
        guard items.indices.contains(index) else { return }
        guard let fn = items[index].recordingFileName,
              rec.hasRecording(fileName: fn) else {
            playbackMode = .selfRead
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.35))
                advance()
            }
            return
        }
        do {
            try rec.play(fileName: fn) { _ in
                // 録音モードで再生完了 → 自動進行
                Task { @MainActor in
                    if playbackMode == .recorded { advance() }
                }
            }
        } catch {
            print("[Recording] play failed: \(error)")
        }
    }

    /// TTSバグ修正: AVAudioSession の playback カテゴリ設定 + トグル動作
    private func speakTTS() {
        // 既に再生中ならトグルで停止
        if ttsSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            ttsSpeaking = false
            return
        }
        guard items.indices.contains(index) else { return }

        // ⚠️ 重要: 補助読み上げが流れないバグの主因 — AVAudioSession の設定不備
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            print("[TTS] AudioSession failed: \(error)")
        }

        // ユーザー要望: AI音声のタイミング自然化
        // 「、」「。」「,」「.」「!」「?」で一拍空ける + 速度を人の話す速度(150 wpm 相当)に調整
        let raw = items[index].text
        let withPauses = raw
            .replacingOccurrences(of: "、", with: "、 ")
            .replacingOccurrences(of: "。", with: "。 ")
            .replacingOccurrences(of: "！", with: "！ ")
            .replacingOccurrences(of: "？", with: "？ ")
            .replacingOccurrences(of: ", ", with: ",  ")
            .replacingOccurrences(of: ". ", with: ".  ")

        let utterance = AVSpeechUtterance(string: withPauses)
        let preferred = Locale.preferredLanguages.first ?? "ja-JP"
        utterance.voice = TTSPreferences.shared.resolvedVoice(for: preferred)
                          ?? AVSpeechSynthesisVoice(language: "ja-JP")
        // AVSpeechUtteranceDefaultSpeechRate ≈ 0.5。人の話す速度 ≈ 0.45 (やや遅め)
        utterance.rate = 0.46
        utterance.volume = 1.0
        utterance.pitchMultiplier = 1.0
        // 文の前後にも 0.4秒の余韻
        utterance.preUtteranceDelay = 0.3
        utterance.postUtteranceDelay = 0.4

        // delegate を装着 + AIモードで完了時に自動進行
        synthesizer.delegate = TTSLogger.shared
        TTSLogger.shared.onFinish = { [self] in
            self.ttsSpeaking = false
            if self.playbackMode == .ai {
                self.advance()
            }
        }

        ttsSpeaking = true
        synthesizer.speak(utterance)
        print("[TTS] speak() called text='\(items[index].text)' lang=\(preferred) volume=\(utterance.volume)")
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
    @State private var secondsRemaining = 10

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

            Text("\(secondsRemaining)秒後にホームへ戻ります")
                .appFont(.caption)
                .foregroundStyle(Color.textSecondary)

            Spacer()

            PrimaryButton(titleKey: "complete.home", action: onClose)
                .padding(.horizontal, AppSpacing.screenEdge)
                .padding(.bottom, AppSpacing.lg)
        }
        .task {
            secondsRemaining = 10
            while secondsRemaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                secondsRemaining -= 1
            }
            onClose()
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
