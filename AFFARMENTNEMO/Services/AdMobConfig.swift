//
//  AdMobConfig.swift
//  広告ユニットID集約 + 頻度キャップ管理
//  仕様: 02_開発仕様書 §10 / 企画書 §7.2
//
//  ⚠️ AdMob SDK は Xcode で SPM 追加が必要:
//     File > Add Package Dependencies > https://github.com/googleads/swift-package-manager-google-mobile-ads
//     SDK が無くてもビルド可能 (#if canImport で分岐)
//

import Foundation

enum AdMobConfig {
    // MARK: - App ID (Info.plist の GADApplicationIdentifier に設定が必要)
    static let appID = "ca-app-pub-2846643868790302~2643315135"

    // MARK: - Production unit IDs
    enum Production {
        static let banner          = "ca-app-pub-2846643868790302/6897646101"
        static let interstitial1   = "ca-app-pub-2846643868790302/9886860816"
        static let interstitial2   = "ca-app-pub-2846643868790302/8350417861"
        static let rewarded        = "ca-app-pub-2846643868790302/1067569075"
        static let nativeAdvanced  = "ca-app-pub-2846643868790302/5309321556"
        static let appOpen         = "ca-app-pub-2846643868790302/1194816721"
    }

    // MARK: - Test unit IDs (Google公式)
    enum Test {
        static let banner          = "ca-app-pub-3940256099942544/2934735716"  // iOS Banner
        static let interstitial    = "ca-app-pub-3940256099942544/4411468910"  // iOS Interstitial
        static let rewarded        = "ca-app-pub-3940256099942544/1712485313"  // iOS Rewarded
        static let nativeAdvanced  = "ca-app-pub-3940256099942544/3986624511"  // iOS Native Advanced
        static let appOpen         = "ca-app-pub-3940256099942544/5575463023"  // iOS App Open
    }

    // MARK: - Resolve IDs
    /// DEBUGビルドではテストID、Releaseでは本番ID
    static var bannerUnitID: String {
        #if DEBUG
        return Test.banner
        #else
        return Production.banner
        #endif
    }

    static var interstitialUnitID: String {
        #if DEBUG
        return Test.interstitial
        #else
        return Production.interstitial1
        #endif
    }

    static var rewardedUnitID: String {
        #if DEBUG
        return Test.rewarded
        #else
        return Production.rewarded
        #endif
    }

    // MARK: - 頻度キャップ
    /// インタースティシャル: 1日3回上限 (仕様 §7.2)
    static let interstitialDailyCap: Int = 3
    /// 初期3日間はインタースティシャル抑制 (UX v4 §5.2)
    static let interstitialDelayDays: Int = 3
}

/// インタースティシャル頻度キャップの実装
@MainActor
final class InterstitialPolicy {
    static let shared = InterstitialPolicy()

    private let countKey = "kotodama.interstitial.dailyCount"
    private let dateKey  = "kotodama.interstitial.dailyDate"

    /// 表示してよいか?
    func canShow(stats: UserStats) -> Bool {
        guard stats.interstitialEnabled else { return false }  // 初期3日抑制
        rotateIfNewDay()
        let count = UserDefaults.standard.integer(forKey: countKey)
        return count < AdMobConfig.interstitialDailyCap
    }

    /// 表示記録
    func recordShown() {
        rotateIfNewDay()
        let count = UserDefaults.standard.integer(forKey: countKey)
        UserDefaults.standard.set(count + 1, forKey: countKey)
    }

    private func rotateIfNewDay() {
        let today = ReadLog.todayKey()
        let lastDate = UserDefaults.standard.string(forKey: dateKey)
        if lastDate != today {
            UserDefaults.standard.set(today, forKey: dateKey)
            UserDefaults.standard.set(0, forKey: countKey)
        }
    }
}
