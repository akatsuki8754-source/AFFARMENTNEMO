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
