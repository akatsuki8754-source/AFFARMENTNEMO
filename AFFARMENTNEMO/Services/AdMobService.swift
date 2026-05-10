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
    private var interstitialRetryCount = 0
    private var rewarded: RewardedAd?
    private var isLoadingRewarded = false
    private var rewardedRetryCount = 0
    /// Strong ref so the FullScreenContentDelegate is retained for the
    /// interstitial's lifetime (delegate is held weakly by the SDK).
    private var interstitialDelegate: InterstitialFullScreenDelegate?

    // MARK: - Emergency Rate Limiter
    // Caps total ad requests per device per hour. Healthy use: 10-20/hour.
    // 60 is generous; anything beyond strongly suggests a runaway loop.
    private static var requestCountThisHour = 0
    private static var hourBucketKey = ""
    private func canMakeAdRequest(type: String) -> Bool {
        let now = Date()
        let key = ISO8601DateFormatter().string(from: now).prefix(13)  // hour bucket "yyyy-MM-ddTHH"
        if AdMobService.hourBucketKey != key {
            AdMobService.hourBucketKey = String(key)
            AdMobService.requestCountThisHour = 0
        }
        AdMobService.requestCountThisHour += 1
        if AdMobService.requestCountThisHour > 60 {
            #if DEBUG
            print("[AdMob] RATE LIMITED type=\(type) count=\(AdMobService.requestCountThisHour) — refusing request")
            #endif
            return false
        }
        return true
    }

    // MARK: - Backoff schedule for failed loads
    // 60s -> 120s -> 300s, then stop after 5 attempts.
    private static let backoffSchedule: [TimeInterval] = [60, 120, 300, 300, 300]
    private static let maxRetries = 5

    func start() {
        MobileAds.shared.start(completionHandler: { [weak self] _ in
            // 起動完了後にプリロード開始
            Task { @MainActor in
                await self?.preloadInterstitial()
                await self?.preloadRewarded()
            }
        })
        // NOTE: 旧実装にあった 60秒間隔のリワード再ロードループは削除。
        // ロード失敗時はそれぞれの preload 内で指数バックオフで再試行する。
    }

    // MARK: - Interstitial
    func preloadInterstitial() async {
        guard !isLoadingInterstitial, interstitial == nil else { return }
        guard canMakeAdRequest(type: "interstitial") else { return }
        isLoadingInterstitial = true
        defer { isLoadingInterstitial = false }

        do {
            let ad = try await InterstitialAd.load(
                with: AdMobConfig.interstitialUnitID,
                request: Request()
            )
            // Wire up FullScreenContentDelegate BEFORE the ad is ever presented
            // so impression/click/dismiss callbacks fire and AdMob counts the show.
            let delegate = InterstitialFullScreenDelegate()
            self.interstitialDelegate = delegate
            ad.fullScreenContentDelegate = delegate
            interstitial = ad
            interstitialRetryCount = 0
            #if DEBUG
            print("[AdMob] interstitial loaded responseInfo=\(String(describing: ad.responseInfo))")
            #endif
        } catch {
            interstitial = nil
            #if DEBUG
            let nsErr = error as NSError
            print("[AdMob] interstitial load failed code=\(nsErr.code) domain=\(nsErr.domain) msg=\(error.localizedDescription)")
            #endif
            scheduleInterstitialRetry()
        }
    }

    private func scheduleInterstitialRetry() {
        guard interstitialRetryCount < AdMobService.maxRetries else {
            NSLog("[AdMobService] interstitial load: max retries reached, giving up")
            return
        }
        let delay = AdMobService.backoffSchedule[interstitialRetryCount]
        interstitialRetryCount += 1
        NSLog("[AdMobService] interstitial backoff: retry %d in %.0fs", interstitialRetryCount, delay)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            await self.preloadInterstitial()
        }
    }

    func showInterstitialIfReady(from viewController: UIViewController, stats: UserStats) {
        guard InterstitialPolicy.shared.canShow(stats: stats) else { return }
        guard let ad = interstitial else {
            // 表示不可能だったときは静かに preload (バックオフで自己制御)
            Task { await preloadInterstitial() }
            return
        }
        ad.present(from: viewController)
        InterstitialPolicy.shared.recordShown()
        interstitial = nil
        // 表示成功後だけ次の preload を行う (loop 防止)
        Task { await preloadInterstitial() }
    }

    // MARK: - Rewarded (B8: AI生成のゲートに使用)
    private var lastRewardedLoadError: String?

    func preloadRewarded() async {
        guard !isLoadingRewarded, rewarded == nil else { return }
        guard canMakeAdRequest(type: "rewarded") else { return }
        isLoadingRewarded = true
        defer { isLoadingRewarded = false }
        let unitId = AdMobConfig.rewardedUnitID
        NSLog("[AdMobService] preloadRewarded start unit=%@", unitId)
        do {
            rewarded = try await RewardedAd.load(with: unitId, request: Request())
            lastRewardedLoadError = nil
            rewardedRetryCount = 0
            NSLog("[AdMobService] rewarded loaded OK")
        } catch {
            rewarded = nil
            lastRewardedLoadError = String(describing: error)
            NSLog("[AdMobService] rewarded load FAILED: %@", lastRewardedLoadError ?? "")
            scheduleRewardedRetry()
        }
    }

    private func scheduleRewardedRetry() {
        guard rewardedRetryCount < AdMobService.maxRetries else {
            NSLog("[AdMobService] rewarded load: max retries reached, giving up")
            return
        }
        let delay = AdMobService.backoffSchedule[rewardedRetryCount]
        rewardedRetryCount += 1
        NSLog("[AdMobService] rewarded backoff: retry %d in %.0fs", rewardedRetryCount, delay)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            await self.preloadRewarded()
        }
    }

    // MARK: - Banner request gate (used by AdBannerView)
    fileprivate func canRequestBanner() -> Bool {
        return canMakeAdRequest(type: "banner")
    }

    /// リワード広告を提示し、ユーザーがリワード獲得したら true を返す
    /// - 広告未ロード時は短時間ロード試行 + 失敗したら false
    func presentRewarded(from viewController: UIViewController,
                        completion: @escaping (Bool) -> Void) {
        if rewarded == nil {
            Task { @MainActor in
                await self.preloadRewarded()
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

    /// リトライ付きリワード提示
    /// ロードできるまで `retries` 回 (各 `intervalSec` 秒) 試行する。
    /// AdMob の Mediation や fill rate の問題で広告が出ないケース対策。
    func presentRewardedWithRetry(from viewController: UIViewController,
                                  retries: Int,
                                  intervalSec: Double,
                                  completion: @escaping (Bool) -> Void) {
        Task { @MainActor in
            for attempt in 0...retries {
                if rewarded == nil {
                    NSLog("[AdMobService] retry attempt %d/%d - loading…", attempt + 1, retries + 1)
                    await self.preloadRewarded()
                }
                if let ad = self.rewarded {
                    self.showRewarded(ad: ad, from: viewController, completion: completion)
                    return
                }
                if attempt < retries {
                    NSLog("[AdMobService] retry attempt %d failed, waiting %.1fs", attempt + 1, intervalSec)
                    try? await Task.sleep(for: .seconds(intervalSec))
                }
            }
            NSLog("[AdMobService] all retry attempts exhausted, deny")
            completion(false)
        }
    }

    /// fullScreenContentDelegate ハンドラ - 広告 dismiss 時に earned で確定 completion を呼ぶ
    private var rewardedDelegate: RewardedAdDelegate?

    private func showRewarded(ad: RewardedAd, from vc: UIViewController,
                              completion: @escaping (Bool) -> Void) {
        // earned フラグを delegate と present completion で共有
        let delegate = RewardedAdDelegate { [weak self] earned in
            NSLog("[AdMobService] rewarded ad dismissed, earned=%@", String(earned))
            completion(earned)
            self?.rewardedDelegate = nil
        }
        // strong ref を保持 (delegate weak なので解放されると completion 呼ばれない)
        self.rewardedDelegate = delegate
        ad.fullScreenContentDelegate = delegate

        ad.present(from: vc) {
            // userDidEarnRewardHandler — 動画完走したときだけ呼ばれる
            delegate.earned = true
            NSLog("[AdMobService] rewarded ad earned (handler called)")
        }
        rewarded = nil
        Task { await preloadRewarded() }
    }
}

/// FullScreenContentDelegate — リワード広告の dismiss/fail を確実に拾う
private final class RewardedAdDelegate: NSObject, FullScreenContentDelegate {
    var earned: Bool = false
    private let onComplete: (Bool) -> Void
    private var completed = false

    init(onComplete: @escaping (Bool) -> Void) {
        self.onComplete = onComplete
    }

    private func finish(_ result: Bool) {
        guard !completed else { return }
        completed = true
        DispatchQueue.main.async { self.onComplete(result) }
    }

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        #if DEBUG
        print("[AdMob] rewarded adWillPresentFullScreenContent")
        #endif
    }

    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        #if DEBUG
        print("[AdMob] rewarded adDidRecordImpression")
        #endif
    }

    func adDidRecordClick(_ ad: FullScreenPresentingAd) {
        #if DEBUG
        print("[AdMob] rewarded adDidRecordClick")
        #endif
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        #if DEBUG
        print("[AdMob] rewarded adDidDismissFullScreenContent earned=\(earned)")
        #endif
        NSLog("[RewardedAdDelegate] adDidDismissFullScreenContent earned=%@", String(earned))
        finish(earned)
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        #if DEBUG
        let nsErr = error as NSError
        print("[AdMob] rewarded didFailToPresent code=\(nsErr.code) domain=\(nsErr.domain) msg=\(error.localizedDescription)")
        #endif
        NSLog("[RewardedAdDelegate] didFailToPresent error=%@", error.localizedDescription)
        finish(false)
    }
}

