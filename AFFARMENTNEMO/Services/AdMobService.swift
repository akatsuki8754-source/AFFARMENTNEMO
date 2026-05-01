//
//  AdMobService.swift
//  Google Mobile Ads SDK 統合 (#if canImport で SDK 不在時もビルド可能)
//
//  ⚠️ セットアップ:
//   1. Xcode で SPM 追加:
//      https://github.com/googleads/swift-package-manager-google-mobile-ads
//   2. Info.plist に以下を追加:
//      <key>GADApplicationIdentifier</key>
//      <string>ca-app-pub-2846643868790302~2643315135</string>
//   3. SKAdNetworkItems / NSUserTrackingUsageDescription も Info.plist に追加 (AdMob Doc 参照)
//

import SwiftUI

#if canImport(GoogleMobileAds)
import GoogleMobileAds
import UIKit

@MainActor
final class AdMobService: NSObject {
    static let shared = AdMobService()
    private var interstitial: InterstitialAd?
    private var isLoadingInterstitial = false
    private var rewarded: RewardedAd?
    private var isLoadingRewarded = false

    func start() {
        MobileAds.shared.start(completionHandler: nil)
        Task { await preloadInterstitial() }
        Task { await preloadRewarded() }
    }

    // MARK: - Interstitial
    func preloadInterstitial() async {
        guard !isLoadingInterstitial, interstitial == nil else { return }
        isLoadingInterstitial = true
        defer { isLoadingInterstitial = false }

        do {
            interstitial = try await InterstitialAd.load(
                with: AdMobConfig.interstitialUnitID,
                request: Request()
            )
        } catch {
            interstitial = nil
        }
    }

    func showInterstitialIfReady(from viewController: UIViewController, stats: UserStats) {
        guard InterstitialPolicy.shared.canShow(stats: stats) else { return }
        guard let ad = interstitial else {
            Task { await preloadInterstitial() }
            return
        }
        ad.present(from: viewController)
        InterstitialPolicy.shared.recordShown()
        interstitial = nil
        Task { await preloadInterstitial() }  // 次回のためにプリロード
    }

    // MARK: - Rewarded (B8: AI生成のゲートに使用)
    private var lastRewardedLoadError: String?

    func preloadRewarded() async {
        guard !isLoadingRewarded, rewarded == nil else { return }
        isLoadingRewarded = true
        defer { isLoadingRewarded = false }
        let unitId = AdMobConfig.rewardedUnitID
        NSLog("[AdMobService] preloadRewarded start unit=%@", unitId)
        do {
            rewarded = try await RewardedAd.load(with: unitId, request: Request())
            lastRewardedLoadError = nil
            NSLog("[AdMobService] rewarded loaded OK")
        } catch {
            rewarded = nil
            lastRewardedLoadError = String(describing: error)
            NSLog("[AdMobService] rewarded load FAILED: %@", lastRewardedLoadError ?? "")
            // 30秒後に自動再試行 (アプリが起動中の間)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(30))
                await self.preloadRewarded()
            }
        }
    }

    /// リワード広告を提示し、ユーザーがリワード獲得したら true を返す
    /// - 広告未ロード時は: 1秒だけ load 試行、それでもダメなら false (= スキップ扱い)
    /// - 呼出側 (AdRewardGate) が結果を見て次の挙動を決める
    func presentRewarded(from viewController: UIViewController,
                        completion: @escaping (Bool) -> Void) {
        if rewarded == nil {
            // 短時間 (1秒) だけロードを試して、無理なら諦める
            Task { @MainActor in
                let loadTask = Task { await self.preloadRewarded() }
                try? await Task.sleep(for: .seconds(1))
                loadTask.cancel()
                if let ad = self.rewarded {
                    self.showRewarded(ad: ad, from: viewController, completion: completion)
                } else {
                    NSLog("[AdMobService] rewarded ad unavailable, skip")
                    completion(false)
                }
            }
            return
        }
        guard let ad = rewarded else {
            completion(false)
            return
        }
        showRewarded(ad: ad, from: viewController, completion: completion)
    }

    private func showRewarded(ad: RewardedAd, from vc: UIViewController,
                              completion: @escaping (Bool) -> Void) {
        var earned = false
        // 真因対策: completion クロージャは「dismiss 後」の通知なので
        //   実際のリワード獲得は ad.present(from:userDidEarnRewardHandler:) で判定する
        ad.present(from: vc) {
            // userDidEarnRewardHandler — 動画完走したときだけ呼ばれる
            earned = true
            NSLog("[AdMobService] rewarded ad earned")
        }
        rewarded = nil
        Task { await preloadRewarded() }

        // 動画閉じ後の判定 — fullScreenContentDelegate を立てるのが王道だが、
        // SwiftUI ベースなので present 完了 + earned フラグの監視で代替
        // 5 秒経過後に earned が立っていなければスキップ扱い
        Task { @MainActor in
            for _ in 0..<60 {  // 60 * 0.5s = 30秒上限
                try? await Task.sleep(for: .milliseconds(500))
                if vc.presentedViewController == nil {
                    // 広告 modal が閉じられた → earned で判定
                    NSLog("[AdMobService] rewarded ad dismissed, earned=\(earned)")
                    completion(earned)
                    return
                }
            }
            // タイムアウト = ユーザーが閉じない or 広告が固まった → 安全側で false
            NSLog("[AdMobService] rewarded ad timeout, deny")
            completion(false)
        }
    }
}

// MARK: - SwiftUI Banner

struct AdBannerView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var refreshTimer: Timer?
        deinit { refreshTimer?.invalidate() }
    }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = AdMobConfig.bannerUnitID
        banner.rootViewController = Self.topViewController()
        banner.load(Request())
        // ユーザー要望: 30秒ごとに更新 (AdMob 推奨値、収益最適化)
        context.coordinator.refreshTimer = Timer.scheduledTimer(
            withTimeInterval: 30, repeats: true
        ) { [weak banner] _ in
            DispatchQueue.main.async {
                banner?.load(Request())
            }
        }
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

    private static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}

#else
// MARK: - SDK未統合時のスタブ (ビルド可能)

@MainActor
final class AdMobService: NSObject {
    static let shared = AdMobService()
    func start() { /* SDK未統合 */ }
    func preloadInterstitial() async { /* SDK未統合 */ }
    func showInterstitialIfReady(from viewController: AnyObject, stats: UserStats) { /* SDK未統合 */ }
    func preloadRewarded() async { /* SDK未統合 */ }
    func presentRewarded(from viewController: AnyObject, completion: @escaping (Bool) -> Void) {
        // SDK未統合時は無料パス
        completion(true)
    }
}

import UIKit
struct AdBannerView: View {
    var body: some View {
        // SDK未統合時は高さだけ予約 (バナー50pt) してレイアウトジャンプ防止
        // 仕様: 品質チェックリスト §2.2 「高さ予約済み」
        Color.clear
            .frame(height: 50)
            .accessibilityHidden(true)
    }
}
#endif

// MARK: - 高さ予約付きバナーラッパー (SDKの有無を問わずレイアウトジャンプ防止)

struct AdBannerSlot: View {
    /// スクショ撮影モード: UserDefaults `kotodama.screenshot.mode` = true で AdMob バナーを完全非表示
    private var screenshotMode: Bool {
        UserDefaults.standard.bool(forKey: "kotodama.screenshot.mode")
    }
    var body: some View {
        if screenshotMode {
            // スクショ用にバナー領域を消す
            EmptyView()
        } else {
            AdBannerView()
                .frame(height: 50)
                .frame(maxWidth: .infinity)
        }
    }
}
