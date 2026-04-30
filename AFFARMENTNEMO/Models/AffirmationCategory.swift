//
//  AffirmationCategory.swift
//  カテゴリ列挙とテンプレート定義 (UX v4 §2.3)
//

import Foundation

enum AffirmationCategoryKind: String, CaseIterable, Identifiable {
    case wish       // 願い (Wish Tree v2)
    case goal       // 目標
    case habit      // 習慣
    case selfAffirm // 自己肯定
    case plan       // 計画
    case concern    // 懸念
    case values     // 価値
    case custom     // カスタム

    var id: String { rawValue }

    var localizedKey: String {
        switch self {
        case .wish: "category.wish"
        case .goal: "category.goal"
        case .habit: "category.habit"
        case .selfAffirm: "category.selfAffirm"
        case .plan: "category.plan"
        case .concern: "category.concern"
        case .values: "category.values"
        case .custom: "category.custom"
        }
    }
}

/// 七夕5色短冊 (Wish Tree v2 §10.3 — 中国五行に基づく文化的根拠)
enum TanzakuColor: String, CaseIterable, Identifiable, Codable {
    case blue   // 青/緑 — 木 — 仁・人間力向上
    case red    // 赤    — 火 — 礼・家族への感謝
    case yellow // 黄    — 土 — 信・友情
    case white  // 白    — 金 — 義・規律ある生活
    case purple // 紫    — 水 — 智・学業/仕事

    var id: String { rawValue }

    /// 短冊の表示用 RGB (淡め、テキストが読みやすい飽和度)
    var hex: String {
        switch self {
        case .blue: "#A8C8E8"   // 淡青
        case .red: "#F4B5B5"    // 淡赤
        case .yellow: "#F4E4A8" // 淡黄
        case .white: "#F5F2EC"  // 生成
        case .purple: "#C8B5DB" // 淡紫
        }
    }

    var meaningKey: String {
        switch self {
        case .blue: "tanzaku.blue.meaning"     // 自己成長・人間関係
        case .red: "tanzaku.red.meaning"       // 家族・感謝
        case .yellow: "tanzaku.yellow.meaning" // 友情・信頼
        case .white: "tanzaku.white.meaning"   // 規律・健康
        case .purple: "tanzaku.purple.meaning" // 仕事・学業・夢
        }
    }
}

/// オンボーディング・追加画面で使うテンプレタグ (UX v4 §2.3)
struct AffirmationTemplate: Identifiable, Hashable {
    let id: String
    let nameKey: String        // i18n キー
    let exampleKey: String     // 例文キー
    let placeholderText: String // ひな型 (タップで入力欄に挿入)
    let internalMode: String   // "affirmation" | "value" | "ifThen"
    let category: AffirmationCategoryKind
    let isStarred: Bool        // ⭐ = 効果が高い (Steele/Gollwitzer)

    /// 穴埋めで「ほぼ完成」する完全文ひな型 (v2 ユーザフィードバック反映)
    /// `[___]` 部分が穴で、ユーザはそこだけ埋めれば自然な文になる
    static let all: [AffirmationTemplate] = [
        AffirmationTemplate(
            id: "narikatai",
            nameKey: "tpl.narikatai.name",
            exampleKey: "tpl.narikatai.example",
            placeholderText: "私は[___]な人になっていく。毎日少しずつ、確実に。",
            internalMode: "affirmation",
            category: .selfAffirm,
            isStarred: false
        ),
        AffirmationTemplate(
            id: "kanaetai",
            nameKey: "tpl.kanaetai.name",
            exampleKey: "tpl.kanaetai.example",
            placeholderText: "今年中に[___]を達成する。そのために、今日できる一歩を踏み出す。",
            internalMode: "affirmation",
            category: .goal,
            isStarred: false
        ),
        AffirmationTemplate(
            id: "taisetsu",
            nameKey: "tpl.taisetsu.name",
            exampleKey: "tpl.taisetsu.example",
            placeholderText: "[___]を大切にしたい。だから、今日の選択を丁寧にする。",
            internalMode: "value",
            category: .values,
            isStarred: true
        ),
        AffirmationTemplate(
            id: "ifthen",
            nameKey: "tpl.ifthen.name",
            exampleKey: "tpl.ifthen.example",
            placeholderText: "もし[___]したら、[___]する。これを毎日続ける。",
            internalMode: "ifThen",
            category: .habit,
            isStarred: true
        ),
        AffirmationTemplate(
            id: "hagemashi",
            nameKey: "tpl.hagemashi.name",
            exampleKey: "tpl.hagemashi.example",
            placeholderText: "今日もよくやった。[___]できた自分を認める。明日も歩ける。",
            internalMode: "affirmation",
            category: .selfAffirm,
            isStarred: false
        ),
        AffirmationTemplate(
            id: "negai",
            nameKey: "tpl.negai.name",
            exampleKey: "tpl.negai.example",
            placeholderText: "今年は[___]な日々を過ごせますように。健やかに、笑顔で。",
            internalMode: "affirmation",
            category: .wish,
            isStarred: false
        ),
    ]
}
