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
            print("[AIWishGen] liveGenerationEnabled: not signed in")
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
            print("[AIWishGen] liveGenerationEnabled: \(enabled)")
            return enabled
        } catch {
            print("[AIWishGen] liveGenerationEnabled error: \(error)")
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
    func generate(path: [WishMapNode]) async throws -> [String] {
        #if canImport(FirebaseAuth)
        await AuthService.shared.signInAnonymouslyIfNeeded()
        guard Auth.auth().currentUser != nil else {
            throw AIWishGenerationError.unavailable
        }
        #endif

        #if canImport(FirebaseFunctions)
        let functions = Functions.functions(region: "asia-northeast1")
        let callable = functions.httpsCallable("aiGenerateWish")
        let payload: [String: Any] = [
            "path": path.map { ["title": $0.title, "prompt": $0.prompt] }
        ]
        let result: HTTPSCallableResult
        do {
            result = try await callable.call(payload)
        } catch let error as NSError {
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
        // 〜したい / 〜でいたい / 〜になりたい で終わる文は補正不要
        if trimmed.hasSuffix("したい。") ||
           trimmed.hasSuffix("いたい。") ||
           trimmed.hasSuffix("なりたい。") ||
           trimmed.hasSuffix("たい。") {
            return trimmed
        }
        let dropped = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "。.!！"))
        return "\(dropped)したい。"
    }
}
