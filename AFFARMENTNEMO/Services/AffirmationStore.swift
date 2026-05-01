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

    /// 個別 affirmation の readCount を +1 (Library 画面 「読了 N 回」の真因対策)
    /// - 渡された Affirmation が context に未登録 (別 context のオブジェクト) でも動くよう
    ///   id で fetch しなおして context 上のインスタンスを更新する
    func incrementReadCount(for affirmation: Affirmation) {
        let targetId = affirmation.id
        // ① まずは渡されたオブジェクトを直接更新 (同一 context の場合これで動く)
        affirmation.readCount += 1
        affirmation.updatedAt = Date()
        do {
            try context.save()
            NSLog("[AffirmationStore] readCount=%d for id=%@ (direct save)",
                  affirmation.readCount, targetId.uuidString)
            return
        } catch {
            NSLog("[AffirmationStore] direct save failed: %@", String(describing: error))
        }
        // ② フォールバック: id で fetch して再更新
        do {
            let descriptor = FetchDescriptor<Affirmation>(
                predicate: #Predicate { $0.id == targetId }
            )
            if let fetched = try context.fetch(descriptor).first {
                fetched.readCount += 1
                fetched.updatedAt = Date()
                try context.save()
                NSLog("[AffirmationStore] readCount=%d for id=%@ (refetch save)",
                      fetched.readCount, targetId.uuidString)
            } else {
                NSLog("[AffirmationStore] no Affirmation matching id=%@", targetId.uuidString)
            }
        } catch {
            NSLog("[AffirmationStore] refetch save failed: %@", String(describing: error))
        }
    }

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

    // MARK: - Default Seed (20 affirmations × 5 categories)
    //   オンボーディング完了直後に呼ばれる。一度シードされると flag で再実行されない。

    /// デフォルト affirmation の 5 カテゴリ × 4 文 = 20 文
    /// (出典: アファメーション基本セット — 自信 / 富 / 生産性 / 関係 / 健康)
    static let defaultSeedAffirmations: [(category: AffirmationCategoryKind, customName: String, text: String, includeInRoutine: Bool)] = [
        // 1) 自信をつけたい
        (.selfAffirm, "自信", "私は自分の人生を自分でデザインしている", true),
        (.selfAffirm, "自信", "私は幸せを選んでいる", true),
        (.selfAffirm, "自信", "私には夢を叶える力がある", true),
        (.selfAffirm, "自信", "私は自分のベストバージョンに近づいている", true),
        // 2) お金に恵まれたい
        (.goal, "豊かさ", "私はお金を簡単に、素早く引き寄せている", false),
        (.goal, "豊かさ", "私は富を引き寄せる磁石だ", false),
        (.goal, "豊かさ", "私は豊かさの中で生きている", false),
        (.goal, "豊かさ", "私はより豊かになるチャンスに恵まれている", false),
        // 3) 生産性
        (.habit, "生産性", "今日の私は、エネルギーに満ちあふれていて何でもできる", true),
        (.habit, "生産性", "私は生産的に仕事をしている", false),
        (.habit, "生産性", "私は計画を実行できている", false),
        (.habit, "生産性", "私の頭の中も周りの環境もよく整理されていて、物事を着実に進めることができている", false),
        // 4) 人間関係
        (.values, "人間関係", "私は人の愛を受け入れて、人に愛を与えている", true),
        (.values, "人間関係", "私は家族や友人といった素晴らしい人間関係に恵まれている", false),
        (.values, "人間関係", "私は人を大切にするし、周りの人も私を大切にしてくれる", false),
        (.values, "人間関係", "私は愛を受け入れる準備があるし、愛に値する人間だ", false),
        // 5) 健康
        (.values, "健康", "私は自分の体にいいものだけを、必要なときにだけ食べる", false),
        (.values, "健康", "私は健康な体を持っている", true),
        (.values, "健康", "私は理想通りの、健康で、強い体を持つ自分に近づいている", false),
        (.values, "健康", "私は自分の体を愛し、尊敬している", false),
    ]

    /// デフォルト affirmation を seed (オンボーディング完了直後に呼ぶ)
    /// 既に seed 済 (UserDefaults: kotodama.defaultsSeeded.v1=true) ならスキップ
    /// ユーザーがオンボで作成した affirmation は orderIndex=0 で残し、
    /// デフォルト 20 件を orderIndex=1..20 で後ろに追加する。
    func seedDefaultAffirmationsIfNeeded() {
        let key = "kotodama.defaultsSeeded.v1"
        if UserDefaults.standard.bool(forKey: key) { return }

        // 既存 affirmation (オンボで作成) を 0 番に固定するため、orderIndex を再採番
        let existing = allAffirmations(activeOnly: false)
        var nextOrder = 0
        for aff in existing.sorted(by: { $0.orderIndex < $1.orderIndex }) {
            aff.orderIndex = nextOrder
            nextOrder += 1
        }

        // デフォルト 20 件を順次追加 (重複検知: 同じ text があればスキップ)
        let existingTexts = Set(existing.map { $0.text })
        var added = 0
        for item in Self.defaultSeedAffirmations {
            if existingTexts.contains(item.text) { continue }
            let aff = Affirmation(
                text: item.text,
                internalMode: "affirmation",
                templateUsed: nil,
                category: item.category.rawValue,
                customCategoryName: item.customName,
                ifTrigger: nil,
                thenAction: nil,
                morningEnabled: item.includeInRoutine,
                eveningEnabled: false,
                orderIndex: nextOrder
            )
            aff.includeInRoutine = item.includeInRoutine
            context.insert(aff)
            nextOrder += 1
            added += 1
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
        NSLog("[AffirmationStore] seeded %d default affirmations (existing user: %d kept at top)", added, existing.count)
    }
}

struct ReadCompletionResult: Equatable {
    let currentStreak: Int
    let xpGained: Int
    let leveledUp: Bool
    let newLevel: Int
    let newStreakStart: Bool
}
