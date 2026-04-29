//
//  ATTService.swift
//  App Tracking Transparency 許可リクエスト
//  仕様: Apple Guideline 2.1 準拠 — AdMob 初期化前に必ず請求
//

import Foundation
import AppTrackingTransparency
import AdSupport
import UIKit

@MainActor
enum ATTService {
    /// 許可状態を返す。.notDetermined の場合のみダイアログを出す。
    /// 完了後にコールバック (許可/拒否のいずれにせよ AdMob 起動可)。
    static func requestAuthorizationIfNeeded(completion: @escaping () -> Void) {
        let status = ATTrackingManager.trackingAuthorizationStatus
        guard status == .notDetermined else {
            completion()
            return
        }
        // iOS の制約: アプリ起動直後の数秒は active scene が UIKit に伝わっていないと出ないことがある
        // → わずかにディレイを入れて確実にダイアログ表示
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            ATTrackingManager.requestTrackingAuthorization { result in
                DispatchQueue.main.async {
                    print("[ATTService] auth status: \(result.rawValue)")
                    completion()
                }
            }
        }
    }
}
