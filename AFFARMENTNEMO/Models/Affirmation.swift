//
//  Affirmation.swift
//  3モード(内部分類のみ、UIには出さない) + カテゴリ管理
//  仕様: 02_開発仕様書_v3 §2.2 / 04_アファメーション科学的根拠 / 05_UXフロー §0.2
//

import Foundation
import SwiftData

@Model
final class Affirmation {
    @Attribute(.unique) var id: UUID
    var text: String
    var internalMode: String     // "affirmation" | "value" | "ifThen"  (UIには出さない)
    var templateUsed: String?    // 「なりたい自分」「習慣のキッカケ」など (分析用)
    var category: String         // "goal" | "habit" | "selfAffirm" | "plan" | "concern" | "values" | "custom"
    var customCategoryName: String?

    // モード2 (価値アファメ) 用 - MVPでは未使用、後方互換のため保持
    var coreValues: [String]
    var valueReason: String?

    // モード3 (If-Thenプラン) 用
    var ifTrigger: String?
    var thenAction: String?

    // 通知スケジュール
    var morningEnabled: Bool
    var eveningEnabled: Bool

    // 統計
    var readCount: Int
    var lastReadAt: Date?
    var currentStreakDays: Int
    var longestStreakDays: Int

    // メタデータ
    var createdAt: Date
    var updatedAt: Date
    var orderIndex: Int
    var isActive: Bool

    // 録音 (ユーザー要望: 自分の声で再生)
    /// Documents/recordings/ 配下のファイル名 (m4a)。nil = 未録音。
    var recordingFileName: String?

    // ホームのルーティンに含めるか (\u30db\u30fc\u30e0\u8aad\u307f\u4e0a\u3052\u30bb\u30c3\u30c8 \u30aa\u30f3/\u30aa\u30d5)
    var includeInRoutine: Bool = true

    // \u8a00\u8449\u306e\u671f\u9650 (Phase 2): \u671f\u9593\u3092\u8a2d\u5b9a\u3057\u3066\u8d85\u3048\u305f\u3089\u81ea\u52d5\u3067\u30eb\u30fc\u30c6\u30a3\u30f3\u9664\u5916
    var startDate: Date?
    var endDate: Date?
    /// \u66dc\u65e5\u30d3\u30c3\u30c8\u30de\u30b9\u30af (\u65e5=1, \u6708=2, \u706b=4, \u6c34=8, \u6728=16, \u91d1=32, \u571f=64) \u30c7\u30d5\u30a9\u30eb\u30c8 127 (\u5168\u66dc\u65e5)
    var weekdayMask: Int = 127

    /// \u73fe\u5728\u8aad\u307f\u4e0a\u3052\u5bfe\u8c61\u304b? (\u671f\u9650 + \u66dc\u65e5\u8003\u616e)
    func isAvailableNow(_ now: Date = Date()) -> Bool {
        if let s = startDate, now < s { return false }
        if let e = endDate, now > e { return false }
        let weekday = Calendar.current.component(.weekday, from: now) // 1=Sun
        let mask = 1 << (weekday - 1)
        return (weekdayMask & mask) != 0
    }

    /// \u30eb\u30fc\u30c6\u30a3\u30f3\u304b\u3089\u9664\u5916\u3055\u308c\u3066\u3044\u308b\u7406\u7531
    enum ExclusionReason {
        case included        // \u542b\u307e\u308c\u308b
        case excludedManually
        case beforeStart
        case afterEnd
        case wrongWeekday
    }

    func exclusionReason(_ now: Date = Date()) -> ExclusionReason {
        if !includeInRoutine { return .excludedManually }
        if let s = startDate, now < s { return .beforeStart }
        if let e = endDate, now > e { return .afterEnd }
        let weekday = Calendar.current.component(.weekday, from: now)
        if (weekdayMask & (1 << (weekday - 1))) == 0 { return .wrongWeekday }
        return .included
    }

    init(
        text: String,
        internalMode: String = "affirmation",
        templateUsed: String? = nil,
        category: String = "custom",
        customCategoryName: String? = nil,
        coreValues: [String] = [],
        valueReason: String? = nil,
        ifTrigger: String? = nil,
        thenAction: String? = nil,
        morningEnabled: Bool = true,
        eveningEnabled: Bool = false,
        orderIndex: Int = 0
    ) {
        self.id = UUID()
        self.text = text
        self.internalMode = internalMode
        self.templateUsed = templateUsed
        self.category = category
        self.customCategoryName = customCategoryName
        self.coreValues = coreValues
        self.valueReason = valueReason
        self.ifTrigger = ifTrigger
        self.thenAction = thenAction
        self.morningEnabled = morningEnabled
        self.eveningEnabled = eveningEnabled
        self.readCount = 0
        self.lastReadAt = nil
        self.currentStreakDays = 0
        self.longestStreakDays = 0
        self.createdAt = Date()
        self.updatedAt = Date()
        self.orderIndex = orderIndex
        self.isActive = true
    }
}
