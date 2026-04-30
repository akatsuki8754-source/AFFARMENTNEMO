//
//  NotificationService.swift
//  朝・夜のローカル通知 (UNUserNotificationCenter)
//  仕様: UX v4 §2.4 (デフォルト朝のみON), 通知文言 §15.3
//

import Foundation
import UserNotifications

enum NotificationSlot: String {
    case morning, evening

    var identifier: String {
        switch self {
        case .morning: "kotodama.morning"
        case .evening: "kotodama.evening"
        }
    }
}

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // MARK: - Schedule

    /// 朝/夜の通知を再設定 (既存をキャンセルしてから再登録)
    func scheduleDaily(morningEnabled: Bool, morningHour: Int, morningMinute: Int,
                       eveningEnabled: Bool, eveningHour: Int, eveningMinute: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [
            NotificationSlot.morning.identifier,
            NotificationSlot.evening.identifier
        ])

        if morningEnabled {
            let content = UNMutableNotificationContent()
            content.title = randomMorningTitle()
            content.body = NSLocalizedString("notif.morning.body", comment: "")
            content.sound = .default
            var comps = DateComponents()
            comps.hour = morningHour
            comps.minute = morningMinute
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let req = UNNotificationRequest(identifier: NotificationSlot.morning.identifier,
                                            content: content, trigger: trigger)
            center.add(req)
        }

        if eveningEnabled {
            let content = UNMutableNotificationContent()
            content.title = randomEveningTitle()
            content.body = NSLocalizedString("notif.evening.body", comment: "")
            content.sound = .default
            var comps = DateComponents()
            comps.hour = eveningHour
            comps.minute = eveningMinute
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let req = UNNotificationRequest(identifier: NotificationSlot.evening.identifier,
                                            content: content, trigger: trigger)
            center.add(req)
        }
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Tap handling

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        Task { @MainActor in
            if identifier == NotificationSlot.morning.identifier ||
                identifier == NotificationSlot.evening.identifier {
                RoutinePlaybackRouter.shared.requestPlayback(mode: .ai)
            }
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    // MARK: - Title rotation (UX v4 §15.3)

    private func randomMorningTitle() -> String {
        let keys = ["notif.morning.t1", "notif.morning.t2", "notif.morning.t3"]
        return NSLocalizedString(keys.randomElement()!, comment: "")
    }

    private func randomEveningTitle() -> String {
        let keys = ["notif.evening.t1", "notif.evening.t2", "notif.evening.t3"]
        return NSLocalizedString(keys.randomElement()!, comment: "")
    }
}
