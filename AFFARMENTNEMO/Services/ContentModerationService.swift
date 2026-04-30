//
//  ContentModerationService.swift
//  Apple Guideline 1.2 (UGC) 対応 — 不適切コンテンツの自動フィルタ + ブロック
//
//  クライアントサイドの基本フィルタ。サーバ側 (Cloud Functions) でも二重チェック予定。
//

import Foundation

enum ContentModerationService {
    /// 不適切ワード (差別/暴力/性的/罵倒) — 日本語+英語の頻出語のみ。
    /// 詳細はサーバサイドで制御。クライアントは UI 即時拒否のためのフィルタ。
    static let prohibitedPatterns: [String] = [
        // 性的 (ユーザー報告: 「ちんこ」が通った → 日本語俗語を網羅)
        "セックス", "セフレ", "風俗", "売春", "AV", "アダルト",
        "ちんこ", "ちんちん", "ちんぽ", "チンコ", "チンチン", "チンポ",
        "まんこ", "マンコ", "おまんこ", "オマンコ",
        "おっぱい", "オッパイ", "乳首", "ちくび", "おちんちん", "ちんぽこ",
        "うんこ", "ウンコ", "うんち", "ウンチ",
        "ザーメン", "ザー汁", "射精", "オナニー", "おなにー", "自慰",
        "エロ", "えろい", "エロい", "h する", "Hする", "ヤる", "やりたい",
        "fuck", "fck", "sex", "porn", "pornhub", "nude", "naked", "xxx", "dick", "pussy", "cock",
        // 暴力 / 自傷示唆 (慎重に: 「自殺」は本人語りの可能性ありなので除外)
        "殺す", "死ね", "氏ね", "ぶっ殺す", "コロス",
        "kill yourself", "kys", "go die",
        // 差別語
        "kkk", "nigger", "n-word", "faggot", "tranny", "retard",
        // 詐欺/出会い系
        "出会い", "援助交際", "援交", "副業募集", "稼げます", "高収入", "在宅で月",
        "パパ活", "ママ活", "セフレ募集", "LINE交換",
        // 過度な罵倒
        "クソ野郎", "ゴミ", "アホ", "バカ野郎", "カス", "クズ",
        "asshole", "bitch", "bastard",
    ]

    enum Result: Equatable {
        case ok
        case blocked(reason: String)
    }

    static func check(_ text: String) -> Result {
        let lowered = text.lowercased()
        for word in prohibitedPatterns {
            if lowered.contains(word.lowercased()) {
                return .blocked(reason: "不適切な表現が含まれています")
            }
        }
        return .ok
    }
}

// MARK: - User Block Store (端末ローカル)
/// Apple Guideline 1.2 ブロック機能の最小実装 — ローカルに UID を蓄積、
/// タイムライン表示時にフィルタリングする。
import Combine
@MainActor
final class UserBlockStore: ObservableObject {
    static let shared = UserBlockStore()
    private let storeKey = "kotodama.blocked.uids"
    @Published private(set) var blockedUIDs: Set<String> = []

    private init() {
        let raw = UserDefaults.standard.stringArray(forKey: storeKey) ?? []
        blockedUIDs = Set(raw)
    }

    func block(_ uid: String) {
        blockedUIDs.insert(uid)
        persist()
    }

    func unblock(_ uid: String) {
        blockedUIDs.remove(uid)
        persist()
    }

    func unblockAll() {
        blockedUIDs.removeAll()
        persist()
    }

    func isBlocked(_ uid: String) -> Bool {
        blockedUIDs.contains(uid)
    }

    private func persist() {
        UserDefaults.standard.set(Array(blockedUIDs), forKey: storeKey)
    }
}
