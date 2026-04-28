//
//  LibraryView.swift
//  アファメ一覧 + 編集 + 削除 (5秒Undo)
//

import SwiftUI

struct LibraryView: View {
    @Environment(AffirmationStore.self) private var store
    @State private var editingAffirmation: Affirmation?
    @State private var pendingUndo: Affirmation?
    @State private var undoTask: Task<Void, Never>?
    @State private var showAdd = false

    var body: some View {
        let items = store.allAffirmations(activeOnly: true)

        NavigationStack {
            VStack(spacing: 0) {
                if items.isEmpty {
                    emptyState
                        .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(items) { aff in
                            AffirmationRow(affirmation: aff)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        softDelete(aff)
                                    } label: {
                                        Label("common.delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        editingAffirmation = aff
                                    } label: {
                                        Label("common.edit", systemImage: "pencil")
                                    }
                                    .tint(Color.brandSecondary)
                                }
                        }
                    }
                    .listStyle(.plain)
                }

                if let undoItem = pendingUndo {
                    undoBar(undoItem)
                }

                AdBannerSlot()
            }
            .background(Color.bgPrimary)
            .navigationTitle(Text("library.title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("home.add"))
                }
            }
            .sheet(item: $editingAffirmation) { aff in
                EditAffirmationView(affirmation: aff)
            }
            .sheet(isPresented: $showAdd) {
                AddAffirmationView()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "text.quote")
                .font(.system(size: 48))
                .foregroundStyle(Color.textDisabled)
            Text("library.empty.title")
                .appFont(.h3)
                .foregroundStyle(Color.textPrimary)
            Text("library.empty.body")
                .appFont(.caption)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                showAdd = true
            } label: {
                Text("home.add")
                    .appFont(.bodyEmphasis)
                    .foregroundStyle(Color.bgPrimary)
                    .padding(.horizontal, AppSpacing.lg)
                    .frame(minHeight: AppTouchTarget.buttonHeight)
                    .background(Color.brandPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.button))
            }
            .padding(.top, AppSpacing.md)
        }
        .padding(AppSpacing.lg)
    }

    private func softDelete(_ aff: Affirmation) {
        store.softDelete(aff)
        pendingUndo = aff
        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled {
                // 5秒経過: 物理削除
                if let item = pendingUndo {
                    store.delete(item)
                    pendingUndo = nil
                }
            }
        }
    }

    private func undoBar(_ aff: Affirmation) -> some View {
        HStack {
            Text("undo.deleted")
                .appFont(.caption)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Button {
                store.restore(aff)
                pendingUndo = nil
                undoTask?.cancel()
            } label: {
                Text("undo.restore")
                    .appFont(.bodyEmphasis)
                    .foregroundStyle(Color.brandSecondary)
            }
        }
        .padding(.horizontal, AppSpacing.screenEdge)
        .padding(.vertical, AppSpacing.md)
        .background(Color.bgSecondary)
    }
}

private struct AffirmationRow: View {
    let affirmation: Affirmation

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(affirmation.text)
                .appFont(.body)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(3)

            HStack(spacing: AppSpacing.sm) {
                if affirmation.morningEnabled {
                    badge(systemImage: "sun.max.fill", textKey: "notif.slot.morning")
                }
                if affirmation.eveningEnabled {
                    badge(systemImage: "moon.fill", textKey: "notif.slot.evening")
                }
                Text("read.\(affirmation.readCount)")
                    .appFont(.micro)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.vertical, AppSpacing.xs)
        .listRowBackground(Color.bgPrimary)
    }

    private func badge(systemImage: String, textKey: LocalizedStringKey) -> some View {
        HStack(spacing: 2) {
            Image(systemName: systemImage)
            Text(textKey)
        }
        .appFont(.micro)
        .foregroundStyle(Color.textSecondary)
        .padding(.horizontal, AppSpacing.xs + 2)
        .padding(.vertical, 2)
        .background(Color.bgSecondary)
        .clipShape(Capsule())
    }
}

// MARK: - Edit

struct EditAffirmationView: View {
    @Environment(AffirmationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let affirmation: Affirmation

    @State private var text: String
    @State private var category: AffirmationCategoryKind
    @State private var morningEnabled: Bool
    @State private var eveningEnabled: Bool

    init(affirmation: Affirmation) {
        self.affirmation = affirmation
        _text = State(initialValue: affirmation.text)
        _category = State(initialValue: AffirmationCategoryKind(rawValue: affirmation.category) ?? .custom)
        _morningEnabled = State(initialValue: affirmation.morningEnabled)
        _eveningEnabled = State(initialValue: affirmation.eveningEnabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                }
                Section(header: Text("add.category")) {
                    Picker("", selection: $category) {
                        ForEach(AffirmationCategoryKind.allCases) { cat in
                            Text(LocalizedStringKey(cat.localizedKey)).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section(header: Text("add.schedule")) {
                    Toggle(isOn: $morningEnabled) { Text("notif.slot.morning") }
                    Toggle(isOn: $eveningEnabled) { Text("notif.slot.evening") }
                }
            }
            .navigationTitle(Text("edit.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("common.cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        store.update(affirmation,
                                     text: trimmed,
                                     category: category,
                                     morningEnabled: morningEnabled,
                                     eveningEnabled: eveningEnabled)
                        dismiss()
                    } label: { Text("common.save") }
                }
            }
        }
    }
}
