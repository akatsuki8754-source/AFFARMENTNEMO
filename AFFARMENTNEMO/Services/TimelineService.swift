//
//  TimelineService.swift
//  流すだけタイムライン Firestore 連携
//  仕様: MASTER §14, §21 (timelineRooms/{lang}/posts, TTL on expireAt)
//

import Foundation
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

struct TimelinePost: Identifiable, Hashable {
    let id: String
    let authorUid: String
    let text: String
    let languageRoom: String
    let createdAt: Date
    let expireAt: Date
    var reportCount: Int
    var isHidden: Bool
    var reactionLike: Int
    var reactionHeart: Int
    var reactionPeace: Int
    var myReaction: String?

    /// 自分の投稿か (現在の anonymous uid と一致)
    var isMine: Bool {
        #if canImport(FirebaseAuth)
        return authorUid == Auth.auth().currentUser?.uid
        #else
        return false
        #endif
    }
}

#if canImport(FirebaseFirestore) && canImport(FirebaseAuth)
import FirebaseFirestore
import FirebaseAuth
#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

@MainActor
final class TimelineService {
    static let shared = TimelineService()
    private init() {}

    /// デバイスロケールから言語ルーム判定 (MASTER §14.8)
    static func defaultLanguageRoom(_ locale: Locale = .current) -> String {
        LanguageCatalog.defaultTimelineRoom(for: locale)
    }

    private var db: Firestore { Firestore.firestore() }

    #if canImport(FirebaseFunctions)
    private var functions: Functions { Functions.functions(region: "asia-northeast1") }
    #endif

