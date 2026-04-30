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
    private let onboardingFreeKey = "kotodama.aiGen.onboardingFreeUsed"

    /// オンボ初回 AI 利用は完全無料 (広告ゲートなし)
    /// それ以外は 1日1回まで無料、以降リワード必須
    /// - Parameters:
    ///   - isOnboardingFirstUse: true なら広告ゲートなし (Onboarding 1ページ目の AI 利用)
    func presentBeforeAIGeneration(isOnboardingFirstUse: Bool = false,
                                    completion: @escaping (Bool) -> Void) {
        if isOnboardingFirstUse {
            if UserDefaults.standard.bool(forKey: onboardingFreeKey) == false {
                UserDefaults.standard.set(true, forKey: onboardingFreeKey)
                NSLog("[AdRewardGate] onboarding first use, one-time bypass")
                completion(true)
                return
            }
        }
        rotateIfNewDay()
        let used = UserDefaults.standard.integer(forKey: dailyFreeKey)
        if used < 1 {
            // 無料枠
            UserDefaults.standard.set(used + 1, forKey: dailyFreeKey)
            NSLog("[AdRewardGate] daily free use (count: %d)", used + 1)
            completion(true)
            return
        }
        // リワード広告必須
        guard let vc = topViewController() else {
            NSLog("[AdRewardGate] VC not found, deny to avoid ad-gate bypass")
            completion(false)
            return
        }
        NSLog("[AdRewardGate] presenting rewarded ad")
        AdMobService.shared.presentRewarded(from: vc) { earned in
            NSLog("[AdRewardGate] rewarded result: earned=%@", String(earned))
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
