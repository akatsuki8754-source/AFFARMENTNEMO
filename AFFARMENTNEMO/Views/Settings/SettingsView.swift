//
//  SettingsView.swift
//  通知設定 / ヘルプ / アカウント削除
//

import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AffirmationStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @AppStorage("kotodama.notif.morningEnabled") private var morningEnabled: Bool = true
    @AppStorage("kotodama.notif.eveningEnabled") private var eveningEnabled: Bool = false
    @AppStorage("kotodama.notif.morningHour") private var morningHour: Int = 7
    @AppStorage("kotodama.notif.morningMinute") private var morningMinute: Int = 0
    @AppStorage("kotodama.notif.eveningHour") private var eveningHour: Int = 22
    @AppStorage("kotodama.notif.eveningMinute") private var eveningMinute: Int = 0

    @State private var morningTime: Date = Date()
    @State private var eveningTime: Date = Date()
    @State private var showHelp = false
    @State private var showResetConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showBlockList = false
    @State private var showEULA = false
    @State private var showContact = false
    @StateObject private var ttsPrefs = TTSPreferences.shared
    @StateObject private var perms = PermissionDiagnostics.shared
    @AppStorage("kotodama.appLanguage") private var appLanguage: String = "system"

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("settings.notif")) {
                    Toggle(isOn: $morningEnabled) { Text("notif.slot.morning") }
                    if morningEnabled {
                        DatePicker("notif.slot.morning",
                                   selection: $morningTime,
                                   displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    Toggle(isOn: $eveningEnabled) { Text("notif.slot.evening") }
                    if eveningEnabled {
                        DatePicker("notif.slot.evening",
                                   selection: $eveningTime,
                                   displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    Button {
                        applyNotificationSettings()
                    } label: {
                        Text("settings.notif.apply")
                    }
                }

                // ユーザー要望: アプリ内言語切替
                Section(header: Text("言語")) {
                    Picker("アプリの言語", selection: $appLanguage) {
                        Text("システム言語に従う").tag("system")
                        Text("日本語").tag("ja")
                        Text("English").tag("en")
                        Text("中文 (简)").tag("zh-Hans")
                        Text("中文 (繁)").tag("zh-Hant")
                        Text("한국어").tag("ko")
                    }
                    Text("変更後はアプリを再起動すると反映されます")
                        .appFont(.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                Section(header: Text("AI音声 (TTS)")) {
                    let voices = ttsPrefs.availableVoices()
                    Picker("声", selection: Binding(
                        get: { ttsPrefs.selectedVoiceId ?? "" },
                        set: { ttsPrefs.selectedVoiceId = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("自動 (端末の言語)").tag("")
                        ForEach(voices) { v in
                            Text("\(v.language) / \(v.name) (\(v.gender) ・\(v.quality))")
                                .tag(v.id)
                        }
                    }
                    Button {
                        ttsPrefs.preview(voiceId: ttsPrefs.selectedVoiceId)
                    } label: {
                        Label("試しに再生", systemImage: "play.circle")
                    }
                }

                // ユーザー要望: アプリ起動時に自動で読み上げる
                Section(header: Text("起動時の自動再生")) {
                    Toggle(isOn: $ttsPrefs.autoplayOnLaunch) {
                        Text("アプリ起動時に音読を自動再生")
                    }
                    if ttsPrefs.autoplayOnLaunch {
                        Picker("再生方法", selection: $ttsPrefs.autoplayMode) {
                            Text("自分で読む").tag("self")
                            Text("AIで再生").tag("ai")
                            Text("録音で再生").tag("recorded")
                        }
                    }
                }

                // ユーザー要望: 権限の現状を可視化 (シミュリセット問題確認用)
                Section(header: Text("権限ステータス (端末設定)")) {
                    LabeledContent("広告トラッキング", value: perms.attStatusText)
                    LabeledContent("通知", value: perms.notificationStatusText)
                    LabeledContent("マイク", value: perms.microphoneStatusText)
                    Button {
                        Task { await perms.refresh() }
                    } label: {
                        Label("再確認", systemImage: "arrow.clockwise")
                    }
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("システム設定を開く", systemImage: "gearshape.2")
                    }
                }

                Section(header: Text("settings.help")) {
                    Button {
                        showHelp = true
                    } label: {
                        HStack {
                            Image(systemName: "book")
                            Text("settings.help.tips")
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Color.textSecondary)
                        }
                    }
                    .foregroundStyle(Color.textPrimary)

                    Button {
                        showEULA = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.plaintext")
                            Text("settings.eula")
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Color.textSecondary)
                        }
                    }
                    .foregroundStyle(Color.textPrimary)

                    Button {
                        showContact = true
                    } label: {
                        HStack {
                            Image(systemName: "envelope")
                            Text("settings.contact")
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Color.textSecondary)
                        }
                    }
                    .foregroundStyle(Color.textPrimary)
                }

                Section(header: Text("settings.privacy")) {
                    Button {
                        showBlockList = true
                    } label: {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.xmark")
                            Text("settings.blockedUsers")
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Color.textSecondary)
                        }
                    }
                    .foregroundStyle(Color.textPrimary)
                }

                Section(header: Text("settings.about")) {
                    HStack {
                        Text("settings.version")
                        Spacer()
                        Text(versionString)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("settings.account.delete", systemImage: "trash")
                    }
                }
            }
            .navigationTitle(Text("settings.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("common.close") }
                }
            }
            .sheet(isPresented: $showHelp) { HelpView() }
            .sheet(isPresented: $showEULA) { EULAView() }
            .sheet(isPresented: $showContact) { ContactView() }
            .sheet(isPresented: $showBlockList) { BlockListView() }
            .alert("settings.account.delete.confirm.title",
                   isPresented: $showDeleteConfirm) {
                Button("common.cancel", role: .cancel) {}
                Button("settings.account.delete", role: .destructive) {
                    store.deleteAll()
                    NotificationService.shared.cancelAll()
                    UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
                    dismiss()
                }
            } message: {
                Text("settings.account.delete.confirm.body")
            }
            .onAppear {
                loadTimes()
                Task { await perms.refresh() }
            }
        }
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private func loadTimes() {
        let cal = Calendar.current
        morningTime = cal.date(bySettingHour: morningHour, minute: morningMinute, second: 0, of: Date()) ?? Date()
        eveningTime = cal.date(bySettingHour: eveningHour, minute: eveningMinute, second: 0, of: Date()) ?? Date()
    }

    private func applyNotificationSettings() {
        let cal = Calendar.current
        morningHour = cal.component(.hour, from: morningTime)
        morningMinute = cal.component(.minute, from: morningTime)
        eveningHour = cal.component(.hour, from: eveningTime)
        eveningMinute = cal.component(.minute, from: eveningTime)
        Task {
            _ = await NotificationService.shared.requestAuthorization()
            NotificationService.shared.scheduleDaily(
                morningEnabled: morningEnabled,
                morningHour: morningHour, morningMinute: morningMinute,
                eveningEnabled: eveningEnabled,
                eveningHour: eveningHour, eveningMinute: eveningMinute
            )
        }
    }
}
