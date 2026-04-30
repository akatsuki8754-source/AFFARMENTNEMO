//
//  TTSPreferences.swift
//  AI音声 (TTS) の声選択 + 自動再生設定。
//  ユーザー要望: 男性/女性/子供 など、運用無料の範囲で選べる声を全列挙 + 試聴ボタン
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class TTSPreferences: ObservableObject {
    static let shared = TTSPreferences()

    /// 選択中の音声 ID (AVSpeechSynthesisVoiceIdentifier)
    /// nil の場合は端末の preferred language デフォルト音声
    @Published var selectedVoiceId: String? {
        didSet { UserDefaults.standard.set(selectedVoiceId, forKey: "kotodama.tts.voiceId") }
    }

    /// 起動時自動再生
    @Published var autoplayOnLaunch: Bool {
        didSet { UserDefaults.standard.set(autoplayOnLaunch, forKey: "kotodama.autoplay.enabled") }
    }
    /// 起動時自動再生のモード ("self" | "ai" | "recorded")
    @Published var autoplayMode: String {
        didSet { UserDefaults.standard.set(autoplayMode, forKey: "kotodama.autoplay.mode") }
    }

    private init() {
        self.selectedVoiceId = UserDefaults.standard.string(forKey: "kotodama.tts.voiceId")
        self.autoplayOnLaunch = UserDefaults.standard.bool(forKey: "kotodama.autoplay.enabled")
        self.autoplayMode = UserDefaults.standard.string(forKey: "kotodama.autoplay.mode") ?? "self"
    }

    // MARK: - Voice list
    struct VoiceOption: Identifiable, Hashable {
        let id: String       // identifier
        let name: String
        let language: String
        let quality: String  // "標準" | "拡張" | "プレミアム"
        let gender: String   // "女性" | "男性" | "不明"
    }

    /// 利用可能な音声を取得 (preferred language を最優先 + en-US/ja-JP も含める)
    func availableVoices() -> [VoiceOption] {
        let allowedPrefixes: Set<String> = ["ja", "en", "ko", "zh"]
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { v in
                let lang = v.language.lowercased()
                return allowedPrefixes.contains(where: { lang.hasPrefix($0) })
            }
        return voices.map { v in
            VoiceOption(
                id: v.identifier,
                name: v.name,
                language: v.language,
                quality: qualityLabel(v.quality),
                gender: genderLabel(v.gender)
            )
        }
        .sorted { ($0.language, $0.name) < ($1.language, $1.name) }
    }

    private func qualityLabel(_ q: AVSpeechSynthesisVoiceQuality) -> String {
        switch q {
        case .default: return "標準"
        case .enhanced: return "拡張"
        case .premium: return "プレミアム"
        @unknown default: return "標準"
        }
    }

    private func genderLabel(_ g: AVSpeechSynthesisVoiceGender) -> String {
        switch g {
        case .female: return "女性"
        case .male: return "男性"
        case .unspecified: return "不明"
        @unknown default: return "不明"
        }
    }

    /// 試聴用シンセサイザー (短いサンプル文を再生)
    private let previewSynthesizer = AVSpeechSynthesizer()

    func preview(voiceId: String?) {
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
        let voice: AVSpeechSynthesisVoice?
        let text: String
        if let id = voiceId, let v = AVSpeechSynthesisVoice(identifier: id) {
            voice = v
            text = v.language.lowercased().hasPrefix("ja") ? sampleJa : sampleEn
        } else {
            voice = AVSpeechSynthesisVoice(language: "ja-JP")
            text = sampleJa
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = 0.46
        utterance.preUtteranceDelay = 0.2
        utterance.postUtteranceDelay = 0.2
        previewSynthesizer.speak(utterance)
    }

    func resolvedVoice(for fallbackLanguage: String) -> AVSpeechSynthesisVoice? {
        if let id = selectedVoiceId, let v = AVSpeechSynthesisVoice(identifier: id) {
            return v
        }
        return AVSpeechSynthesisVoice(language: fallbackLanguage)
    }
}
