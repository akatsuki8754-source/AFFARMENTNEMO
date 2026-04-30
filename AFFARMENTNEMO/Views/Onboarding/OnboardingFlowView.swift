//
//  OnboardingFlowView.swift
//  3画面 (Welcome -> First Affirmation -> Notification) を縦遷移
//  仕様: UX v4 §2
//

import SwiftUI

struct OnboardingFlowView: View {
    @Environment(AffirmationStore.self) private var store
    @AppStorage("kotodama.onboarding.completed") private var completed: Bool = false

    @State private var step: Int = 0  // 0=splash, 1=welcome, 2=first, 3=notif
    @State private var firstText: String = ""
    @State private var selectedTemplate: AffirmationTemplate?
    @State private var morningEnabled: Bool = true   // UX §2.4: 朝のみON
    @State private var eveningEnabled: Bool = false
    @State private var morningTime: Date = Self.defaultMorning
    @State private var eveningTime: Date = Self.defaultEvening

    static var defaultMorning: Date {
        Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    }
    static var defaultEvening: Date {
        Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date()) ?? Date()
    }

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            switch step {
            case 0:
                SplashStep().task {
                    try? await Task.sleep(for: .seconds(1))
                    withAnimation(.easeInOut(duration: 0.3)) { step = 1 }
                }
            case 1:
                WelcomeStep(onContinue: { withAnimation { step = 2 } })
            case 2:
                FirstAffirmationStep(
                    text: $firstText,
                    selectedTemplate: $selectedTemplate,
                    onSubmit: {
                        saveFirstAffirmation()
                        withAnimation { step = 3 }
                    },
                    onSkip: { withAnimation { step = 3 } }
                )
            case 3:
                NotificationStep(
                    morningEnabled: $morningEnabled,
                    eveningEnabled: $eveningEnabled,
                    morningTime: $morningTime,
                    eveningTime: $eveningTime,
                    onComplete: {
                        Task { await complete() }
                    }
                )
            default:
                EmptyView()
            }
        }
    }

    private func saveFirstAffirmation() {
        let trimmed = firstText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let mode = selectedTemplate?.internalMode ?? "affirmation"
        let category = selectedTemplate?.category ?? .selfAffirm
        store.add(
            text: trimmed,
            internalMode: mode,
            templateUsed: selectedTemplate?.id,
            category: category,
            morningEnabled: true,
            eveningEnabled: false
        )
    }

    private func complete() async {
        // 通知許可ダイアログ (UX v4 §2.4: [完了] の後にOSダイアログ)
        if morningEnabled || eveningEnabled {
            _ = await NotificationService.shared.requestAuthorization()
            let cal = Calendar.current
            let mh = cal.component(.hour, from: morningTime)
            let mm = cal.component(.minute, from: morningTime)
            let eh = cal.component(.hour, from: eveningTime)
            let em = cal.component(.minute, from: eveningTime)
            NotificationService.shared.scheduleDaily(
                morningEnabled: morningEnabled, morningHour: mh, morningMinute: mm,
                eveningEnabled: eveningEnabled, eveningHour: eh, eveningMinute: em
            )
        }
        completed = true
    }
}

// MARK: - Step 0: Splash

private struct SplashStep: View {
    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()
            Image(systemName: "quote.bubble.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Color.brandAccent)
            Text("app.name")
                .appFont(.h1)
                .foregroundStyle(Color.textPrimary)
            Text("splash.tagline")
                .appFont(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, AppSpacing.screenEdge)
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStep: View {
    let onContinue: () -> Void

    var body: some View {
        welcomeContent.responsivePage()
    }

    /// Hybrid alignment: Hero (title/sub) は中央寄せで「飲み込みやすさ」最大化、
    /// Bullet 本文は左寄せで読戻り負荷を減らす (NN/g F-pattern + Ling 2007)
    private var welcomeContent: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer().frame(height: AppSpacing.xxl)

            // Hero (中央寄せ — 7秒で価値訴求)
            VStack(spacing: AppSpacing.sm) {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.brandAccent)
                    .padding(.bottom, AppSpacing.xs)

                Text("welcome.title")
                    .appFont(.display)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                Text("welcome.sub")
                    .appFont(.body)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            .frame(maxWidth: .infinity)

            // Body (左寄せ — リスト形式は左寄せが視認性最高)
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                BulletRow(titleKey: "welcome.bullet1.title", bodyKey: "welcome.bullet1.body")
                BulletRow(titleKey: "welcome.bullet2.title", bodyKey: "welcome.bullet2.body")
                BulletRow(titleKey: "welcome.bullet3.title", bodyKey: nil)
            }
            .padding(.vertical, AppSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            PrimaryButton(titleKey: "onboard.start", action: onContinue)
        }
        .padding(.horizontal, AppSpacing.screenEdge)
        .padding(.bottom, AppSpacing.lg)
    }
}

