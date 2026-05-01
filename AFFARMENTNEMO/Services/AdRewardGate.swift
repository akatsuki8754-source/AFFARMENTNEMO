//
//  AdRewardGate.swift
//  AI生成 (Gemini) を呼ぶ前のリワード広告ゲート
//
//  ゲートポリシー (ユーザー要望: 制限かからなきゃ基本 Gemini):
//   - オンボ初回: 完全無料 (体験を阻害しない)
//   - 1日 daily_free 回 (= 5) は無料で Gemini 直行
//   - daily_free を超えたら、リワード広告を「任意で」提示
//      - リワードロードできて、ユーザーが見て完走 → 生成
//      - 広告未ロード or ユーザーがスキップ → それでも生成 (Functions 側のクォータ
//        が日5回の保護線として効く)
//   - つまりクライアント側はソフトゲート。サーバー側がハードリミット。
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
    /// 1日に広告なしで Gemini を使える回数
    /// (Functions 側の AI_MAX_USER_DAILY=5 とほぼ揃える)
    private let dailyFreeQuota = 3

    /// AI 生成前のゲート。
    /// ポリシー (ユーザー要望: 制限内なら基本 Gemini / 広告出ない時は破綻させない):
    ///   1. オンボ初回 → 完全無料パス
    ///   2. 1日 dailyFreeQuota 回 (= 3) は広告なしで Gemini に直行
    ///   3. それ以降はリワード広告必須:
    ///      - 広告完走 → Gemini に通す + 無料枠 +1 (リワード分)
    ///      - 広告未ロード → deny (= ローカル候補にフォールバック / 破綻防止)
    ///      - 広告スキップ → deny (= 同上)
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
        if used < dailyFreeQuota {
            // 無料枠 (3回まで)
            UserDefaults.standard.set(used + 1, forKey: dailyFreeKey)
            NSLog("[AdRewardGate] daily free use (count: %d/%d)", used + 1, dailyFreeQuota)
            completion(true)
            return
        }
        // 4回目以降: リワード広告必須
        guard let vc = topViewController() else {
            NSLog("[AdRewardGate] VC not found, deny")
            completion(false)
            return
        }
        NSLog("[AdRewardGate] over quota, presenting rewarded ad")
        AdMobService.shared.presentRewarded(from: vc) { earned in
            NSLog("[AdRewardGate] rewarded result: earned=%@", String(earned))
            // 広告完走時のみ通す。ロード失敗・スキップは deny して破綻防止
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
