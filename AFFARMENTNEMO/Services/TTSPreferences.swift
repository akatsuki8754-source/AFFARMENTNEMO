//
//  TTSPreferences.swift
//  AI音声 (TTS) の声選択 + 自動再生設定。
//  ユーザー要望: 国別の細かい声ではなく、端末言語に合う男性/女性だけ選ぶ。
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class TTSPreferences: ObservableObject {
    static let shared = TTSPreferences()

    /// "female" | "male"。端末の優先言語に合う声を自動解決する。
    @Published var selectedVoiceGender: String {
        didSet { UserDefaults.standard.set(selectedVoiceGender, forKey: "kotodama.tts.voiceGender") }
    }

    /// 起動時自動再生
    @Published var autoplayOnLaunch: Bool {
        didSet { UserDefaults.standard.set(autoplayOnLaunch, forKey: "kotodama.autoplay.enabled") }
    }
    /// 起動時自動再生のモード ("self" | "ai" | "recorded")
    @Published var autoplayMode: String {
        didSet { UserDefaults.standard.set(autoplayMode, forKey: "kotodama.autoplay.mode") }
    }

    /// AI音声をバックグラウンドでも継続する。ONにしたら自動再生もAIに揃える。
    @Published var backgroundAIPlaybackEnabled: Bool {
        didSet {
            UserDefaults.standard.set(backgroundAIPlaybackEnabled, forKey: "kotodama.tts.backgroundAIPlayback")
            if backgroundAIPlaybackEnabled {
                autoplayOnLaunch = true
                autoplayMode = "ai"
            }
        }
    }

    private init() {
        let defaults: [String: Any] = [
            "kotodama.tts.voiceGender": "female",
            "kotodama.autoplay.enabled": true,
            "kotodama.autoplay.mode": "ai",
            "kotodama.tts.backgroundAIPlayback": false,
        ]
        UserDefaults.standard.register(defaults: defaults)
        self.selectedVoiceGender = UserDefaults.standard.string(forKey: "kotodama.tts.voiceGender") ?? "female"
        self.autoplayOnLaunch = UserDefaults.standard.bool(forKey: "kotodama.autoplay.enabled")
        self.autoplayMode = UserDefaults.standard.string(forKey: "kotodama.autoplay.mode") ?? "ai"
        self.backgroundAIPlaybackEnabled = UserDefaults.standard.bool(forKey: "kotodama.tts.backgroundAIPlayback")
    }

    /// 試聴用シンセサイザー (短いサンプル文を再生)
    private let previewSynthesizer = AVSpeechSynthesizer()

    func preview() {
        previewSynthesizer.stopSpeaking(at: .immediate)

        // AudioSession 起動 (TTS が無音になるバグ対策)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true, options: [])
        } catch {
            print("[TTSPreferences] AudioSession failed: \(error)")
        }

        let sampleJa = "自分の言葉を、声に出して読みましょう。今日もよくやった。"
        let sampleEn = "Read your words out loud. Well done today."
        let preferred = Locale.preferredLanguages.first ?? "ja-JP"
        let voice = resolvedVoice(for: preferred)
        let text: String
        text = (voice?.language ?? preferred).lowercased().hasPrefix("ja") ? sampleJa : sampleEn
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = 0.46
        utterance.preUtteranceDelay = 0.2
        utterance.postUtteranceDelay = 0.2
        previewSynthesizer.speak(utterance)
    }

    func resolvedVoice(for fallbackLanguage: String) -> AVSpeechSynthesisVoice? {
        let normalized = normalizeLanguage(fallbackLanguage)
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { normalizeLanguage($0.language) == normalized }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality { return lhs.quality.rawValue > rhs.quality.rawValue }
                return lhs.name < rhs.name
            }
        let targetGender: AVSpeechSynthesisVoiceGender = selectedVoiceGender == "male" ? .male : .female
        if let genderMatch = voices.first(where: { $0.gender == targetGender }) {
            return genderMatch
        }
        if let first = voices.first {
            return first
        }
        return AVSpeechSynthesisVoice(language: normalized)
    }

    private func normalizeLanguage(_ raw: String) -> String {
        let lower = raw.replacingOccurrences(of: "_", with: "-").lowercased()
        if lower.hasPrefix("ja") { return "ja-JP" }
        if lower.hasPrefix("ko") { return "ko-KR" }
        if lower.hasPrefix("zh-hant") || lower.contains("-tw") || lower.contains("-hk") { return "zh-TW" }
        if lower.hasPrefix("zh") { return "zh-CN" }
        if lower.hasPrefix("en") { return "en-US" }
        return raw
    }
}
