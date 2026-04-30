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
        let preferred = Self.effectiveSpeechLanguage()
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
        let requestedFamily = languageFamily(normalized)
        var voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { normalizeLanguage($0.language) == normalized }
        if voices.isEmpty {
            voices = AVSpeechSynthesisVoice.speechVoices()
                .filter { languageFamily($0.language) == requestedFamily }
        }
        voices = voices
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality { return lhs.quality.rawValue > rhs.quality.rawValue }
                return lhs.name < rhs.name
            }
        let targetGender: AVSpeechSynthesisVoiceGender = selectedVoiceGender == "male" ? .male : .female

        // ── 1. AVSpeechSynthesisVoice.gender で完全一致 ──
        if let exactMatch = voices.first(where: { $0.gender == targetGender }) {
            NSLog("[TTS] resolved (gender exact): %@ (%@)", exactMatch.name, exactMatch.language)
            return exactMatch
        }

        // ── 2. .unspecified の場合は voice 名で推論 ──
        // Apple の多くの voice は .unspecified を返すので名前パターンマッチが必要
        let scored = voices.map { voice -> (AVSpeechSynthesisVoice, Int) in
            let inferredScore = self.genderScore(for: voice, target: targetGender)
            return (voice, inferredScore)
        }.sorted { $0.1 > $1.1 }

        if let best = scored.first, best.1 > 0 {
            NSLog("[TTS] resolved (name-inferred): %@ (%@), score=%d, target=%@",
                  best.0.name, best.0.language, best.1,
                  selectedVoiceGender)
            return best.0
        }

        // ── 3. フォールバック: 性別不問で best quality voice ──
        if let first = voices.first {
            NSLog("[TTS] resolved (fallback): %@ (%@) — gender=%@ NOT FOUND",
                  first.name, first.language, selectedVoiceGender)
            return first
        }
        return AVSpeechSynthesisVoice(language: normalized)
    }

    static func effectiveSpeechLanguage() -> String {
        let appLanguage = UserDefaults.standard.string(forKey: "kotodama.appLanguage") ?? "system"
        let effective = LanguageCatalog.effectiveAppLocaleIdentifier(userDefaultValue: appLanguage)
        return effective == "system" ? (Locale.preferredLanguages.first ?? "ja-JP") : effective
    }

    /// voice 名から性別を推論してスコア化 (target に合致するほど高スコア)
    /// Apple の voice カタログから手動キュレーション (ja/en/zh/ko 主要言語のみ)
    private func genderScore(for voice: AVSpeechSynthesisVoice, target: AVSpeechSynthesisVoiceGender) -> Int {
        let name = voice.name.lowercased()
        // 男性 voice 名 (Apple iOS 17+ ベース)
        let maleNames: Set<String> = [
            "otoya", "hattori",                  // ja
            "alex", "daniel", "tom", "fred",     // en (Daniel/Fred は男性)
            "li-mu", "yu-shu",                    // zh
            "tian-tian"                            // zh-CN
        ]
        // 女性 voice 名
        let femaleNames: Set<String> = [
            "kyoko", "siri", "o-ren",            // ja (Siri is gender-fluid だが Apple 分類は female)
            "samantha", "allison", "ava", "susan", "victoria", "karen", "moira",
            "tessa", "fiona",                    // en
            "ting-ting", "sin-ji", "mei-jia",   // zh
            "yuna"                                // ko
        ]

        let isMaleName = maleNames.contains(where: { name.contains($0) })
        let isFemaleName = femaleNames.contains(where: { name.contains($0) })

        var score = 0
        if target == .male {
            if isMaleName { score += 100 }
            if isFemaleName { score -= 100 }
        } else {
            if isFemaleName { score += 100 }
            if isMaleName { score -= 100 }
        }
        // quality boost (Enhanced/Premium voices > Default)
        score += voice.quality.rawValue * 5
        return score
    }

    private func normalizeLanguage(_ raw: String) -> String {
        let lower = raw.replacingOccurrences(of: "_", with: "-").lowercased()
        if lower.hasPrefix("ja") { return "ja-JP" }
        if lower.hasPrefix("ko") { return "ko-KR" }
        if lower.hasPrefix("zh-hant") || lower.contains("-tw") || lower.contains("-hk") { return "zh-TW" }
        if lower.hasPrefix("zh") { return "zh-CN" }
        if lower.hasPrefix("en") { return "en-US" }
        if lower.hasPrefix("es") { return "es-ES" }
        if lower.hasPrefix("fr") { return "fr-FR" }
        if lower.hasPrefix("de") { return "de-DE" }
        if lower.hasPrefix("pt") { return "pt-BR" }
        if lower.hasPrefix("id") { return "id-ID" }
        if lower.hasPrefix("vi") { return "vi-VN" }
        if lower.hasPrefix("th") { return "th-TH" }
        if lower.hasPrefix("hi") { return "hi-IN" }
        if lower.hasPrefix("ar") { return "ar-SA" }
        return raw
    }

    private func languageFamily(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .first
            .map(String.init)?
            .lowercased() ?? raw.lowercased()
    }
}
