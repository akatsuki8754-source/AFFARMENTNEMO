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
    /// 真因対策: UNCalendarNotificationTrigger は dateMatching に hour/minute だけだと
    /// 一部 iOS バージョンで動作不安定。second=0 を明示し、Calendar も明示する。
    func scheduleDaily(morningEnabled: Bool, morningHour: Int, morningMinute: Int,
                       eveningEnabled: Bool, eveningHour: Int, eveningMinute: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [
            NotificationSlot.morning.identifier,
            NotificationSlot.evening.identifier
        ])

        // 既存リクエストの確認 (デバッグ用)
        center.getPendingNotificationRequests { reqs in
            NSLog("[NotificationService] pending after remove: \(reqs.count)")
        }

        if morningEnabled {
            let content = UNMutableNotificationContent()
            content.title = randomMorningTitle()
            content.body = randomMorningBody()
            content.sound = .default
            content.userInfo = ["slot": "morning"]
            var comps = DateComponents()
            comps.calendar = Calendar(identifier: .gregorian)
            comps.timeZone = TimeZone.current
            comps.hour = morningHour
            comps.minute = morningMinute
            comps.second = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let req = UNNotificationRequest(identifier: NotificationSlot.morning.identifier,
                                            content: content, trigger: trigger)
            center.add(req) { err in
                if let err = err {
                    NSLog("[NotificationService] morning add error: \(err.localizedDescription)")
                } else {
                    NSLog("[NotificationService] morning scheduled at \(morningHour):\(String(format: "%02d", morningMinute))")
                }
            }
        }

        if eveningEnabled {
            let content = UNMutableNotificationContent()
            content.title = randomEveningTitle()
            content.body = randomEveningBody()
            content.sound = .default
            content.userInfo = ["slot": "evening"]
            var comps = DateComponents()
            comps.calendar = Calendar(identifier: .gregorian)
            comps.timeZone = TimeZone.current
            comps.hour = eveningHour
            comps.minute = eveningMinute
            comps.second = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let req = UNNotificationRequest(identifier: NotificationSlot.evening.identifier,
                                            content: content, trigger: trigger)
            center.add(req) { err in
                if let err = err {
                    NSLog("[NotificationService] evening add error: \(err.localizedDescription)")
                } else {
                    NSLog("[NotificationService] evening scheduled at \(eveningHour):\(String(format: "%02d", eveningMinute))")
                }
            }
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

    // MARK: - Notification copy rotation (50+ パターン)
    //
    // 行動経済学・マーケ・営業根拠:
    // - Cialdini "好奇心" / 「不完全な情報」: 質問形 → 開封率↑
    // - 損失回避 (Kahneman): 「逃すと…」 / 「今だけ」
    // - 自己関連性 (Self-Relevance): 「あなたの言葉」「私の朝」
    // - 短文 (FOGG model B=MAP の Ability↑): 文字数を絞る
    // - ループ閉鎖 (Zeigarnik): 「30秒だけ」「1分で」 — 完了可能感
    // - パーソナライズ (Personalization Effect): 名前/数字差し込み
    //
    // タイトル/本文ペアではなく独立ローテーションで日替わり感を演出
    // 文字制限: タイトル ≤22 字, 本文 ≤45 字 (iOS バナー 2 行表示)

    private func randomMorningTitle() -> String {
        let titles = [
            "おはよう、今日の言葉が届いてるよ",
            "朝の30秒、自分にプレゼントを",
            "🌅 1分で今日のスイッチを入れよう",
            "今日のあなたは、誰になりたい？",
            "朝の言葉、もう読んだ？",
            "今日もいい一日にする魔法",
            "✨ 朝イチの30秒を投資しない？",
            "あなたの言葉が待ってるよ",
            "今日の自分を呼び起こそう",
            "朝の3秒で、流れを変える",
            "なりたい自分、もう近くにいるよ",
            "今日の方向、決めた？",
            "30秒で、今日が変わる",
            "朝の儀式、始めようか",
            "あなたの一日を、言葉で整える",
            "🌱 今日の小さな一歩、踏み出そう",
            "今日の言葉、見た瞬間に変わる",
            "おはよう。3日坊主、もう卒業だよ",
            "コーヒー前の、30秒",
            "今日のあなたの宣言は？",
            "🌟 朝の言葉が、夜まで効く",
            "1日1回、自分を肯定する時間",
            "今日のスタート、整える？",
            "あなたが選ぶ、今日の言葉",
            "朝の30秒投資、続いてる？",
        ]
        return titles.randomElement()!
    }

    private func randomMorningBody() -> String {
        let bodies = [
            "声に出すと脳が動く。今日のあなたへ。",
            "30秒の音読が、行動を引き寄せる。",
            "今日のあなたへ、3つの言葉を選んだよ。",
            "朝1分の宣言で、夜の自分が変わる。",
            "なりたい姿に、声でアクセス。",
            "音読は1日1回。今がそのとき。",
            "脳のスイッチを言葉でオンに。",
            "目覚めたら、まず自分を認めよう。",
            "今日のあなたを、言葉で整える。",
            "1分の音読で、午前中が変わる。",
            "Stanford 研究: 音読は脳の信頼度を上げる。",
            "声に出した言葉だけが、行動になる。",
            "今すぐ、3日坊主を卒業しよう。",
            "朝の言葉が、夜まで効く。",
            "誰かのためじゃなく、自分のために。",
        ]
        return bodies.randomElement()!
    }

    private func randomEveningTitle() -> String {
        let titles = [
            "おつかれさま。1分で1日を締めよう",
            "夜の言葉、明日の準備に",
            "🌙 今日の自分、認めてあげよう",
            "明日のあなたを、今夜整える",
            "今日もよく頑張った。最後にひとこと",
            "明日のスタートを、今夜決める",
            "今日のリセット、始めようか",
            "🌃 寝る前の30秒儀式",
            "今日の自分にありがとうを",
            "明日のあなたに送る言葉",
            "夜の音読で、深く眠る",
            "今日の終わりに、自分を肯定",
            "1日のクロージング、しよう",
            "明日の朝が、今夜決まる",
            "🌒 寝る前の3秒チェックイン",
            "今日もよくやった。声に出そう",
            "明日のあなたへ、メッセージ",
            "1日のご褒美の言葉",
            "🛌 おやすみ前の30秒",
            "今夜の言葉が、明日を作る",
            "今日の自分を抱きしめよう",
            "🌌 寝る前の自己肯定タイム",
            "明日が楽しみになる言葉",
            "1日のリセットボタン",
            "今夜のクロージング、忘れずに",
        ]
        return titles.randomElement()!
    }

    private func randomEveningBody() -> String {
        let bodies = [
            "30秒の音読で、ぐっすり眠れる。",
            "夜の言葉が、明日の朝を作る。",
            "今日もよくやった。最後にひとこと。",
            "寝る前の音読は、潜在意識に届く。",
            "明日のあなたを、今夜整えよう。",
            "Seligman 研究: 夜の感謝で幸福度↑。",
            "今日の感謝3つ、書く前に1つ読もう。",
            "声に出して、1日を閉じよう。",
            "30秒だけ、自分のために。",
            "明日が楽しみになる言葉、選んだ？",
            "夜の音読は、深い睡眠の合図。",
            "今日の自分を、声で認めよう。",
            "1分のクロージングで、明日が変わる。",
            "今日もよくやった。ぐっすり眠ろう。",
            "明日のあなたへ、ひとこと残そう。",
        ]
        return bodies.randomElement()!
    }
}
