//
//  AIWishGenerationService.swift
//  Phase 3: Gemini Flash-Lite 本接続。
//   - Firestore `system/aiRuntime.clientEnabled` でランタイム ON/OFF
//   - FirebaseFunctions SDK で onCall (asia-northeast1)
//   - 失敗時は呼出元で静的フォールバック (UX 阻害しない)
//

import Foundation

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

enum AIWishGenerationError: Error {
    case unavailable
    case invalidResponse
    case quotaExceeded(canWatchAd: Bool)
    case budgetEmergencyStop
}

@MainActor
final class AIWishGenerationService {
    static let shared = AIWishGenerationService()
    private init() {}

    /// Firestore aiRuntime.clientEnabled をチェック (Phase 3 の有効化フラグ)
    /// 注意: 認証が必須 (rules で authed() && docId == 'aiRuntime' の read 許可)
    /// 認証未完了時は signInAnonymouslyIfNeeded で完了を待つ
    /// オフライン or エラー時は false (静的フォールバック)
    func liveGenerationEnabled() async -> Bool {
        #if canImport(FirebaseAuth)
        // 必ず認証完了を待つ — 未認証で Firestore 読むと permission denied
        await AuthService.shared.signInAnonymouslyIfNeeded()
        guard Auth.auth().currentUser != nil else {
            NSLog("[AIWishGen] liveGenerationEnabled: not signed in")
            return false
        }
        #endif

        #if canImport(FirebaseFirestore)
        do {
            let snapshot = try await Firestore.firestore()
                .collection("system")
                .document("aiRuntime")
                .getDocument()
            let enabled = snapshot.data()?["clientEnabled"] as? Bool == true
            NSLog("[AIWishGen] liveGenerationEnabled: \(enabled)")
            return enabled
        } catch {
            NSLog("[AIWishGen] liveGenerationEnabled error: \(error)")
            return false
        }
        #else
        return false
        #endif
    }

    /// Cloud Function aiGenerateWish を呼び出して 3 候補を取得
    /// - 認証: 匿名サインイン経由 (Functions 側で uid 必須)
    /// - quota: ユーザー5/日、グローバル800/日 (Functions 側で enforce)
    /// - エラー時は throw → 呼出元で静的フォールバックに切替
    /// - userContext: 任意の自由テキスト (200字以内, AI 入力に追加するコンテキスト)
    func generate(path: [WishMapNode], userContext: String = "") async throws -> [String] {
        #if canImport(FirebaseAuth)
        await AuthService.shared.signInAnonymouslyIfNeeded()
        guard Auth.auth().currentUser != nil else {
            throw AIWishGenerationError.unavailable
        }
        #endif

        #if canImport(FirebaseFunctions)
        let functions = Functions.functions(region: "asia-northeast1")
        let callable = functions.httpsCallable("aiGenerateWish")
        let appLanguage = UserDefaults.standard.string(forKey: "kotodama.appLanguage") ?? "system"
        let localeIdentifier = LanguageCatalog.effectiveAppLocaleIdentifier(userDefaultValue: appLanguage)
        var payload: [String: Any] = [
            "path": path.map { ["title": $0.title, "prompt": $0.prompt] },
            "locale": localeIdentifier
        ]
        // 任意のコンテキストは 300 字上限で送る (Hick's Law / Context Rot 回避)
        let trimmedContext = userContext
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(300)
        if !trimmedContext.isEmpty {
            payload["userContext"] = String(trimmedContext)
        }
        let result: HTTPSCallableResult
        do {
            NSLog("[AIWishGen] calling aiGenerateWish with path: \(payload)")
            result = try await callable.call(payload)
            NSLog("[AIWishGen] aiGenerateWish success: \(result.data)")
        } catch let error as NSError {
            NSLog("[AIWishGen] aiGenerateWish FAILED: domain=\(error.domain) code=\(error.code) localizedDescription=\(error.localizedDescription) userInfo=\(error.userInfo)")
            // Firebase Functions エラーコード判定
            let code = FunctionsErrorCode(rawValue: error.code)
            if code == .resourceExhausted {
                let info = error.userInfo[FunctionsErrorDetailsKey] as? [String: Any]
                let canWatchAd = (info?["canWatchAd"] as? Bool) ?? false
                let reason = info?["reason"] as? String
                if reason == "global_quota" {
                    throw AIWishGenerationError.budgetEmergencyStop
                }
                throw AIWishGenerationError.quotaExceeded(canWatchAd: canWatchAd)
            }
            throw AIWishGenerationError.unavailable
        }

        guard let dict = result.data as? [String: Any],
              let candidates = dict["candidates"] as? [String],
              !candidates.isEmpty else {
            throw AIWishGenerationError.invalidResponse
        }
        return candidates.prefix(3).map(Self.normalizeCandidate)
        #else
        throw AIWishGenerationError.unavailable
        #endif
    }

    private static func normalizeCandidate(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let appLanguage = UserDefaults.standard.string(forKey: "kotodama.appLanguage") ?? "system"
        let localeIdentifier = LanguageCatalog.effectiveAppLocaleIdentifier(userDefaultValue: appLanguage)
        if !localeIdentifier.hasPrefix("ja") {
            let punctuation = CharacterSet(charactersIn: ".!?。！？")
            if trimmed.unicodeScalars.last.map({ punctuation.contains($0) }) == true {
                return trimmed
            }
            return "\(trimmed)."
        }

        // 末尾記号を一旦剥がす
        var t = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "。.!！？\n\r 　"))

        // 文末「したい」連結を全パターン除去 (最大 4 ループで連結を完全に解す)
        for _ in 0..<4 {
            let before = t
            // 1. 末尾 「(語尾)したい(と思います|と思う|と思って(い|る)|です|でしょう)?」 を削除
            if let r = t.range(
                of: "したい(?:と思います|と思う|と思っている|と思って|です|でしょう)?$",
                options: .regularExpression
            ) {
                t = String(t[..<r.lowerBound])
            }
            // 2. 末尾の句点・空白を再度トリム
            t = t.trimmingCharacters(in: CharacterSet(charactersIn: "。.!！？\n\r 　"))
            // 3. 末尾が「し」「いし」「をし」など中途半端な連結なら削除
            if let r = t.range(of: "(?:を|に|が|は|も|と)?[しじ]$", options: .regularExpression) {
                t = String(t[..<r.lowerBound])
            }
            // 4. 重複したパターン (例: 「思います思います」) を1つに
            t = t.replacingOccurrences(of: "思います思います", with: "思います")
                 .replacingOccurrences(of: "信じます信じます", with: "信じます")
                 .replacingOccurrences(of: "できますできます", with: "できます")
            t = t.trimmingCharacters(in: CharacterSet(charactersIn: "、,，。.!！？\n\r 　"))
            if t == before { break }
        }

        guard t.count >= 4 else { return "" }
        return "\(t)。"
    }
}
