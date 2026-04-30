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
        children: [achievement, improvement, famousQuotes, balance]
    )

    static let famousQuotes: WishMapNode = WishMapNode(
        id: "famous",
        title: "有名人の言葉を参考にしたい",
        prompt: "famous_quotes",
        children: [
            WishMapNode(id: "famous.business", title: "仕事・挑戦の名言", prompt: "quote_business", children: []),
            WishMapNode(id: "famous.life", title: "人生・生き方の名言", prompt: "quote_life", children: []),
            WishMapNode(id: "famous.sport", title: "努力・勝負の名言", prompt: "quote_sport", children: []),
        ]
    )

    // MARK: - 達成型 (受験/仕事/目標) — 各ノードに 6+ の選択肢を持たせ、同階層内で3択ずつ循環できるように
    static let achievement: WishMapNode = WishMapNode(
        id: "achievement",
        title: "達成したい",
        prompt: "achievement",
        children: [
            WishMapNode(id: "ach.exam", title: "資格・試験に合格", prompt: "exam_passing", children: [
                WishMapNode(id: "ach.exam.1m", title: "1ヶ月以内", prompt: "deadline_1m", children: []),
                WishMapNode(id: "ach.exam.3m", title: "3ヶ月以内", prompt: "deadline_3m", children: []),
                WishMapNode(id: "ach.exam.1y", title: "今年中", prompt: "deadline_1y", children: []),
                WishMapNode(id: "ach.exam.langtoeic", title: "TOEIC・語学試験", prompt: "exam_lang", children: []),
                WishMapNode(id: "ach.exam.licence", title: "国家資格", prompt: "exam_license", children: []),
                WishMapNode(id: "ach.exam.entrance", title: "受験 (高校/大学/院)", prompt: "exam_entrance", children: []),
            ]),
            WishMapNode(id: "ach.career", title: "仕事で結果を出す", prompt: "career_success", children: [
                WishMapNode(id: "ach.career.sales", title: "営業成績", prompt: "career_sales", children: []),
                WishMapNode(id: "ach.career.promo", title: "昇進・昇格", prompt: "career_promotion", children: []),
                WishMapNode(id: "ach.career.skill", title: "スキル習得", prompt: "career_skill", children: []),
                WishMapNode(id: "ach.career.transfer", title: "転職を成功させる", prompt: "career_transfer", children: []),
                WishMapNode(id: "ach.career.team", title: "チームをまとめる", prompt: "career_team", children: []),
                WishMapNode(id: "ach.career.salary", title: "年収を上げる", prompt: "career_salary", children: []),
            ]),
            WishMapNode(id: "ach.dream", title: "夢を実現する", prompt: "dream", children: [
                WishMapNode(id: "ach.dream.startup", title: "起業・独立", prompt: "dream_startup", children: []),
                WishMapNode(id: "ach.dream.travel", title: "旅行・海外移住", prompt: "dream_travel", children: []),
                WishMapNode(id: "ach.dream.art", title: "創作・表現", prompt: "dream_art", children: []),
                WishMapNode(id: "ach.dream.contest", title: "大会で優勝・入賞", prompt: "dream_contest", children: []),
                WishMapNode(id: "ach.dream.book", title: "本を書く・出版", prompt: "dream_book", children: []),
                WishMapNode(id: "ach.dream.audition", title: "オーディション・コンペ", prompt: "dream_audition", children: []),
            ]),
            // 達成型ルート直下にも追加サブカテゴリ (「その他」で循環するため)
            WishMapNode(id: "ach.money", title: "お金を増やす", prompt: "money", children: [
                WishMapNode(id: "ach.money.save", title: "貯金を増やす", prompt: "money_save", children: []),
                WishMapNode(id: "ach.money.invest", title: "投資で増やす", prompt: "money_invest", children: []),
                WishMapNode(id: "ach.money.side", title: "副業を成功させる", prompt: "money_side", children: []),
                WishMapNode(id: "ach.money.debt", title: "借金を返す", prompt: "money_debt", children: []),
                WishMapNode(id: "ach.money.house", title: "マイホームを買う", prompt: "money_house", children: []),
                WishMapNode(id: "ach.money.car", title: "欲しい物を買う", prompt: "money_car", children: []),
            ]),
            WishMapNode(id: "ach.romance", title: "恋愛・結婚", prompt: "romance", children: [
                WishMapNode(id: "ach.romance.partner", title: "素敵な人と出会う", prompt: "romance_meet", children: []),
                WishMapNode(id: "ach.romance.confess", title: "告白を成功させる", prompt: "romance_confess", children: []),
                WishMapNode(id: "ach.romance.long", title: "長く幸せに過ごす", prompt: "romance_long", children: []),
                WishMapNode(id: "ach.romance.marriage", title: "結婚する", prompt: "romance_marriage", children: []),
                WishMapNode(id: "ach.romance.child", title: "子どもを授かる", prompt: "romance_child", children: []),
                WishMapNode(id: "ach.romance.recover", title: "元のような関係に戻る", prompt: "romance_recover", children: []),
            ]),
        ]
    )

    // MARK: - 改善型
    static let improvement: WishMapNode = WishMapNode(
        id: "improvement",
        title: "改善したい",
        prompt: "improvement",
        children: [
            WishMapNode(id: "imp.health", title: "健康・体力", prompt: "health", children: [
                WishMapNode(id: "imp.health.weight", title: "ダイエット", prompt: "health_diet", children: []),
                WishMapNode(id: "imp.health.exercise", title: "運動習慣", prompt: "health_exercise", children: []),
                WishMapNode(id: "imp.health.sleep", title: "睡眠改善", prompt: "health_sleep", children: []),
                WishMapNode(id: "imp.health.muscle", title: "筋トレ・体力UP", prompt: "health_muscle", children: []),
                WishMapNode(id: "imp.health.diet", title: "食生活を整える", prompt: "health_food", children: []),
                WishMapNode(id: "imp.health.recovery", title: "病気を治す・回復", prompt: "health_recovery", children: []),
            ]),
            WishMapNode(id: "imp.habit", title: "習慣を変える", prompt: "habit", children: [
                WishMapNode(id: "imp.habit.quit", title: "やめたい習慣", prompt: "habit_quit", children: []),
                WishMapNode(id: "imp.habit.start", title: "始めたい習慣", prompt: "habit_start", children: []),
                WishMapNode(id: "imp.habit.morning", title: "朝活・モーニング", prompt: "habit_morning", children: []),
                WishMapNode(id: "imp.habit.read", title: "読書習慣", prompt: "habit_read", children: []),
                WishMapNode(id: "imp.habit.write", title: "日記・ジャーナリング", prompt: "habit_write", children: []),
                WishMapNode(id: "imp.habit.smart", title: "スマホ依存を減らす", prompt: "habit_smart", children: []),
            ]),
            WishMapNode(id: "imp.relation", title: "人間関係を改善", prompt: "relationship", children: [
                WishMapNode(id: "imp.relation.family", title: "家族との関係", prompt: "rel_family", children: []),
                WishMapNode(id: "imp.relation.partner", title: "パートナー・恋愛", prompt: "rel_partner", children: []),
                WishMapNode(id: "imp.relation.colleague", title: "職場・友人", prompt: "rel_colleague", children: []),
                WishMapNode(id: "imp.relation.parent", title: "親への感謝・理解", prompt: "rel_parent", children: []),
                WishMapNode(id: "imp.relation.child", title: "子育て", prompt: "rel_child", children: []),
                WishMapNode(id: "imp.relation.boss", title: "上司・部下", prompt: "rel_boss", children: []),
            ]),
            WishMapNode(id: "imp.skill", title: "スキルを伸ばす", prompt: "skill", children: [
                WishMapNode(id: "imp.skill.lang", title: "語学", prompt: "skill_lang", children: []),
                WishMapNode(id: "imp.skill.it", title: "プログラミング・IT", prompt: "skill_it", children: []),
                WishMapNode(id: "imp.skill.com", title: "コミュニケーション力", prompt: "skill_com", children: []),
                WishMapNode(id: "imp.skill.lead", title: "リーダーシップ", prompt: "skill_lead", children: []),
                WishMapNode(id: "imp.skill.creative", title: "クリエイティブ・芸術", prompt: "skill_creative", children: []),
                WishMapNode(id: "imp.skill.body", title: "スポーツ・体技", prompt: "skill_body", children: []),
            ]),
        ]
    )

    // MARK: - 整える型
    static let balance: WishMapNode = WishMapNode(
        id: "balance",
        title: "心を整えたい",
        prompt: "balance",
        children: [
            WishMapNode(id: "bal.mental", title: "メンタルの安定", prompt: "mental", children: [
                WishMapNode(id: "bal.mental.anxiety", title: "不安・心配を手放す", prompt: "mental_anxiety", children: []),
                WishMapNode(id: "bal.mental.confidence", title: "自信を持つ", prompt: "mental_confidence", children: []),
                WishMapNode(id: "bal.mental.calm", title: "穏やかさを保つ", prompt: "mental_calm", children: []),
                WishMapNode(id: "bal.mental.angry", title: "怒りをコントロール", prompt: "mental_angry", children: []),
                WishMapNode(id: "bal.mental.lonely", title: "孤独感を癒す", prompt: "mental_lonely", children: []),
                WishMapNode(id: "bal.mental.depression", title: "気分の落ち込みを和らげる", prompt: "mental_depression", children: []),
            ]),
            WishMapNode(id: "bal.value", title: "価値観を確認", prompt: "value", children: [
                WishMapNode(id: "bal.value.family", title: "家族を大切にする", prompt: "value_family", children: []),
                WishMapNode(id: "bal.value.growth", title: "成長を続ける", prompt: "value_growth", children: []),
                WishMapNode(id: "bal.value.contribution", title: "誰かの役に立つ", prompt: "value_contribution", children: []),
                WishMapNode(id: "bal.value.honesty", title: "誠実に生きる", prompt: "value_honesty", children: []),
                WishMapNode(id: "bal.value.creativity", title: "創造的に生きる", prompt: "value_creativity", children: []),
                WishMapNode(id: "bal.value.freedom", title: "自由を大切にする", prompt: "value_freedom", children: []),
            ]),
            WishMapNode(id: "bal.gratitude", title: "感謝・幸せを感じる", prompt: "gratitude", children: [
                WishMapNode(id: "bal.gratitude.daily", title: "日常の小さな幸せ", prompt: "gratitude_daily", children: []),
                WishMapNode(id: "bal.gratitude.people", title: "周りの人への感謝", prompt: "gratitude_people", children: []),
                WishMapNode(id: "bal.gratitude.self", title: "自分自身を認める", prompt: "gratitude_self", children: []),
                WishMapNode(id: "bal.gratitude.nature", title: "自然・季節を感じる", prompt: "gratitude_nature", children: []),
                WishMapNode(id: "bal.gratitude.past", title: "過去の自分にありがとう", prompt: "gratitude_past", children: []),
                WishMapNode(id: "bal.gratitude.body", title: "自分の体に感謝する", prompt: "gratitude_body", children: []),
            ]),
            WishMapNode(id: "bal.spirit", title: "スピリチュアル・本質", prompt: "spirit", children: [
                WishMapNode(id: "bal.spirit.purpose", title: "人生の目的を見つける", prompt: "spirit_purpose", children: []),
                WishMapNode(id: "bal.spirit.meditate", title: "瞑想・マインドフルネス", prompt: "spirit_meditate", children: []),
                WishMapNode(id: "bal.spirit.energy", title: "波動・エネルギーを整える", prompt: "spirit_energy", children: []),
                WishMapNode(id: "bal.spirit.intuition", title: "直感を信じる", prompt: "spirit_intuition", children: []),
                WishMapNode(id: "bal.spirit.deathlife", title: "生き方を見つめる", prompt: "spirit_deathlife", children: []),
                WishMapNode(id: "bal.spirit.universe", title: "大いなるものを信頼する", prompt: "spirit_universe", children: []),
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
                "試験に合格したい。今日も必要な集中力と理解力を少しずつ育てたい。",
                "もし朝起きたら、まず30分だけ問題を解く自分でいたい。",
                "合格の先で、学んだ知識を誰かの役に立てたい。"
            ]
        case "career_sales", "career_promotion", "career_skill":
            return [
                "仕事で結果を出したい。今日できることを淡々と積み上げたい。",
                "もし会議が始まったら、3つの選択肢を準備して臨みたい。",
                "誰かの困りごとを解いて、自然に成果が出る自分でいたい。"
            ]
        case "health_diet", "health_exercise", "health_sleep":
            return [
                "自分の体を大切にしたい。今日の選択で明日の自分を整えたい。",
                "もし帰宅したら、まず10分だけ体を動かす自分でいたい。",
                "健康につながる選択を、今日もひとつ選びたい。"
            ]
        case "habit_quit", "habit_start", "habit_morning":
            return [
                "意志だけに頼らず、続く仕組みで習慣を作りたい。",
                "もし朝起きたら、コップ一杯の水から始めたい。",
                "完璧でなくても、続いている自分を認めたい。"
            ]
        case "rel_family", "rel_partner", "rel_colleague":
            return [
                "大切な人との時間を、今日も丁寧に作りたい。",
                "もし相手が話し始めたら、まず最後まで聴ける自分でいたい。",
                "小さな約束を守り続けて、信頼を積み上げたい。"
            ]
        case "mental_anxiety", "mental_confidence", "mental_calm":
            return [
                "不安があっても進みたい。完璧より、次の一歩を選びたい。",
                "もし不安になったら、深呼吸を3回してから考えたい。",
                "心が揺れる日ほど、自分に優しくしたい。"
            ]
        case "value_family", "value_growth", "value_contribution":
            return [
                "家族との時間を大切にできる自分でいたい。",
                "できなかったことを、少しずつできるようになりたい。",
                "誰かの役に立つことで、自分の手応えを感じたい。"
            ]
        case "gratitude_daily", "gratitude_people", "gratitude_self":
            return [
                "今日も歩けること、食べられること、眠れることに感謝したい。",
                "周りの人がいてくれることを、忘れずに大切にしたい。",
                "今日もよくやった自分を認めて、明日も歩きたい。"
            ]
        // ── 名言モード: 実際の偉人・哲学者の言葉 + 出典 ──
        case "quote_business":
            return [
                "「成功とは、失敗から失敗へと熱意を失わずに進んでいくことだ」 — ウィンストン・チャーチル",
                "「最大の栄光は決して倒れないことではなく、倒れるたびに起き上がることにある」 — ネルソン・マンデラ",
                "「Stay hungry, stay foolish. (ハングリーであれ、愚か者であれ)」 — スティーブ・ジョブズ"
            ]
        case "quote_life":
            return [
                "「なぜ生きるかを知っている者は、どのように生きることにも耐える」 — フリードリヒ・ニーチェ",
                "「人生において重要なのは、生きることそのものではなく、よく生きることである」 — ソクラテス",
                "「何事も、過ぎ去ってしまえば一つの懐かしい思い出となる」 — アレクサンドル・プーシキン"
            ]
        case "quote_sport":
            return [
                "「99%の努力と1%のひらめき」 — トーマス・エジソン",
                "「壁というのは、できる人にしかやってこない」 — イチロー",
                "「Just do it. (ただやるんだ)」 — Nike (ダン・ワイデン)"
            ]
        default:
            return [
                "\(lastTitle)に向かって、今日もできる一歩を踏み出したい。",
                "もし\(lastTitle)で迷ったら、深呼吸して目の前のことに集中したい。",
                "\(lastTitle)を通して、今日も自分らしくありたい。"
            ]
        }
    }
}
