//
//  DailyTipProvider.swift
//  ホーム画面下部の「今日のヒント」 (MASTER仕様書 §17, §11.2)
//  30種類を日替わりローテーション、消した日は再表示しない
//

import Foundation

struct DailyTip: Identifiable, Hashable {
    let id: String
    let messageKey: String
    let templateId: String?  // タップ時に使うテンプレ
}

enum DailyTipProvider {
    /// 30種類のヒント (MASTER §11.2: 日替わりで1つ表示、`day % 30`)
    static let pool: [DailyTip] = [
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
        DailyTip(id: "tip22", messageKey: "tip.business", templateId: "biz"),
        DailyTip(id: "tip23", messageKey: "tip.flexible", templateId: nil),
        DailyTip(id: "tip24", messageKey: "tip.write_short", templateId: nil),
        DailyTip(id: "tip25", messageKey: "tip.no_negative", templateId: nil),
        DailyTip(id: "tip26", messageKey: "tip.cue_response", templateId: "ifthen"),
        DailyTip(id: "tip27", messageKey: "tip.values_remind", templateId: "taisetsu"),
        DailyTip(id: "tip28", messageKey: "tip.daily_check", templateId: nil),
        DailyTip(id: "tip29", messageKey: "tip.mood_first", templateId: nil),
        DailyTip(id: "tip30", messageKey: "tip.celebrate_small", templateId: nil),
    ]

    /// 日付の年内通算日でローテーション (同じ日は同じTip)
    static func tipForToday(_ date: Date = Date()) -> DailyTip {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        return pool[day % pool.count]
    }
}
