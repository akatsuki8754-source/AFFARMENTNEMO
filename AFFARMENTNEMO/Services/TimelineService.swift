//
//  TimelineService.swift
//  流すだけタイムライン Firestore 連携
//  仕様: MASTER §14, §21 (timelineRooms/{lang}/posts, TTL on expireAt)
//

import Foundation

struct TimelinePost: Identifiable, Hashable {
    let id: String
    let authorUid: String
    let text: String
    let languageRoom: String
    let createdAt: Date
    let expireAt: Date
    var reportCount: Int
    var isHidden: Bool
}

#if canImport(FirebaseFirestore) && canImport(FirebaseAuth)
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class TimelineService {
    static let shared = TimelineService()
    private init() {}

    /// デバイスロケールから言語ルーム判定 (MASTER §14.8)
    static func defaultLanguageRoom(_ locale: Locale = .current) -> String {
        switch locale.language.languageCode?.identifier {
        case "ja": return "ja_JP"
        case "en": return "en"
        case "zh":
            let region = locale.language.region?.identifier ?? ""
            if region == "TW" || region == "HK" { return "zh_TW" }
            return "zh_CN"
        case "ko": return "ko_KR"
        default: return "en"
        }
    }

    private var db: Firestore { Firestore.firestore() }

    /// PII (URL/email/phone) パターン拒否 (MASTER §14.6)
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
        return .ok
    }

    enum ValidationResult: Equatable {
        case ok
        case error(String)
    }

    /// 24時間以内の投稿をストリーム購読
    func subscribePosts(room: String, limit: Int = 20,
                        onUpdate: @escaping ([TimelinePost]) -> Void) -> ListenerRegistration {
        let ref = db.collection("timelineRooms").document(room).collection("posts")
            .whereField("isHidden", isEqualTo: false)
            .whereField("expireAt", isGreaterThan: Timestamp(date: Date()))
            .order(by: "expireAt", descending: false)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
        return ref.addSnapshotListener { snapshot, _ in
            guard let docs = snapshot?.documents else { onUpdate([]); return }
            let posts = docs.compactMap { Self.decode($0) }
            onUpdate(posts)
        }
    }

    /// 投稿
    func post(text: String, room: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "TimelineService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        let now = Date()
        let expireAt = Calendar.current.date(byAdding: .hour, value: 24, to: now) ?? now.addingTimeInterval(86400)
        let data: [String: Any] = [
            "authorUid": uid,
            "text": text,
            "languageRoom": room,
            "createdAt": Timestamp(date: now),
            "expireAt": Timestamp(date: expireAt),
            "reportCount": 0,
            "isHidden": false,
            "reportedBy": [String](),
        ]
        try await db.collection("timelineRooms").document(room).collection("posts")
            .addDocument(data: data)
    }

    /// 通報
    func report(postId: String, room: String, reason: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db.collection("reports").addDocument(data: [
            "reporterUid": uid,
            "targetType": "post",
            "targetId": postId,
            "targetRoom": room,
            "reason": reason,
            "createdAt": Timestamp(date: Date()),
        ])
        // クライアント側で即時非表示用にreportedByへ自身のUIDを追加
        let postRef = db.collection("timelineRooms").document(room).collection("posts").document(postId)
        try await postRef.updateData([
            "reportedBy": FieldValue.arrayUnion([uid]),
            "reportCount": FieldValue.increment(Int64(1)),
        ])
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
        return TimelinePost(
            id: doc.documentID,
            authorUid: authorUid,
            text: text,
            languageRoom: room,
            createdAt: createdAt,
            expireAt: expireAt,
            reportCount: (data["reportCount"] as? Int) ?? 0,
            isHidden: (data["isHidden"] as? Bool) ?? false
        )
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
}
#endif
