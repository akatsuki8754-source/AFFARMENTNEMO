//
//  AIWishGenerationService.swift
//  Phase 3 Gemini 本接続。Cloud Functions 側の明示フラグが ON の時だけ生成する。
//

import Foundation

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

enum AIWishGenerationError: Error {
    case unavailable
    case invalidResponse
}

@MainActor
final class AIWishGenerationService {
    static let shared = AIWishGenerationService()
    private init() {}

    private let endpoint = URL(string: "https://asia-northeast1-kotodama-86a14.cloudfunctions.net/aiGenerateWish")!

    func liveGenerationEnabled() async -> Bool {
        #if canImport(FirebaseFirestore)
        do {
            let snapshot = try await Firestore.firestore()
                .collection("system")
                .document("aiRuntime")
                .getDocument()
            return snapshot.data()?["clientEnabled"] as? Bool == true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    func generate(path: [WishMapNode]) async throws -> [String] {
        #if canImport(FirebaseAuth)
        await AuthService.shared.signInAnonymouslyIfNeeded()
        guard let user = Auth.auth().currentUser else { throw AIWishGenerationError.unavailable }
        let token = try await user.getIDToken()
        #else
        let token = ""
        #endif

        let payload: [String: Any] = [
            "data": [
                "path": path.map { ["title": $0.title, "prompt": $0.prompt] }
            ]
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw AIWishGenerationError.unavailable
        }

        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let result = object?["result"] as? [String: Any],
           let candidates = result["candidates"] as? [String],
           !candidates.isEmpty {
            return candidates.prefix(3).map(Self.normalizeCandidate)
        }
        throw AIWishGenerationError.invalidResponse
    }

    private static func normalizeCandidate(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
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
