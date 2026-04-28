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

    func start() {
        MobileAds.shared.start(completionHandler: nil)
        Task { await preloadInterstitial() }
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
}

// MARK: - SwiftUI Banner

struct AdBannerView: UIViewRepresentable {
    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = AdMobConfig.bannerUnitID
        banner.rootViewController = Self.topViewController()
        banner.load(Request())
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
    var body: some View {
        AdBannerView()
            .frame(height: 50)
            .frame(maxWidth: .infinity)
    }
}
