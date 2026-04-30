//
//  KnowledgeMap.swift
//  AI短冊作成のための「知識マップ」決定木 (3択ずつ進む)
//  仕様: 00_コトダマ_AI短冊機能_完全実装仕様書 §12-§16
//
//  Phase 1.5 では UI のみ実装し、AI 生成は静的サンプルを返す。
//  Phase 2 で Cloud Functions + Gemini API に置き換え。
//

import Foundation

/// 決定木のノード
struct WishMapNode: Identifiable, Hashable {
    let id: String
    let title: String      // ノードのタイトル (3択の問い)
    let prompt: String     // システムプロンプト用キーワード
    let children: [WishMapNode]
}

enum KnowledgeMap {

    /// ルートノード (3択)
    static let root: WishMapNode = WishMapNode(
        id: "root",
        title: "いま、何を願いたい?",
        prompt: "root",
        children: [achievement, improvement, balance]
    )

    // MARK: - 達成型 (受験/仕事/目標)
    static let achievement: WishMapNode = WishMapNode(
        id: "achievement",
        title: "達成したい",
        prompt: "achievement",
        children: [
            WishMapNode(id: "ach.exam", title: "資格・試験に合格", prompt: "exam_passing", children: [
                WishMapNode(id: "ach.exam.1m", title: "1ヶ月以内", prompt: "deadline_1m", children: []),
                WishMapNode(id: "ach.exam.3m", title: "3ヶ月以内", prompt: "deadline_3m", children: []),
                WishMapNode(id: "ach.exam.1y", title: "今年中", prompt: "deadline_1y", children: []),
            ]),
            WishMapNode(id: "ach.career", title: "仕事で結果を出す", prompt: "career_success", children: [
                WishMapNode(id: "ach.career.sales", title: "営業成績", prompt: "career_sales", children: []),
                WishMapNode(id: "ach.career.promo", title: "昇進・昇格", prompt: "career_promotion", children: []),
                WishMapNode(id: "ach.career.skill", title: "スキル習得", prompt: "career_skill", children: []),
            ]),
            WishMapNode(id: "ach.dream", title: "夢を実現する", prompt: "dream", children: [
                WishMapNode(id: "ach.dream.startup", title: "起業・独立", prompt: "dream_startup", children: []),
                WishMapNode(id: "ach.dream.travel", title: "旅行・海外移住", prompt: "dream_travel", children: []),
                WishMapNode(id: "ach.dream.art", title: "創作・表現", prompt: "dream_art", children: []),
            ]),
        ]
    )

    // MARK: - 改善型 (健康/ダイエット/習慣)
    static let improvement: WishMapNode = WishMapNode(
        id: "improvement",
        title: "改善したい",
        prompt: "improvement",
        children: [
            WishMapNode(id: "imp.health", title: "健康・体力", prompt: "health", children: [
                WishMapNode(id: "imp.health.weight", title: "ダイエット", prompt: "health_diet", children: []),
                WishMapNode(id: "imp.health.exercise", title: "運動習慣", prompt: "health_exercise", children: []),
                WishMapNode(id: "imp.health.sleep", title: "睡眠改善", prompt: "health_sleep", children: []),
            ]),
            WishMapNode(id: "imp.habit", title: "習慣を変える", prompt: "habit", children: [
                WishMapNode(id: "imp.habit.quit", title: "やめたい習慣", prompt: "habit_quit", children: []),
                WishMapNode(id: "imp.habit.start", title: "始めたい習慣", prompt: "habit_start", children: []),
                WishMapNode(id: "imp.habit.morning", title: "朝活・モーニングルーティン", prompt: "habit_morning", children: []),
            ]),
            WishMapNode(id: "imp.relation", title: "人間関係を改善", prompt: "relationship", children: [
                WishMapNode(id: "imp.relation.family", title: "家族との関係", prompt: "rel_family", children: []),
                WishMapNode(id: "imp.relation.partner", title: "パートナー・恋愛", prompt: "rel_partner", children: []),
                WishMapNode(id: "imp.relation.colleague", title: "職場・友人", prompt: "rel_colleague", children: []),
            ]),
        ]
    )

