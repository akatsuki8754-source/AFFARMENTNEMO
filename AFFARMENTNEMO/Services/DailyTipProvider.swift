//
//  DailyTipProvider.swift
//  ホーム画面下部の「今日のヒント」 (UX v4 §10.1)
//  日替わり、押すと該当テンプレ選択状態で追加画面へ
//

import Foundation

struct DailyTip: Identifiable, Hashable {
    let id: String
    let messageKey: String
    let templateId: String?  // タップ時に使うテンプレ
}

enum DailyTipProvider {
    static let pool: [DailyTip] = [
        DailyTip(id: "tip.ifthen1",
                 messageKey: "tip.ifthen1",
                 templateId: "ifthen"),
        DailyTip(id: "tip.value1",
                 messageKey: "tip.value1",
                 templateId: "taisetsu"),
        DailyTip(id: "tip.production",
                 messageKey: "tip.production",
                 templateId: nil),
        DailyTip(id: "tip.short",
                 messageKey: "tip.short",
                 templateId: nil),
        DailyTip(id: "tip.streak",
                 messageKey: "tip.streak",
                 templateId: nil),
        DailyTip(id: "tip.consistency",
                 messageKey: "tip.consistency",
                 templateId: nil),
        DailyTip(id: "tip.ifthen2",
                 messageKey: "tip.ifthen2",
                 templateId: "ifthen"),
        DailyTip(id: "tip.value2",
                 messageKey: "tip.value2",
                 templateId: "taisetsu"),
    ]

    /// 日付の日番号で安定的に選択 (同じ日は同じTip)
    static func tipForToday(_ date: Date = Date()) -> DailyTip {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        return pool[day % pool.count]
    }
}