/// FullScreenContentDelegate for interstitial ads — diagnostic logging
private final class InterstitialFullScreenDelegate: NSObject, FullScreenContentDelegate {
    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        #if DEBUG
        print("[AdMob] interstitial adWillPresentFullScreenContent")
        #endif
    }

    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        #if DEBUG
        print("[AdMob] interstitial adDidRecordImpression")
        #endif
    }

    func adDidRecordClick(_ ad: FullScreenPresentingAd) {
        #if DEBUG
        print("[AdMob] interstitial adDidRecordClick")
        #endif
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        #if DEBUG
        print("[AdMob] interstitial adDidDismissFullScreenContent")
        #endif
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        #if DEBUG
        let nsErr = error as NSError
        print("[AdMob] interstitial didFailToPresent code=\(nsErr.code) domain=\(nsErr.domain) msg=\(error.localizedDescription)")
        #endif
    }
}

/// BannerViewDelegate — banner load/impression/click diagnostics
fileprivate final class BannerDelegate: NSObject, BannerViewDelegate {
    func bannerViewDidReceiveAd(_ bannerView: BannerView) {
        #if DEBUG
        let info = bannerView.responseInfo.map { String(describing: $0) } ?? "nil"
        print("[AdMob] banner loaded responseInfo=\(info)")
        #endif
    }

    func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
        #if DEBUG
        let nsErr = error as NSError
        let info = bannerView.responseInfo.map { String(describing: $0) } ?? "nil"
        print("[AdMob] banner failed code=\(nsErr.code) domain=\(nsErr.domain) msg=\(error.localizedDescription) responseInfo=\(info)")
        #endif
    }

    func bannerViewDidRecordImpression(_ bannerView: BannerView) {
        #if DEBUG
        print("[AdMob] banner impression")
        #endif
    }

    func bannerViewDidRecordClick(_ bannerView: BannerView) {
        #if DEBUG
        print("[AdMob] banner click")
        #endif
    }
}

