//
//  AddAffirmationView.swift
//  アファメ追加: テキストエリア + テンプレ展開 + スマートヒント
//  仕様: UX v4 §3-4
//

import SwiftUI

struct AddAffirmationView: View {
    @Environment(AffirmationStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @State private var selectedTemplate: AffirmationTemplate?
    @State private var category: AffirmationCategoryKind
    @State private var morningEnabled: Bool = true
    @State private var eveningEnabled: Bool = false
    @State private var templateExpanded: Bool = false
    @State private var hint: SmartHint?
    @State private var hintDismissedThisSession: Bool = false

    @FocusState private var focused: Bool
    private let maxLen = 200

    init(initialTemplate: AffirmationTemplate? = nil) {
        if let tpl = initialTemplate {
            _text = State(initialValue: tpl.placeholderText)
            _selectedTemplate = State(initialValue: tpl)
            _category = State(initialValue: tpl.category)
        } else {
            _text = State(initialValue: "")
            _selectedTemplate = State(initialValue: nil)
            _category = State(initialValue: .custom)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
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

                    scheduleSection

                    HStack {
                        Spacer()
                        Text("\(text.count) / \(maxLen)")
                            .appFont(.micro)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .padding(.horizontal, AppSpacing.screenEdge)
                .padding(.vertical, AppSpacing.md)
            }
            .background(Color.bgPrimary.ignoresSafeArea())
            .navigationTitle(Text("add.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Text("common.cancel") }
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
            .frame(minHeight: 120)
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
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("add.schedule")
                .appFont(.caption)
                .foregroundStyle(Color.textSecondary)
            HStack(spacing: AppSpacing.md) {
                Toggle(isOn: $morningEnabled) {
                    Text("notif.slot.morning").appFont(.body)
                }
                .tint(Color.brandSecondary)
                Toggle(isOn: $eveningEnabled) {
                    Text("notif.slot.evening").appFont(.body)
                }
                .tint(Color.brandSecondary)
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
        store.add(
            text: trimmed,
            internalMode: mode,
            templateUsed: selectedTemplate?.id,
            category: category,
            morningEnabled: morningEnabled,
            eveningEnabled: eveningEnabled
        )
        dismiss()
    }
}
