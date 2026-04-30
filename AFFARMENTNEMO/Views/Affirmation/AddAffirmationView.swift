//
//  AddAffirmationView.swift
//  アファメ追加: テキストエリア + テンプレ展開 + スマートヒント
//  仕様: UX v4 §3-4
//

import SwiftUI

private let addWeekdayLabels = ["日", "月", "火", "水", "木", "金", "土"]

struct AddAffirmationView: View {
    @Environment(AffirmationStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @State private var selectedTemplate: AffirmationTemplate?
    @State private var category: AffirmationCategoryKind
    @State private var customCategoryName: String = ""
    @State private var includeInRoutine: Bool = true
    @State private var hasStartDate: Bool = false
    @State private var startDate: Date = Date()
    @State private var hasEndDate: Bool = false
    @State private var endDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var weekdayMask: Int = 127
    @State private var templateExpanded: Bool = false
    @State private var hint: SmartHint?
    @State private var hintDismissedThisSession: Bool = false
    @State private var recordingFileName: String?
    @State private var pendingId: UUID = UUID()
    @AppStorage("kotodama.draft.text") private var draftText: String = ""
    @State private var initialText: String = ""
    @State private var showCancelConfirm: Bool = false
    @State private var showAIWizard: Bool = false

    @FocusState private var focused: Bool
    private let maxLen = 200

    init(initialTemplate: AffirmationTemplate? = nil) {
        // 下書きが保存されていればそれを優先
        let draft = UserDefaults.standard.string(forKey: "kotodama.draft.text") ?? ""
        if !draft.isEmpty {
            _text = State(initialValue: draft)
            _selectedTemplate = State(initialValue: nil)
            _category = State(initialValue: .custom)
            _initialText = State(initialValue: draft)
        } else if let tpl = initialTemplate {
            _text = State(initialValue: tpl.placeholderText)
            _selectedTemplate = State(initialValue: tpl)
            _category = State(initialValue: tpl.category)
            _initialText = State(initialValue: tpl.placeholderText)
        } else {
            _text = State(initialValue: "")
            _selectedTemplate = State(initialValue: nil)
            _category = State(initialValue: .custom)
            _initialText = State(initialValue: "")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    // AI ウィザード入口 (ユーザー要望: 願い事登録のところに追加)
                    Button {
                        showAIWizard = true
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "sparkles").font(.system(size: 20))
                            Text("AIに考えてもらう")
                                .appFont(.bodyEmphasis)
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .foregroundStyle(Color.brandPrimary)
                        .padding(AppSpacing.md)
                        .background(Color.brandAccent.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
                    }

                    textInputArea

                    if let hint, !hintDismissedThisSession {
                        hintCard(hint)
                    }

                    DisclosureGroup(isExpanded: $templateExpanded) {
                        templateList
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                            Text("add.template.toggle")
                                .appFont(.bodyEmphasis)
                            Spacer()
                        }
                        .foregroundStyle(Color.textPrimary)
                        .padding(.vertical, AppSpacing.xs)
                    }

                    categorySection

                    routineSection

                    writingTipsSection

                    // 自分の声を録音 (ユーザー要望: 一覧編集や新規時に録音可能)
                    RecordingControl(fileName: $recordingFileName, affirmationId: pendingId)

                    PrimaryButton(titleKey: "common.register", action: save, isEnabled: canSave)

                    HStack {
                        Spacer()
                        Text("\(text.count) / \(maxLen)")
                            .appFont(.micro)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .padding(.horizontal, AppSpacing.screenEdge)
                .padding(.vertical, AppSpacing.md)
                .responsivePage()
            }
            .background(Color.bgPrimary.ignoresSafeArea())
            .navigationTitle(Text("add.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        // 内容が変更されていれば保存確認、そうでなければ破棄
                        if text != initialText && !text.trimmingCharacters(in: .whitespaces).isEmpty {
                            showCancelConfirm = true
                        } else {
                            dismiss()
                        }
                    } label: { Text("common.cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        Text("common.register")
                            .foregroundStyle(canSave ? Color.brandPrimary : Color.textDisabled)
                    }
                    .disabled(!canSave)
                }
            }
            .onChange(of: text) { _, _ in
                hint = SmartHintEngine.evaluate(text)
            }
            .onAppear { focused = true }
            .sheet(isPresented: $showAIWizard, onDismiss: {
                // AI ウィザードで選択した文を draft から読み戻す (B4)
                let updated = UserDefaults.standard.string(forKey: "kotodama.draft.text") ?? ""
                if !updated.isEmpty && updated != text {
                    text = String(updated.prefix(maxLen))
                    initialText = text
                    // 採用後は draft 自体は残しておく (キャンセルで再復元できるように)
                }
            }) { AIWishWizardView() }
            .confirmationDialog("変更があります", isPresented: $showCancelConfirm, titleVisibility: .visible) {
                Button("下書きを保存して閉じる") {
                    draftText = text
                    dismiss()
                }
                Button("保存せず閉じる", role: .destructive) {
                    draftText = ""
                    dismiss()
                }
                Button("入力を続ける", role: .cancel) {}
            } message: {
                Text("入力中の内容を下書きとして保存しますか?")
            }
        }
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var textInputArea: some View {
        TextEditor(text: $text)
            .focused($focused)
            .appFont(.body)
            .scrollContentBackground(.hidden)
            .padding(AppSpacing.sm)
            .frame(minHeight: 160)
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.buttonSecondary))
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
    }

    @ViewBuilder
    private func hintCard(_ hint: SmartHint) -> some View {
        DismissableCard(content: {
            HStack(alignment: .top, spacing: AppSpacing.xs) {
                Text(hint.isPositive ? "💡" : "💡")
                Text(LocalizedStringKey(hint.messageKey))
                    .appFont(.caption)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }, onDismiss: { hintDismissedThisSession = true })
    }

    private var templateList: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            ForEach(AffirmationTemplate.all) { tpl in
                Button {
                    apply(tpl)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(LocalizedStringKey(tpl.nameKey))
                                    .appFont(.bodyEmphasis)
                                    .foregroundStyle(Color.textPrimary)
                                if tpl.isStarred { Text("⭐").font(.system(size: 12)) }
                            }
                            Text(LocalizedStringKey(tpl.exampleKey))
                                .appFont(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(AppSpacing.sm)
                    .background(Color.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.buttonSecondary))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("add.category")
                .appFont(.caption)
                .foregroundStyle(Color.textSecondary)

            Picker("category", selection: $category) {
                ForEach(AffirmationCategoryKind.allCases) { cat in
                    Text(LocalizedStringKey(cat.localizedKey)).tag(cat)
                }
            }
            .pickerStyle(.menu)
            .tint(Color.brandSecondary)

            if category == .custom {
                TextField("カテゴリ名を入力", text: $customCategoryName)
                    .textInputAutocapitalization(.never)
                    .appFont(.body)
                    .padding(AppSpacing.sm)
                    .background(Color.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.buttonSecondary))
            }
        }
    }

    private var routineSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("読み上げ設定")
                .appFont(.caption)
                .foregroundStyle(Color.textSecondary)
            Toggle(isOn: $includeInRoutine) {
                Text("ホームの読み上げセットに入れる").appFont(.body)
            }
            .tint(Color.brandSecondary)

            Toggle("開始日を設定する", isOn: $hasStartDate)
                .appFont(.body)
            if hasStartDate {
                DatePicker("開始日", selection: $startDate, displayedComponents: .date)
            }

            Toggle("終了日を設定する", isOn: $hasEndDate)
                .appFont(.body)
            if hasEndDate {
                DatePicker("終了日", selection: $endDate, displayedComponents: .date)
            }

            Text("読み上げる曜日")
                .appFont(.caption)
                .foregroundStyle(Color.textSecondary)
                .padding(.top, AppSpacing.xs)
            weekdayPicker
        }
        .padding(AppSpacing.md)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
    }

    private var weekdayPicker: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                let bit = 1 << i
                let on = (weekdayMask & bit) != 0
                Button {
                    if on {
                        weekdayMask &= ~bit
                    } else {
                        weekdayMask |= bit
                    }
                } label: {
                    Text(addWeekdayLabels[i])
                        .appFont(.caption)
                        .frame(width: 36, height: 36)
                        .background(on ? Color.brandPrimary : Color.bgPrimary)
                        .foregroundStyle(on ? Color.bgPrimary : Color.textSecondary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var writingTipsSection: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("書き方のコツ")
                    .appFont(.bodyEmphasis)
                    .foregroundStyle(Color.textPrimary)
                Text("「したい」で終わる願い、または「もし〜したら〜する」の形にすると、毎日の行動に移しやすくなります。")
                    .appFont(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private func apply(_ tpl: AffirmationTemplate) {
        selectedTemplate = tpl
        category = tpl.category
        if !tpl.placeholderText.isEmpty &&
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = tpl.placeholderText
        }
        templateExpanded = false
        focused = true
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let mode = selectedTemplate?.internalMode ?? "affirmation"
        let customName = customCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let aff = store.add(
            text: trimmed,
            internalMode: mode,
            templateUsed: selectedTemplate?.id,
            category: category,
            customCategoryName: category == .custom && !customName.isEmpty ? customName : nil,
            morningEnabled: true,
            eveningEnabled: false,
            includeInRoutine: includeInRoutine,
            startDate: hasStartDate ? startDate : nil,
            endDate: hasEndDate ? endDate : nil,
            weekdayMask: weekdayMask
        )
        // 録音ファイルを Affirmation の id にリネーム (pendingId で先行録音した場合)
        if let recName = recordingFileName, !recName.isEmpty {
            let target = RecordingService.newFileName(for: aff.id)
            let src = RecordingService.url(for: recName)
            let dst = RecordingService.url(for: target)
            if FileManager.default.fileExists(atPath: src.path), src != dst {
                try? FileManager.default.removeItem(at: dst)
                try? FileManager.default.moveItem(at: src, to: dst)
            }
            store.update(aff, recordingFileName: target)
        }
        // 保存完了 → 下書きクリア
        draftText = ""
        dismiss()
    }
}
