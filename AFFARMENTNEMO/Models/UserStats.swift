//
//  UserStats.swift
//  ストリーク・XP・レベル管理 (シングルトン)
//

import Foundation
import SwiftData

@Model
final class UserStats {
    @Attribute(.unique) var id: String  // 固定 "singleton"
    var currentStreak: Int
    var longestStreak: Int
    var lastReadDate: Date?
    var totalReadCount: Int
    var xp: Int
    var level: Int
    var firstLaunchDate: Date

    /// AdMob インタースティシャル抑制用: 初回3日間は出さない
    var interstitialEnabled: Bool {
        let days = Calendar.current.dateComponents([.day], from: firstLaunchDate, to: Date()).day ?? 0
        return days >= 3
    }

    init() {
        self.id = "singleton"
        self.currentStreak = 0
        self.longestStreak = 0
        self.lastReadDate = nil
        self.totalReadCount = 0
        self.xp = 0
        self.level = 1
        self.firstLaunchDate = Date()
    }

    /// XP→レベル変換 (シンプルな等差: Lv N -> N*100 XP までで次へ)
    func xpForNextLevel() -> Int { level * 100 }

    /// レベル進捗 0.0〜1.0
    var levelProgress: Double {
        let need = max(1, xpForNextLevel())
        return min(1.0, Double(xp) / Double(need))
    }
}
