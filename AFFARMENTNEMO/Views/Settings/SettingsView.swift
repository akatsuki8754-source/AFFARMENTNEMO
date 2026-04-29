//
//  SettingsView.swift
//  通知設定 / ヘルプ / アカウント削除
//

import SwiftUI

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
            .onAppear { loadTimes() }
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
