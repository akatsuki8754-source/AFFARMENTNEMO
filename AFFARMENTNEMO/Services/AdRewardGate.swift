//
//  AdRewardGate.swift
//  AI生成 (Gemini) を呼ぶ前にリワード広告で資金回収するゲート
//
//  ゲートポリシー:
//   - Phase 1.5/2 (静的サンプル中): #if PHASE3_GEMINI_LIVE が無いので呼ばれない
//   - Phase 3 (Gemini本接続): AI生成1回ごとにリワード広告を提示
//   - 1日のスキップ枠 = 1回 (ライト版): 初回 or 1日1回は無料、それ以降はリワードを見ないと生成不可
//   - 動画完走でリワード獲得 → completion(true) → AI呼び出し
//   - スキップ・失敗 → completion(false) → AI呼び出さない
//

import Foundation
import UIKit

@MainActor
final class AdRewardGate {
    static let shared = AdRewardGate()
    private init() {}

    private let dailyFreeKey = "kotodama.aiGen.dailyFreeUsed"
    private let dailyDateKey = "kotodama.aiGen.dailyDate"

    /// 1日1回まで無料 → それ以降はリワード必須
    func presentBeforeAIGeneration(completion: @escaping (Bool) -> Void) {
        rotateIfNewDay()
        let used = UserDefaults.standard.integer(forKey: dailyFreeKey)
        if used < 1 {
            // 無料枠
            UserDefaults.standard.set(used + 1, forKey: dailyFreeKey)
            completion(true)
            return
        }
        // リワード広告必須
        guard let vc = topViewController() else {
            completion(true)  // VC 取得失敗は無料パス
            return
        }
        AdMobService.shared.presentRewarded(from: vc) { earned in
            completion(earned)
        }
    }

    private func rotateIfNewDay() {
        let today = Self.todayKey()
        let last = UserDefaults.standard.string(forKey: dailyDateKey)
        if last != today {
            UserDefaults.standard.set(today, forKey: dailyDateKey)
            UserDefaults.standard.set(0, forKey: dailyFreeKey)
        }
    }

    private static func todayKey() -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: Date())
        return "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
    }

    private func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}
