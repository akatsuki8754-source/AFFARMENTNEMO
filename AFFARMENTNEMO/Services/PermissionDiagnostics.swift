//
//  PermissionDiagnostics.swift
//  起動時に各種権限の現状をログ出力 + 設定画面で可視化
//  ユーザー懸念: シミュ再起動で権限がリセットされる気がする → 実機確認用に状態を見える化
//

import Foundation
import AppTrackingTransparency
import AVFoundation
import UserNotifications
import Combine

@MainActor
final class PermissionDiagnostics: ObservableObject {
    static let shared = PermissionDiagnostics()

    @Published var attStatusText: String = "未確認"
    @Published var notificationStatusText: String = "未確認"
    @Published var microphoneStatusText: String = "未確認"
    @Published var lastChecked: Date?

    func refresh() async {
        // ATT
        let att = ATTrackingManager.trackingAuthorizationStatus
        let attLabel: String
        switch att {
        case .notDetermined: attLabel = "未確定"
        case .restricted: attLabel = "制限あり"
        case .denied: attLabel = "拒否"
        case .authorized: attLabel = "許可"
        @unknown default: attLabel = "不明"
        }
        attStatusText = attLabel

        // 通知
        let center = UNUserNotificationCenter.current()
        let notif = await center.notificationSettings()
        let notifLabel: String
        switch notif.authorizationStatus {
        case .notDetermined: notifLabel = "未確定"
        case .denied: notifLabel = "拒否"
        case .authorized: notifLabel = "許可"
        case .provisional: notifLabel = "暫定"
        case .ephemeral: notifLabel = "一時的"
        @unknown default: notifLabel = "不明"
        }
        notificationStatusText = notifLabel

        // マイク
        let mic = AVAudioApplication.shared.recordPermission
        let micLabel: String
        switch mic {
        case .undetermined: micLabel = "未確定"
        case .denied: micLabel = "拒否"
        case .granted: micLabel = "許可"
        @unknown default: micLabel = "不明"
        }
        microphoneStatusText = micLabel

        lastChecked = Date()

        print("[Permissions] ATT=\(attLabel) Notification=\(notifLabel) Microphone=\(micLabel)")
    }
}