private struct BulletRow: View {
    let titleKey: LocalizedStringKey
    let bodyKey: LocalizedStringKey?

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.semanticSuccess)
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey)
                    .appFont(.bodyEmphasis)
                    .foregroundStyle(Color.textPrimary)
                if let bodyKey {
                    Text(bodyKey)
                        .appFont(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }
}

// MARK: - Step 2: First Affirmation

private struct FirstAffirmationStep: View {
    @Binding var text: String
    @Binding var selectedTemplate: AffirmationTemplate?
    let onSubmit: () -> Void
    let onSkip: () -> Void

    @FocusState private var focused: Bool
    @State private var showReplaceConfirm: Bool = false
    @State private var pendingTemplate: AffirmationTemplate?
    @State private var insertionFeedback: String? = nil
    private let maxLen = 200

    var body: some View {
        firstContent.responsivePage()
            .alert("テンプレートを使う?", isPresented: $showReplaceConfirm, presenting: pendingTemplate) { tpl in
                Button("キャンセル", role: .cancel) {
                    pendingTemplate = nil
                }
                Button("置き換える", role: .destructive) {
                    performInsert(tpl)
                    pendingTemplate = nil
                }
            } message: { _ in
                Text("入力中の文字はクリアされます。")
            }
    }

    private var firstContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // 進捗インジケータ 1/2 (MASTER §10.3)
            Text("onboard.step.1")
                .appFont(.micro)
                .foregroundStyle(Color.textSecondary)

            HStack {
                Text("first.title")
                    .appFont(.h2)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }

            Text("first.subtitle")
                .appFont(.caption)
                .foregroundStyle(Color.textSecondary)

            TextEditor(text: $text)
                .focused($focused)
                .appFont(.body)
                .scrollContentBackground(.hidden)
                .padding(AppSpacing.sm)
                .frame(minHeight: 140)
                .background(Color.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.buttonSecondary, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("first.placeholder")
                            .appFont(.body)
                            .foregroundStyle(Color.textDisabled)
                            .padding(AppSpacing.sm + 4)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: text) { _, new in
                    if new.count > maxLen { text = String(new.prefix(maxLen)) }
                }

            HStack {
                Spacer()
                Text("\(text.count) / \(maxLen)")
                    .appFont(.micro)
                    .foregroundStyle(Color.textSecondary)
            }

            Divider().padding(.vertical, AppSpacing.xs)

            Text("first.template.hint")
                .appFont(.caption)
                .foregroundStyle(Color.textSecondary)

            templateGrid

