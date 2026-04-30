//
//  AffirmationStore.swift
//  CRUD + ストリーク計算 + XP/レベル更新の高位ファサード
//

import Foundation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class AffirmationStore {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - UserStats (singleton)

    func userStats() -> UserStats {
        let descriptor = FetchDescriptor<UserStats>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let stats = UserStats()
        context.insert(stats)
        try? context.save()
        return stats
    }

    // MARK: - Affirmation CRUD

    func allAffirmations(activeOnly: Bool = true) -> [Affirmation] {
        var descriptor = FetchDescriptor<Affirmation>(
            sortBy: [SortDescriptor(\.orderIndex), SortDescriptor(\.createdAt)]
        )
        if activeOnly {
            descriptor.predicate = #Predicate { $0.isActive }
        }
        return (try? context.fetch(descriptor)) ?? []
    }

    func morningSet() -> [Affirmation] {
        allAffirmations().filter { $0.morningEnabled }
    }

    func eveningSet() -> [Affirmation] {
        allAffirmations().filter { $0.eveningEnabled }
    }

    @discardableResult
    func add(text: String,
             internalMode: String,
             templateUsed: String?,
             category: AffirmationCategoryKind,
             customCategoryName: String? = nil,
             ifTrigger: String? = nil,
             thenAction: String? = nil,
             morningEnabled: Bool = true,
             eveningEnabled: Bool = false,
             includeInRoutine: Bool = true,
             startDate: Date? = nil,
             endDate: Date? = nil,
             weekdayMask: Int = 127) -> Affirmation {
        let nextOrder = (allAffirmations(activeOnly: false).map(\.orderIndex).max() ?? -1) + 1
        let aff = Affirmation(
            text: text,
            internalMode: internalMode,
            templateUsed: templateUsed,
            category: category.rawValue,
            customCategoryName: customCategoryName,
            ifTrigger: ifTrigger,
            thenAction: thenAction,
            morningEnabled: morningEnabled,
            eveningEnabled: eveningEnabled,
            orderIndex: nextOrder
        )
        aff.includeInRoutine = includeInRoutine
        aff.startDate = startDate
        aff.endDate = endDate
        aff.weekdayMask = weekdayMask == 0 ? 127 : weekdayMask
        context.insert(aff)
        try? context.save()
        return aff
    }

    func update(_ aff: Affirmation,
                text: String? = nil,
                category: AffirmationCategoryKind? = nil,
                morningEnabled: Bool? = nil,
                eveningEnabled: Bool? = nil,
                customCategoryName: String?? = nil,
                startDate: Date?? = nil,
                endDate: Date?? = nil,
                weekdayMask: Int? = nil,
                recordingFileName: String?? = nil,
                includeInRoutine: Bool? = nil) {
        if let text { aff.text = text }
        if let category { aff.category = category.rawValue }
        if let customCategoryName { aff.customCategoryName = customCategoryName }
        if let morningEnabled { aff.morningEnabled = morningEnabled }
        if let eveningEnabled { aff.eveningEnabled = eveningEnabled }
        if let startDate { aff.startDate = startDate }
        if let endDate { aff.endDate = endDate }
        if let weekdayMask { aff.weekdayMask = weekdayMask == 0 ? 127 : weekdayMask }
        if let recordingFileName { aff.recordingFileName = recordingFileName }
        if let includeInRoutine { aff.includeInRoutine = includeInRoutine }
        aff.updatedAt = Date()
        try? context.save()
    }

    /// ホームのルーティン順序を保存 (新しい配列の orderIndex を 0...N で振り直す)
    func updateRoutineOrder(_ ordered: [Affirmation]) {
        for (i, a) in ordered.enumerated() {
            a.orderIndex = i
            a.updatedAt = Date()
        }
        try? context.save()
    }

    func delete(_ aff: Affirmation) {
        context.delete(aff)
        try? context.save()
    }

    /// 削除Undo用: 5秒以内の論理削除リカバリ
    func softDelete(_ aff: Affirmation) {
        aff.isActive = false
        aff.updatedAt = Date()
        try? context.save()
    }

    func restore(_ aff: Affirmation) {
        aff.isActive = true
        aff.updatedAt = Date()
        try? context.save()
    }

    // MARK: - Read completion

    /// 「✓ 読みました」タップ時の処理: ストリーク・XP更新 + ReadLog記録
    func recordRead(slot: String = "anytime") -> ReadCompletionResult {
        let stats = userStats()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // ストリーク計算
        var newStreakStart = false
        if let last = stats.lastReadDate {
            let lastDay = cal.startOfDay(for: last)
            let dayDiff = cal.dateComponents([.day], from: lastDay, to: today).day ?? 0
            if dayDiff == 0 {
                // 既に今日読んでいる: ストリークは変えない
            } else if dayDiff == 1 {
                stats.currentStreak += 1
            } else {
                stats.currentStreak = 1
                newStreakStart = true
            }
        } else {
            stats.currentStreak = 1
        }
        stats.longestStreak = max(stats.longestStreak, stats.currentStreak)
        stats.lastReadDate = today
        stats.totalReadCount += 1

        // XP/Level
        let xpGained = 10
        stats.xp += xpGained
        var leveledUp = false
        while stats.xp >= stats.xpForNextLevel() {
            stats.xp -= stats.xpForNextLevel()
            stats.level += 1
            leveledUp = true
        }

        // ReadLog (1日1件、上書き)
        let key = ReadLog.todayKey()
        let logDescriptor = FetchDescriptor<ReadLog>(
            predicate: #Predicate { $0.dateKey == key }
        )
        if let existing = try? context.fetch(logDescriptor).first {
            existing.readCount += 1
        } else {
            let log = ReadLog(date: today, readCount: 1, slot: slot)
            context.insert(log)
        }

        try? context.save()

        return ReadCompletionResult(
            currentStreak: stats.currentStreak,
            xpGained: xpGained,
            leveledUp: leveledUp,
            newLevel: stats.level,
            newStreakStart: newStreakStart
        )
    }

    /// 全データ削除 (アカウント削除導線用)
    func deleteAll() {
        try? context.delete(model: Affirmation.self)
        try? context.delete(model: ReadLog.self)
        try? context.delete(model: UserStats.self)
        try? context.save()
    }
}

struct ReadCompletionResult: Equatable {
    let currentStreak: Int
    let xpGained: Int
    let leveledUp: Bool
    let newLevel: Int
    let newStreakStart: Bool
}