    /// PII (URL/email/phone) + 不適切コンテンツ パターン拒否 (MASTER §14.6 + Apple Guideline 1.2)
    static func validatePost(_ text: String) -> ValidationResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .error("テキストを入力してください") }
        if trimmed.count > 100 { return .error("100文字以内で入力してください") }
        if trimmed.split(whereSeparator: \.isNewline).count > 5 { return .error("5行以内で入力してください") }

        let piiPatterns = [
            #"https?://|www\.|\.com|\.jp|\.net|\.org"#,
            #"[\w.-]+@[\w.-]+\.\w+"#,
            #"\d{2,4}[-_ ]?\d{2,4}[-_ ]?\d{4}"#,
            #"(LINE|ライン|line)\s*(ID|id)\s*[:：]"#,
        ]
        for p in piiPatterns {
            if trimmed.range(of: p, options: [.regularExpression, .caseInsensitive]) != nil {
                return .error("URL・連絡先などは投稿できません")
            }
        }
        // 不適切コンテンツチェック (Apple 1.2)
        if case .blocked(let reason) = ContentModerationService.check(trimmed) {
            return .error(reason)
        }
        return .ok
    }

    enum ValidationResult: Equatable {
        case ok
        case error(String)
    }

    /// ユーザー要望: ロケーションごとに最新100件のみ表示。
    /// 期限切れはサーバ側 + クライアント側でも二重フィルタ (24h cleanup バグ対策)。
    func subscribePosts(room: String, limit: Int = 100,
                        onUpdate: @escaping ([TimelinePost]) -> Void) -> ListenerRegistration {
        let ref = db.collection("timelineRooms").document(room).collection("posts")
            .whereField("isHidden", isEqualTo: false)
            .whereField("expireAt", isGreaterThan: Timestamp(date: Date()))
            .order(by: "expireAt", descending: false)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
        return ref.addSnapshotListener { snapshot, _ in
            guard let docs = snapshot?.documents else { onUpdate([]); return }
            let now = Date()
            // クライアント側でも expireAt 再チェック (古いキャッシュ対策)
            let posts = docs
                .compactMap { Self.decode($0) }
                .filter { $0.expireAt > now }
                .prefix(100)
            onUpdate(Array(posts))
        }
    }

    /// 投稿
    func post(text: String, room: String) async throws {
        await AuthService.shared.signInAnonymouslyIfNeeded()
        guard Auth.auth().currentUser?.uid != nil else {
            throw NSError(domain: "TimelineService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        #if canImport(FirebaseFunctions)
        let callable = functions.httpsCallable("submitTimelinePost")
        _ = try await callable.call([
            "text": text.trimmingCharacters(in: .whitespacesAndNewlines),
            "room": room,
        ])
        #else
        let now = Date()
        let expireAt = Calendar.current.date(byAdding: .hour, value: 24, to: now) ?? now.addingTimeInterval(86400)
        let data: [String: Any] = [
            "authorUid": Auth.auth().currentUser?.uid ?? "",
            "text": text,
            "languageRoom": room,
            "createdAt": Timestamp(date: now),
            "expireAt": Timestamp(date: expireAt),
            "reportCount": 0,
            "isHidden": false,
            "reportedBy": [String](),
            "reactionLike": 0,
            "reactionHeart": 0,
            "reactionPeace": 0,
            "reactedBy": [String: String](),
        ]
        try await db.collection("timelineRooms").document(room).collection("posts")
            .addDocument(data: data)
        #endif
    }

    /// 自分の投稿を即時削除 (Apple 1.2 「ユーザーがフィードから即時削除」)
    func deleteOwnPost(postId: String, room: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = db.collection("timelineRooms").document(room).collection("posts").document(postId)
        let snap = try await ref.getDocument()
        guard let data = snap.data(), data["authorUid"] as? String == uid else {
            throw NSError(domain: "TimelineService", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Not your post"])
        }
        // 物理削除はセキュリティルールで禁止 (allow delete: false) のため、isHidden=true で論理削除
        try await ref.updateData(["isHidden": true])
    }

    /// 通報
    func report(postId: String, room: String, reason: String) async throws {
        await AuthService.shared.signInAnonymouslyIfNeeded()
        guard Auth.auth().currentUser?.uid != nil else { return }
        #if canImport(FirebaseFunctions)
        let callable = functions.httpsCallable("reportPost")
        _ = try await callable.call([
            "postId": postId,
            "room": room,
            "reason": reason,
        ])
        #else
        throw NSError(domain: "TimelineService", code: -3,
                      userInfo: [NSLocalizedDescriptionKey: "Report requires Firebase Functions"])
        #endif
    }

    func fetchPosts(room: String, limit: Int = 100) async throws -> [TimelinePost] {
        await AuthService.shared.signInAnonymouslyIfNeeded()
        let now = Date()
        let snap = try await db.collection("timelineRooms").document(room).collection("posts")
            .whereField("isHidden", isEqualTo: false)
            .whereField("expireAt", isGreaterThan: Timestamp(date: now))
            .order(by: "expireAt", descending: false)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snap.documents
            .compactMap { Self.decode($0) }
            .filter { $0.expireAt > now }
    }

    func toggleReaction(post: TimelinePost, reaction: String) async throws {
        await AuthService.shared.signInAnonymouslyIfNeeded()
        guard let uid = Auth.auth().currentUser?.uid else { return }
        #if canImport(FirebaseFunctions)
        let callable = functions.httpsCallable("reactToPost")
        let nextReaction = post.myReaction == reaction ? "none" : reaction
        _ = try await callable.call([
            "postId": post.id,
            "room": post.languageRoom,
            "reaction": nextReaction,
        ])
        #else
        let ref = db.collection("timelineRooms").document(post.languageRoom).collection("posts").document(post.id)
        try await db.runTransaction { transaction, errorPointer in
            do {
                let snapshot = try transaction.getDocument(ref)
                guard let data = snapshot.data() else { return nil }
                var reactedBy = data["reactedBy"] as? [String: String] ?? [:]
                let current = reactedBy[uid]
                var updates: [String: Any] = [:]
                if let current {
                    updates[Self.reactionField(current)] = FieldValue.increment(Int64(-1))
                }
                if current == reaction {
                    reactedBy.removeValue(forKey: uid)
                } else {
                    reactedBy[uid] = reaction
                    updates[Self.reactionField(reaction)] = FieldValue.increment(Int64(1))
                }
                updates["reactedBy"] = reactedBy
                transaction.updateData(updates, forDocument: ref)
            } catch let error as NSError {
                errorPointer?.pointee = error
            }
            return nil
        }
        #endif
    }

    private static func reactionField(_ reaction: String) -> String {
        switch reaction {
        case "heart": return "reactionHeart"
        case "peace": return "reactionPeace"
        default: return "reactionLike"
        }
    }

    private static func decode(_ doc: QueryDocumentSnapshot) -> TimelinePost? {
        let data = doc.data()
        guard
            let authorUid = data["authorUid"] as? String,
            let text = data["text"] as? String,
            let room = data["languageRoom"] as? String,
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
            let expireAt = (data["expireAt"] as? Timestamp)?.dateValue()
        else { return nil }
        let reactedBy = data["reactedBy"] as? [String: String] ?? [:]
        return TimelinePost(
            id: doc.documentID,
            authorUid: authorUid,
            text: text,
            languageRoom: room,
            createdAt: createdAt,
            expireAt: expireAt,
            reportCount: numericValue(data["reportCount"]),
            isHidden: (data["isHidden"] as? Bool) ?? false,
            reactionLike: numericValue(data["reactionLike"]),
            reactionHeart: numericValue(data["reactionHeart"]),
            reactionPeace: numericValue(data["reactionPeace"]),
            myReaction: Auth.auth().currentUser.flatMap { reactedBy[$0.uid] }
        )
    }

    private static func numericValue(_ value: Any?) -> Int {
        if let int = value as? Int { return int }
        if let int64 = value as? Int64 { return Int(int64) }
        if let number = value as? NSNumber { return number.intValue }
        return 0
    }
}
#else
// SDK未統合時のスタブ
@MainActor
final class TimelineService {
    static let shared = TimelineService()
    private init() {}
    static func defaultLanguageRoom(_ locale: Locale = .current) -> String { "ja_JP" }
    enum ValidationResult: Equatable {
        case ok
        case error(String)
    }
    static func validatePost(_ text: String) -> ValidationResult { .ok }
    func post(text: String, room: String) async throws {}
    func report(postId: String, room: String, reason: String) async throws {}
    func fetchPosts(room: String, limit: Int = 100) async throws -> [TimelinePost] { [] }
    func toggleReaction(post: TimelinePost, reaction: String) async throws {}
}
#endif
