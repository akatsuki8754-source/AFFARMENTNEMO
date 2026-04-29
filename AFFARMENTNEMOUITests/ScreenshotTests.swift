//
//  ScreenshotTests.swift
//  オンボーディング → ホーム → 追加 → 音読 → ライブラリ → 設定 → ヘルプ の自動キャプチャ
//

import XCTest

final class ScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testCaptureFullFlow() throws {
        let app = XCUIApplication()

        // Springboard上の通知/トラッキング許可ダイアログを自動処理
        addUIInterruptionMonitor(withDescription: "System Dialog") { alert -> Bool in
            for label in ["許可", "Allow", "OK", "許可しない", "Don't Allow"] {
                let b = alert.buttons[label]
                if b.exists { b.tap(); return true }
            }
            return false
        }

        app.launch()

        // --- 01 Welcome ---
        sleep(2)
        attachScreenshot(name: "01_welcome")

        let startBtn = app.buttons["はじめる"]
        if startBtn.waitForExistence(timeout: 5) {
            startBtn.tap()
        }

        // --- 02 First affirmation empty ---
        sleep(1)
        attachScreenshot(name: "02_first_affirmation_empty")

        // テンプレ「習慣のキッカケ」を選択
        let ifThenTpl = app.buttons.containing(NSPredicate(format: "label CONTAINS '習慣のキッカケ'")).firstMatch
        if ifThenTpl.waitForExistence(timeout: 3) {
            ifThenTpl.tap()
            sleep(1)
        }

        // テキスト追記
        let editor = app.textViews.firstMatch
        if editor.waitForExistence(timeout: 3) {
            editor.tap()
            editor.typeText("\nもし朝起きたら、白湯を飲む")
            sleep(1)
        }
        attachScreenshot(name: "03_first_affirmation_filled")

        // キーボードを閉じる: 画面上部のタイトル領域をタップ
        // タイトル「最初の言葉を書いてみましょう」の付近をタップ
        let title = app.staticTexts["最初の言葉を書いてみましょう"]
        if title.exists {
            title.tap()
        } else {
            // 安全策: 画面上部の座標タップ
            let coord = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
            coord.tap()
        }
        sleep(1)

        let registerBtn = app.buttons["登録する"]
        if registerBtn.waitForExistence(timeout: 3) {
            registerBtn.tap()
        }

        // --- 03 Notification setup ---
        sleep(2)
        attachScreenshot(name: "04_notification_setup")

        let completeBtn = app.buttons["完了"]
        if completeBtn.waitForExistence(timeout: 3) {
            completeBtn.tap()
        }

        // SpringBoardレベルの通知許可ダイアログを直接処理
        sleep(3)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["許可", "Allow", "許可しない", "Don't Allow"] {
            let b = springboard.buttons[label]
            if b.waitForExistence(timeout: 2) {
                b.tap()
                break
            }
        }

        // 念押し: アプリをタップしてアラートをトリガー
        app.tap()

        // --- 04 Home ---
        sleep(3)
        attachScreenshot(name: "05_home")

        // --- 05 Add affirmation ---
        let addBtn = app.buttons.containing(NSPredicate(format: "label CONTAINS '言葉を追加'")).firstMatch
        if addBtn.waitForExistence(timeout: 3) {
            addBtn.tap()
            sleep(2)
            attachScreenshot(name: "06_add_affirmation")
            let cancelBtn = app.buttons["キャンセル"]
            if cancelBtn.waitForExistence(timeout: 2) {
                cancelBtn.tap()
            }
        }

        // --- 06 Read aloud ---
        sleep(2)
        let readBtn = app.buttons.containing(NSPredicate(format: "label CONTAINS '音読する'")).firstMatch
        if readBtn.waitForExistence(timeout: 3) {
            readBtn.tap()
            sleep(2)
            attachScreenshot(name: "07_read_aloud")
            let doneBtn = app.buttons.containing(NSPredicate(format: "label CONTAINS '読みました'")).firstMatch
            if doneBtn.waitForExistence(timeout: 3) {
                doneBtn.tap()
                sleep(3)
                attachScreenshot(name: "08_read_complete")
                let homeBtn = app.buttons["ホームへ"]
                if homeBtn.waitForExistence(timeout: 3) {
                    homeBtn.tap()
                }
            }
        }

        sleep(2)

        // --- 07 Library ---
        let libraryTab = app.tabBars.buttons["一覧"]
        if libraryTab.waitForExistence(timeout: 3) {
            libraryTab.tap()
            sleep(1)
            attachScreenshot(name: "09_library")
        }

        // --- 08 Settings ---
        let settingsTab = app.tabBars.buttons["設定"]
        if settingsTab.waitForExistence(timeout: 3) {
            settingsTab.tap()
            sleep(1)
            attachScreenshot(name: "10_settings")

            let helpRow = app.buttons.containing(NSPredicate(format: "label CONTAINS '書き方のコツ'")).firstMatch
            if helpRow.waitForExistence(timeout: 3) {
                helpRow.tap()
                sleep(1)
                attachScreenshot(name: "11_help")
            }
        }
    }

    private func attachScreenshot(name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