// MARK: - SwiftUI Banner

struct AdBannerView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Coordinator が BannerView を保持し、SwiftUI 再描画でも単一のバナーを使い回す。
    /// バックグラウンド遷移の通知監視もここで行い、保留中ロードを抑止する。
    final class Coordinator {
        weak var banner: BannerView?
        var hasLoadedOnce = false
        var isAppActive: Bool = true
        var pendingLoadOnForeground = false
        var willResignObserver: NSObjectProtocol?
        var didBecomeActiveObserver: NSObjectProtocol?
        /// Strong ref to BannerDelegate (SDK holds delegate weakly).
        fileprivate var bannerDelegate: BannerDelegate?

        init() {
            willResignObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.isAppActive = false
            }
            didBecomeActiveObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.isAppActive = true
                if self.pendingLoadOnForeground, let b = self.banner {
                    self.pendingLoadOnForeground = false
                    if AdMobService.shared.canRequestBanner() {
                        b.load(Request())
                    }
                }
            }
        }

        deinit {
            if let o = willResignObserver { NotificationCenter.default.removeObserver(o) }
            if let o = didBecomeActiveObserver { NotificationCenter.default.removeObserver(o) }
        }
    }

    func makeUIView(context: Context) -> BannerView {
        // SwiftUI 再描画で makeUIView が再度呼ばれた場合、既存 banner があれば返す。
        if let existing = context.coordinator.banner {
            return existing
        }
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = AdMobConfig.bannerUnitID
        banner.rootViewController = Self.topViewController()
        // Attach delegate BEFORE the first load so we capture every callback.
        let delegate = BannerDelegate()
        context.coordinator.bannerDelegate = delegate
        banner.delegate = delegate
        #if DEBUG
        // Faint green tint so we can visually confirm the banner slot is on
        // screen with non-zero height even when the ad has not yet filled.
        banner.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.08)
        #endif
        context.coordinator.banner = banner

        // バックグラウンド時は load せず、フォアグラウンド復帰時にロードする。
        if context.coordinator.isAppActive {
            if AdMobService.shared.canRequestBanner() {
                banner.load(Request())
                context.coordinator.hasLoadedOnce = true
            }
        } else {
            context.coordinator.pendingLoadOnForeground = true
        }

        // NOTE: 旧実装の 30秒タイマー再ロードは削除済み。
        // モダン AdMob バナーは AdMob コンソールの refresh rate に従ってサーバー側で
        // 自動更新されるため、クライアント側の繰り返しロードは "Invalid Traffic" の温床。
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
