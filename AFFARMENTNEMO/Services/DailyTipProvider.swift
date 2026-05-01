//
//  DailyTipProvider.swift
//  ホーム画面下部の「今日のヒント」 (MASTER仕様書 §17, §11.2)
//  60+ 件: 心理学エビデンス + 願い文化 + 名言 + アファメーション科学
//

import Foundation

struct DailyTip: Identifiable, Hashable {
    let id: String
    let messageKey: String
    let templateId: String?  // タップ時に使うテンプレ
}

enum DailyTipProvider {
    /// 60+ 種類のヒント (年内通算日 % pool.count でローテーション)
    static let pool: [DailyTip] = [
        // ─── 心理学・行動経済学 ───
        DailyTip(id: "tip01", messageKey: "tip.ifthen1", templateId: "ifthen"),
        DailyTip(id: "tip02", messageKey: "tip.value1", templateId: "taisetsu"),
        DailyTip(id: "tip03", messageKey: "tip.production", templateId: nil),
        DailyTip(id: "tip04", messageKey: "tip.short", templateId: nil),
        DailyTip(id: "tip05", messageKey: "tip.streak", templateId: nil),
        DailyTip(id: "tip06", messageKey: "tip.consistency", templateId: nil),
        DailyTip(id: "tip07", messageKey: "tip.ifthen2", templateId: "ifthen"),
        DailyTip(id: "tip08", messageKey: "tip.value2", templateId: "taisetsu"),
        DailyTip(id: "tip09", messageKey: "tip.morning", templateId: nil),
        DailyTip(id: "tip10", messageKey: "tip.evening", templateId: nil),
        DailyTip(id: "tip11", messageKey: "tip.specific", templateId: nil),
        DailyTip(id: "tip12", messageKey: "tip.process", templateId: "narikatai"),
        DailyTip(id: "tip13", messageKey: "tip.gratitude", templateId: nil),
        DailyTip(id: "tip14", messageKey: "tip.smallstep", templateId: "ifthen"),
        DailyTip(id: "tip15", messageKey: "tip.values_alignment", templateId: "taisetsu"),
        DailyTip(id: "tip16", messageKey: "tip.no_perfection", templateId: nil),
        DailyTip(id: "tip17", messageKey: "tip.review", templateId: nil),
        DailyTip(id: "tip18", messageKey: "tip.repeat", templateId: nil),
        DailyTip(id: "tip19", messageKey: "tip.context", templateId: "ifthen"),
        DailyTip(id: "tip20", messageKey: "tip.self_kind", templateId: "hagemashi"),
        DailyTip(id: "tip21", messageKey: "tip.realistic", templateId: nil),
        DailyTip(id: "tip22", messageKey: "tip.business", templateId: "negai"),
        DailyTip(id: "tip23", messageKey: "tip.flexible", templateId: nil),
        DailyTip(id: "tip24", messageKey: "tip.write_short", templateId: nil),
        DailyTip(id: "tip25", messageKey: "tip.no_negative", templateId: nil),
        DailyTip(id: "tip26", messageKey: "tip.cue_response", templateId: "ifthen"),
        DailyTip(id: "tip27", messageKey: "tip.values_remind", templateId: "taisetsu"),
        DailyTip(id: "tip28", messageKey: "tip.daily_check", templateId: nil),
        DailyTip(id: "tip29", messageKey: "tip.mood_first", templateId: nil),
        DailyTip(id: "tip30", messageKey: "tip.celebrate_small", templateId: nil),

        // ─── 世界の願い文化 ───
        DailyTip(id: "tip31", messageKey: "tip.tanabata1", templateId: "negai"),
        DailyTip(id: "tip32", messageKey: "tip.tanabata2", templateId: "negai"),
        DailyTip(id: "tip33", messageKey: "tip.ema", templateId: "negai"),
        DailyTip(id: "tip34", messageKey: "tip.wishtree_world", templateId: nil),
        DailyTip(id: "tip35", messageKey: "tip.dreamcatcher", templateId: nil),
        DailyTip(id: "tip36", messageKey: "tip.trevi_fountain", templateId: "negai"),
        DailyTip(id: "tip37", messageKey: "tip.korean_wish", templateId: nil),
        DailyTip(id: "tip38", messageKey: "tip.tibetan_prayer", templateId: nil),
        DailyTip(id: "tip39", messageKey: "tip.shinto_kotodama", templateId: nil),
        DailyTip(id: "tip40", messageKey: "tip.first_dream", templateId: "negai"),

        // ─── 名言 (公有/古典) ───
        DailyTip(id: "tip41", messageKey: "tip.quote_emerson", templateId: nil),
        DailyTip(id: "tip42", messageKey: "tip.quote_aurelius", templateId: nil),
        DailyTip(id: "tip43", messageKey: "tip.quote_lao", templateId: "ifthen"),
        DailyTip(id: "tip44", messageKey: "tip.quote_seneca", templateId: nil),
        DailyTip(id: "tip45", messageKey: "tip.quote_kojiki", templateId: nil),
        DailyTip(id: "tip46", messageKey: "tip.quote_basho", templateId: nil),
        DailyTip(id: "tip47", messageKey: "tip.quote_buddha", templateId: "taisetsu"),
        DailyTip(id: "tip48", messageKey: "tip.quote_aristotle", templateId: "ifthen"),
        DailyTip(id: "tip49", messageKey: "tip.quote_yoshida", templateId: nil),
        DailyTip(id: "tip50", messageKey: "tip.quote_franklin", templateId: nil),

        // ─── アファメーション科学 ───
        DailyTip(id: "tip51", messageKey: "tip.science_steele", templateId: "taisetsu"),
        DailyTip(id: "tip52", messageKey: "tip.science_wood", templateId: nil),
        DailyTip(id: "tip53", messageKey: "tip.science_gollwitzer", templateId: "ifthen"),
        DailyTip(id: "tip54", messageKey: "tip.science_macleod", templateId: nil),
        DailyTip(id: "tip55", messageKey: "tip.science_dweck", templateId: "narikatai"),
        DailyTip(id: "tip56", messageKey: "tip.science_lally", templateId: nil),
        DailyTip(id: "tip57", messageKey: "tip.science_baumeister", templateId: "hagemashi"),
        DailyTip(id: "tip58", messageKey: "tip.science_loehr", templateId: nil),
        DailyTip(id: "tip59", messageKey: "tip.science_neff", templateId: "hagemashi"),
        DailyTip(id: "tip60", messageKey: "tip.science_creswell", templateId: "taisetsu"),

        // ─── 拡張: 行動経済学・習慣化テクニック (実用集) ───
        DailyTip(id: "tip61", messageKey: "tip.x.habit_stack", templateId: "ifthen"),
        DailyTip(id: "tip62", messageKey: "tip.x.two_minute_rule", templateId: nil),
        DailyTip(id: "tip63", messageKey: "tip.x.environment_design", templateId: nil),
        DailyTip(id: "tip64", messageKey: "tip.x.identity_first", templateId: "narikatai"),
        DailyTip(id: "tip65", messageKey: "tip.x.compound_effect", templateId: nil),
        DailyTip(id: "tip66", messageKey: "tip.x.fresh_start", templateId: nil),
        DailyTip(id: "tip67", messageKey: "tip.x.commitment_device", templateId: nil),
        DailyTip(id: "tip68", messageKey: "tip.x.temptation_bundling", templateId: nil),
        DailyTip(id: "tip69", messageKey: "tip.x.never_miss_twice", templateId: nil),
        DailyTip(id: "tip70", messageKey: "tip.x.tracking", templateId: nil),

        // ─── 拡張: 自己肯定感・メンタル ───
        DailyTip(id: "tip71", messageKey: "tip.x.self_compassion", templateId: "hagemashi"),
        DailyTip(id: "tip72", messageKey: "tip.x.growth_mindset", templateId: "narikatai"),
        DailyTip(id: "tip73", messageKey: "tip.x.body_first", templateId: nil),
        DailyTip(id: "tip74", messageKey: "tip.x.deep_breath", templateId: nil),
        DailyTip(id: "tip75", messageKey: "tip.x.gratitude_three", templateId: nil),
        DailyTip(id: "tip76", messageKey: "tip.x.compare_yesterday", templateId: nil),
        DailyTip(id: "tip77", messageKey: "tip.x.permission_rest", templateId: "hagemashi"),
        DailyTip(id: "tip78", messageKey: "tip.x.smile_first", templateId: nil),
        DailyTip(id: "tip79", messageKey: "tip.x.proud_moment", templateId: nil),
        DailyTip(id: "tip80", messageKey: "tip.x.future_self_letter", templateId: "negai"),

        // ─── 拡張: 営業・目標達成 ───
        DailyTip(id: "tip81", messageKey: "tip.x.smart_goal", templateId: "negai"),
        DailyTip(id: "tip82", messageKey: "tip.x.daily_focus_one", templateId: nil),
        DailyTip(id: "tip83", messageKey: "tip.x.eat_the_frog", templateId: "ifthen"),
        DailyTip(id: "tip84", messageKey: "tip.x.pomodoro", templateId: "ifthen"),
        DailyTip(id: "tip85", messageKey: "tip.x.wins_record", templateId: nil),
        DailyTip(id: "tip86", messageKey: "tip.x.deadline_self", templateId: nil),
        DailyTip(id: "tip87", messageKey: "tip.x.review_friday", templateId: nil),
        DailyTip(id: "tip88", messageKey: "tip.x.next_action", templateId: "ifthen"),

        // ─── 拡張: 言葉・声・読み方 ───
        DailyTip(id: "tip89", messageKey: "tip.x.read_aloud_volume", templateId: nil),
        DailyTip(id: "tip90", messageKey: "tip.x.first_person", templateId: nil),
        DailyTip(id: "tip91", messageKey: "tip.x.present_tense", templateId: nil),
        DailyTip(id: "tip92", messageKey: "tip.x.specific_situation", templateId: "ifthen"),
        DailyTip(id: "tip93", messageKey: "tip.x.morning_first_word", templateId: nil),
        DailyTip(id: "tip94", messageKey: "tip.x.evening_reflect", templateId: nil),
        DailyTip(id: "tip95", messageKey: "tip.x.short_sentence", templateId: nil),

        // ─── 拡張: 名言追加 (古典中心) ───
        DailyTip(id: "tip96", messageKey: "tip.x.quote_socrates", templateId: nil),
        DailyTip(id: "tip97", messageKey: "tip.x.quote_confucius", templateId: nil),
        DailyTip(id: "tip98", messageKey: "tip.x.quote_thoreau", templateId: nil),
        DailyTip(id: "tip99", messageKey: "tip.x.quote_helen_keller", templateId: "hagemashi"),
        DailyTip(id: "tip100", messageKey: "tip.x.quote_picasso", templateId: nil),
    ]

    static func tipForToday(_ date: Date = Date()) -> DailyTip {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        return pool[day % pool.count]
    }
}
