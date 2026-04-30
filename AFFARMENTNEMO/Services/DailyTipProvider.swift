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
    ]

    static func tipForToday(_ date: Date = Date()) -> DailyTip {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        return pool[day % pool.count]
    }
}