    // MARK: - 整える型 (メンタル/価値観/感謝)
    static let balance: WishMapNode = WishMapNode(
        id: "balance",
        title: "心を整えたい",
        prompt: "balance",
        children: [
            WishMapNode(id: "bal.mental", title: "メンタルの安定", prompt: "mental", children: [
                WishMapNode(id: "bal.mental.anxiety", title: "不安・心配を手放す", prompt: "mental_anxiety", children: []),
                WishMapNode(id: "bal.mental.confidence", title: "自信を持つ", prompt: "mental_confidence", children: []),
                WishMapNode(id: "bal.mental.calm", title: "穏やかさを保つ", prompt: "mental_calm", children: []),
            ]),
            WishMapNode(id: "bal.value", title: "価値観を確認", prompt: "value", children: [
                WishMapNode(id: "bal.value.family", title: "家族を大切にする", prompt: "value_family", children: []),
                WishMapNode(id: "bal.value.growth", title: "成長を続ける", prompt: "value_growth", children: []),
                WishMapNode(id: "bal.value.contribution", title: "誰かの役に立つ", prompt: "value_contribution", children: []),
            ]),
            WishMapNode(id: "bal.gratitude", title: "感謝・幸せを感じる", prompt: "gratitude", children: [
                WishMapNode(id: "bal.gratitude.daily", title: "日常の小さな幸せ", prompt: "gratitude_daily", children: []),
                WishMapNode(id: "bal.gratitude.people", title: "周りの人への感謝", prompt: "gratitude_people", children: []),
                WishMapNode(id: "bal.gratitude.self", title: "自分自身を認める", prompt: "gratitude_self", children: []),
            ]),
        ]
    )

    /// path → AI生成候補 (Phase 1.5: 静的サンプル、Phase 2: Gemini)
    static func generateCandidates(for path: [WishMapNode]) -> [String] {
        let last = path.last?.prompt ?? ""
        let lastTitle = path.last?.title ?? ""
        // 簡易テンプレ生成 (Phase 2 で Gemini に置き換え)
        switch last {
        case "exam_passing", "deadline_1m", "deadline_3m", "deadline_1y":
            return [
                "私は試験に必要な集中力と理解力を毎日育てている。きっと合格できる。",
                "もし朝起きたら、まず30分だけ問題を解く。これを毎日続ける。",
                "合格は通過点。学んだ知識で誰かの役に立つ自分になる。"
            ]
        case "career_sales", "career_promotion", "career_skill":
            return [
                "私は約束した数字を必ず達成する。今日もできることを淡々と積み上げる。",
                "もし会議が始まったら、まず3つの選択肢を準備して臨む。",
                "成果は誰かの困りごとを解いた結果。今日も誠実に向き合う。"
            ]
        case "health_diet", "health_exercise", "health_sleep":
            return [
                "私は自分の体を大切にできる人だ。今日選ぶものが明日の自分を作る。",
                "もし帰宅したら、まず10分だけ体を動かす。続けることが力になる。",
                "健康は権利ではなく、選び続けた結果。今日もその選択をする。"
            ]
        case "habit_quit", "habit_start", "habit_morning":
            return [
                "私は意志ではなく仕組みで習慣を作る。決めたことを淡々と続ける。",
                "もし朝起きたら、コップ一杯の水を飲んでから始める。",
                "完璧でなくていい。続いていることが価値だ。"
            ]
        case "rel_family", "rel_partner", "rel_colleague":
            return [
                "私は家族・大切な人との時間を、今日も丁寧に作る。",
                "もし相手が話し始めたら、まず最後まで聴く。それから自分の意見を伝える。",
                "信頼は積み上げ。小さな約束を守り続ける。"
            ]
        case "mental_anxiety", "mental_confidence", "mental_calm":
            return [
                "私は不安と共に進む人だ。完璧を求めず、進む方向だけ確認する。",
                "もし不安になったら、深呼吸を3回してから次の一歩を考える。",
                "心が揺れる時こそ、自分に優しく。それでも前を向ける。"
            ]
        case "value_family", "value_growth", "value_contribution":
            return [
                "私は家族との時間を最優先にできる人でありたい。",
                "成長とは、できなかったことが少しずつできるようになること。",
                "誰かの役に立てることが、自分の生きる手応えになる。"
            ]
        case "gratitude_daily", "gratitude_people", "gratitude_self":
            return [
                "今日も歩けた。食べられた。眠れる。それだけで十分ありがたい。",
                "周りの人がいてくれるから、私は今日も笑える。",
                "今日もよくやった。明日も歩ける自分でいよう。"
            ]
        default:
            return [
                "私は\(lastTitle)に向かって、今日もできる一歩を踏み出す。",
                "もし\(lastTitle)について悩んだら、深呼吸して目の前のことに集中する。",
                "\(lastTitle)は通過点。今日も自分らしくあろう。"
            ]
        }
    }
}
