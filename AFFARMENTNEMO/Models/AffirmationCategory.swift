//
//  AffirmationCategory.swift
//  カテゴリ列挙とテンプレート定義 (UX v4 §2.3)
//

import Foundation

enum AffirmationCategoryKind: String, CaseIterable, Identifiable {
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

/// オンボーディング・追加画面で使うテンプレタグ (UX v4 §2.3)
struct AffirmationTemplate: Identifiable, Hashable {
    let id: String
    let nameKey: String        // i18n キー
    let exampleKey: String     // 例文キー
    let placeholderText: String // ひな型 (タップで入力欄に挿入)
    let internalMode: String   // "affirmation" | "value" | "ifThen"
    let category: AffirmationCategoryKind
    let isStarred: Bool        // ⭐ = 効果が高い (Steele/Gollwitzer)

    static let all: [AffirmationTemplate] = [
        AffirmationTemplate(
            id: "narikatai",
            nameKey: "tpl.narikatai.name",
            exampleKey: "tpl.narikatai.example",
            placeholderText: "私は",
            internalMode: "affirmation",
            category: .selfAffirm,
            isStarred: false
        ),
        AffirmationTemplate(
            id: "kanaetai",
            nameKey: "tpl.kanaetai.name",
            exampleKey: "tpl.kanaetai.example",
            placeholderText: "を達成したい",
            internalMode: "affirmation",
            category: .goal,
            isStarred: false
        ),
        AffirmationTemplate(
            id: "taisetsu",
            nameKey: "tpl.taisetsu.name",
            exampleKey: "tpl.taisetsu.example",
            placeholderText: "を大切にしたい",
            internalMode: "value",
            category: .values,
            isStarred: true
        ),
        AffirmationTemplate(
            id: "ifthen",
            nameKey: "tpl.ifthen.name",
            exampleKey: "tpl.ifthen.example",
            placeholderText: "もし、したら、する",
            internalMode: "ifThen",
            category: .habit,
            isStarred: true
        ),
        AffirmationTemplate(
            id: "hagemashi",
            nameKey: "tpl.hagemashi.name",
            exampleKey: "tpl.hagemashi.example",
            placeholderText: "今日も",
            internalMode: "affirmation",
            category: .selfAffirm,
            isStarred: false
        ),
        AffirmationTemplate(
            id: "biz",
            nameKey: "tpl.biz.name",
            exampleKey: "tpl.biz.example",
            placeholderText: "",
            internalMode: "affirmation",
            category: .plan,
            isStarred: false
        ),
    ]
}