            if let feedback = insertionFeedback {
                Label(feedback, systemImage: "checkmark.circle.fill")
                    .appFont(.caption)
                    .foregroundStyle(Color.semanticSuccess)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer()

            HStack(spacing: AppSpacing.md) {
                SecondaryButton(titleKey: "common.skip", action: onSkip)
                // MASTER §10.3: ボタンは「次へ」、空でも進める
                PrimaryButton(
                    titleKey: "common.next",
                    action: {
                        focused = false
                        onSubmit()
                    }
                )
            }
        }
        .padding(.horizontal, AppSpacing.screenEdge)
        .padding(.top, AppSpacing.lg)
        .padding(.bottom, AppSpacing.lg)
    }

    private var templateGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 140), spacing: AppSpacing.sm)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.sm) {
            ForEach(AffirmationTemplate.all) { tpl in
                Button {
                    insertTemplate(tpl)
                } label: {
                    HStack(spacing: 4) {
                        Text(LocalizedStringKey(tpl.nameKey))
                            .appFont(.caption)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        if tpl.isStarred {
                            Text("⭐")
                                .font(.system(size: 11))
                        }
                    }
                    .padding(.horizontal, AppSpacing.sm + 2)
                    .padding(.vertical, AppSpacing.sm)
                    .frame(minHeight: AppTouchTarget.minimum)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedTemplate?.id == tpl.id ? Color.brandAccent.opacity(0.2) : Color.bgTertiary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selectedTemplate?.id == tpl.id ? Color.brandAccent : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// テンプレ選択 — 入力欄が空 → 即挿入 / 既に文字あり → 確認後置換
    /// (Apple HIG: 破壊的操作は確認、空状態はワンタップで使えるように)
    private func insertTemplate(_ tpl: AffirmationTemplate) {
        // 同じテンプレを2回タップ → 解除
        if selectedTemplate?.id == tpl.id {
            selectedTemplate = nil
            withAnimation { insertionFeedback = nil }
            return
        }

        selectedTemplate = tpl
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            performInsert(tpl)
        } else if !tpl.placeholderText.isEmpty {
            pendingTemplate = tpl
            showReplaceConfirm = true
        } else {
            // ビジネスの計画など placeholder 空のテンプレ — 選択のみ
            withAnimation { insertionFeedback = "テンプレートを選択しました" }
            scheduleFeedbackDismiss()
        }
    }

    private func performInsert(_ tpl: AffirmationTemplate) {
        if !tpl.placeholderText.isEmpty {
            text = tpl.placeholderText
            withAnimation { insertionFeedback = "ひな型を挿入しました — 続きを入力してください" }
        } else {
            withAnimation { insertionFeedback = "テンプレートを選択しました" }
        }
        focused = true
        scheduleFeedbackDismiss()
    }

    private func scheduleFeedbackDismiss() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            withAnimation { insertionFeedback = nil }
        }
    }
}

// MARK: - Step 3: Notification Setup

private struct NotificationStep: View {
    @Binding var morningEnabled: Bool
    @Binding var eveningEnabled: Bool
    @Binding var morningTime: Date
    @Binding var eveningTime: Date
    let onComplete: () -> Void

    var body: some View {
        notifContent.responsivePage()
    }

    private var notifContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            // 進捗インジケータ 2/2 (MASTER §10.4)
            Text("onboard.step.2")
                .appFont(.micro)
                .foregroundStyle(Color.textSecondary)

            Text("notif.title")
                .appFont(.h2)
                .foregroundStyle(Color.textPrimary)

            Text("notif.body")
                .appFont(.body)
                .foregroundStyle(Color.textSecondary)

            VStack(spacing: AppSpacing.md) {
                slotRow(
                    titleKey: "notif.slot.morning",
                    enabled: $morningEnabled,
                    time: $morningTime
                )
                slotRow(
                    titleKey: "notif.slot.evening",
                    enabled: $eveningEnabled,
                    time: $eveningTime
                )
            }

            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.semanticInfo)
                Text("notif.cap.note")
                    .appFont(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            PrimaryButton(titleKey: "common.complete", action: onComplete)

            Text("notif.permission.note")
                .appFont(.caption)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, AppSpacing.screenEdge)
        .padding(.top, AppSpacing.lg)
        .padding(.bottom, AppSpacing.lg)
    }

    private func slotRow(titleKey: LocalizedStringKey,
                         enabled: Binding<Bool>,
                         time: Binding<Date>) -> some View {
        HStack {
            Text(titleKey)
                .appFont(.bodyEmphasis)
                .foregroundStyle(Color.textPrimary)
                .frame(width: 60, alignment: .leading)

            Toggle("", isOn: enabled)
                .labelsHidden()
                .tint(Color.brandSecondary)

            Spacer()

            DatePicker("", selection: time, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .disabled(!enabled.wrappedValue)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.buttonSecondary))
    }
}
