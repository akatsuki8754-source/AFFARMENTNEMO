//
//  ReadLog.swift
//  日次の音読完了ログ (ストリーク計算とカレンダー表示用)
//

import Foundation
import SwiftData

@Model
final class ReadLog {
    /// yyyyMMdd 形式の日付キー (タイムゾーン非依存の比較を安定化)
    @Attribute(.unique) var dateKey: String
    var date: Date
    var readCount: Int
    var slot: String  // "morning" | "evening" | "both" | "anytime"
    var createdAt: Date

    init(date: Date, readCount: Int = 1, slot: String = "anytime") {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.locale = Locale(identifier: "en_US_POSIX")
        self.dateKey = f.string(from: date)
        self.date = Calendar.current.startOfDay(for: date)
        self.readCount = readCount
        self.slot = slot
        self.createdAt = Date()
    }

    static func todayKey(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}
