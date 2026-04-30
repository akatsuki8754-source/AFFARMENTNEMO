//
//  LibraryView.swift
//  アファメ一覧 + 編集 + 削除 (5秒Undo)
//

import SwiftUI
import SwiftData

enum LibrarySortMode: String, CaseIterable, Identifiable {
    case orderIndex = "order"
    case createdAtDesc = "created_desc"
    case createdAtAsc = "created_asc"
    case lastReadDesc = "lastread_desc"
    case readCountDesc = "readcount_desc"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .orderIndex: return "並び順 (デフォルト)"
        case .createdAtDesc: return "作成日 (新しい順)"
        case .createdAtAsc: return "作成日 (古い順)"
        case .lastReadDesc: return "最後に読んだ順"
        case .readCountDesc: return "読み上げ回数順"
        }
    }
}

struct LibraryView: View {
    @Environment(AffirmationStore.self) private var store
    /// SwiftData @Query で SwiftData の変更を即時購読 (バグ修正: 追加が一覧に反映されない)
    /// activeOnly=true 相当: isActive==true なものだけ orderIndex 順
    @Query(filter: #Predicate<Affirmation> { $0.isActive }, sort: [SortDescriptor(\.orderIndex)])
    private var items: [Affirmation]
    @State private var editingAffirmation: Affirmation?
    @State private var pendingUndo: Affirmation?
    @State private var undoTask: Task<Void, Never>?
    @State private var showAdd = false
    // ユーザー要望: 検索 + フィルター
    @State private var searchText: String = ""
    @State private var filterCategory: AffirmationCategoryKind?
    @State private var sortMode: LibrarySortMode = .orderIndex
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showBulkDeleteConfirm = false

    private var filteredItems: [Affirmation] {
        var result = items
        if let cat = filterCategory {
            result = result.filter { $0.category == cat.rawValue }
        }
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let q = searchText.lowercased()
            result = result.filter { $0.text.lowercased().contains(q) }
        }
        switch sortMode {
        case .orderIndex: result.sort { $0.orderIndex < $1.orderIndex }
        case .createdAtDesc: result.sort { $0.createdAt > $1.createdAt }
        case .createdAtAsc: result.sort { $0.createdAt < $1.createdAt }
        case .lastReadDesc: result.sort { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }
        case .readCountDesc: result.sort { $0.readCount > $1.readCount }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            mainContent(items: filteredItems)
                .searchable(text: $searchText, prompt: "言葉を検索")
                .responsivePage(maxWidth: 720)
        }
    }

    @ViewBuilder
    private func mainContent(items: [Affirmation]) -> some View {
        VStack(spacing: 0) {
                if items.isEmpty {
                    emptyState
                        .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(items) { aff in
                            // バグ修正: タップで詳細/編集シートを開く (旧: 何も起きなかった)
                            Button {
                                if isSelecting {
                                    toggleSelection(aff)
                                } else {
                                    editingAffirmation = aff
                                }
                            } label: {
                                HStack(spacing: AppSpacing.sm) {
                                    if isSelecting {
                                        Image(systemName: selectedIDs.contains(aff.id) ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 24))
                                            .foregroundStyle(selectedIDs.contains(aff.id) ? Color.brandPrimary : Color.textSecondary)
                                    }
                                    AffirmationRow(affirmation: aff)
                                }
                            }
                            .buttonStyle(.plain)
                            .onLongPressGesture {
                                isSelecting = true
                                selectedIDs.insert(aff.id)
                            }
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
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        // カテゴリ絞り込み
                        Section("カテゴリで絞り込む") {
                            Button {
                                filterCategory = nil
                            } label: {
                                HStack {
                                    Text("すべて")
                                    if filterCategory == nil { Image(systemName: "checkmark") }
                                }
                            }
                            ForEach(AffirmationCategoryKind.allCases) { cat in
                                Button {
                                    filterCategory = (filterCategory == cat) ? nil : cat
                                } label: {
                                    HStack {
                                        Text(LocalizedStringKey(cat.localizedKey))
                                        if filterCategory == cat { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        }
                        // 並び替え
                        Section("並び替え") {
                            ForEach(LibrarySortMode.allCases) { mode in
                                Button {
                                    sortMode = mode
                                } label: {
                                    HStack {
                                        Text(mode.label)
                                        if sortMode == mode { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: filterCategory == nil ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                            .foregroundStyle(filterCategory == nil ? Color.textPrimary : Color.brandPrimary)
                    }
                    .accessibilityLabel(Text("フィルター"))
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isSelecting {
                        Button {
                            selectAllFiltered(items)
                        } label: {
                            Image(systemName: "checkmark.square")
                        }
                        .accessibilityLabel(Text("表示中をすべて選択"))

                        Button(role: .destructive) {
                            showBulkDeleteConfirm = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(selectedIDs.isEmpty)
                        .accessibilityLabel(Text("選択した言葉を削除"))

                        Button("完了") {
                            isSelecting = false
                            selectedIDs = []
                        }
                    } else {
                        Button {
                            isSelecting = true
                        } label: {
                            Image(systemName: "checkmark.circle")
                        }
                        .accessibilityLabel(Text("複数選択"))

                        Button { showAdd = true } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(Text("home.add"))
                    }
                }
            }
            .sheet(item: $editingAffirmation) { aff in
                EditAffirmationView(affirmation: aff)
            }
            .sheet(isPresented: $showAdd) {
                AddAffirmationView()
            }
            .confirmationDialog("選択した言葉を削除しますか?",
                                isPresented: $showBulkDeleteConfirm,
                                titleVisibility: .visible) {
                Button("削除する", role: .destructive) {
                    bulkDeleteSelected()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("\(selectedIDs.count)件を削除します")
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

    private func toggleSelection(_ aff: Affirmation) {
        if selectedIDs.contains(aff.id) {
            selectedIDs.remove(aff.id)
        } else {
            selectedIDs.insert(aff.id)
        }
    }

    private func selectAllFiltered(_ visibleItems: [Affirmation]) {
        let ids = Set(visibleItems.map(\.id))
        if selectedIDs.isSuperset(of: ids), !ids.isEmpty {
            selectedIDs.subtract(ids)
        } else {
            selectedIDs.formUnion(ids)
        }
    }

    private func bulkDeleteSelected() {
        let targets = items.filter { selectedIDs.contains($0.id) }
        targets.forEach { store.delete($0) }
        selectedIDs = []
        isSelecting = false
        pendingUndo = nil
        undoTask?.cancel()
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

    private var categoryKind: AffirmationCategoryKind {
        AffirmationCategoryKind(rawValue: affirmation.category) ?? .custom
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(affirmation.text)
                .appFont(.body)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(3)

            HStack(spacing: AppSpacing.sm) {
                // バグ修正: カテゴリ表示が抜けていた → カテゴリバッジ追加
                categoryBadge(categoryKind)
                Spacer()
                Text("read.\(affirmation.readCount)")
                    .appFont(.micro)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.vertical, AppSpacing.xs)
        .listRowBackground(Color.bgPrimary)
    }

    private func categoryBadge(_ kind: AffirmationCategoryKind) -> some View {
        // custom かつ カスタム名がある場合はそれを表示
        let label: String = {
            if kind == .custom, let name = affirmation.customCategoryName, !name.isEmpty {
                return name
            }
            return NSLocalizedString(kind.localizedKey, comment: "")
        }()
        return Text(label)
            .appFont(.micro)
            .foregroundStyle(Color.brandPrimary)
            .padding(.horizontal, AppSpacing.xs + 2)
            .padding(.vertical, 2)
            .background(Color.brandAccent.opacity(0.2))
            .clipShape(Capsule())
    }

}

// MARK: - Edit

private let weekdayLabels = ["日", "月", "火", "水", "木", "金", "土"]

struct EditAffirmationView: View {
    @Environment(AffirmationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let affirmation: Affirmation

    @State private var text: String
    @State private var category: AffirmationCategoryKind
    @State private var customCategoryName: String
    @State private var morningEnabled: Bool
    @State private var eveningEnabled: Bool
    @State private var includeInRoutine: Bool
    @State private var recordingFileName: String?
    // 期限・曜日 (Phase 2)
    @State private var hasStartDate: Bool
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var weekdayMask: Int

    init(affirmation: Affirmation) {
        self.affirmation = affirmation
        _text = State(initialValue: affirmation.text)
        _category = State(initialValue: AffirmationCategoryKind(rawValue: affirmation.category) ?? .custom)
        _customCategoryName = State(initialValue: affirmation.customCategoryName ?? "")
        _morningEnabled = State(initialValue: affirmation.morningEnabled)
        _eveningEnabled = State(initialValue: affirmation.eveningEnabled)
        _includeInRoutine = State(initialValue: affirmation.includeInRoutine)
        _recordingFileName = State(initialValue: affirmation.recordingFileName)
        _hasStartDate = State(initialValue: affirmation.startDate != nil)
        _startDate = State(initialValue: affirmation.startDate ?? Date())
        _hasEndDate = State(initialValue: affirmation.endDate != nil)
        _endDate = State(initialValue: affirmation.endDate ?? Date().addingTimeInterval(7 * 24 * 3600))
        _weekdayMask = State(initialValue: affirmation.weekdayMask)
    }

    @ViewBuilder
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
                    Text(weekdayLabels[i])
                        .appFont(.caption)
                        .frame(width: 36, height: 36)
                        .background(on ? Color.brandPrimary : Color.bgSecondary)
                        .foregroundStyle(on ? Color.bgPrimary : Color.textSecondary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .appFont(.body)
                        .scrollContentBackground(.hidden)
                        .padding(AppSpacing.sm)
                        .frame(minHeight: 160)
                        .background(Color.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.buttonSecondary))
                }
                Section(header: Text("add.category")) {
                    Picker("", selection: $category) {
                        ForEach(AffirmationCategoryKind.allCases) { cat in
                            Text(LocalizedStringKey(cat.localizedKey)).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                    if category == .custom {
                        TextField("カテゴリ名 (例: 健康習慣)", text: $customCategoryName)
                            .textInputAutocapitalization(.never)
                    }
                }
                Section(header: Text("読み上げ設定")) {
                    Toggle(isOn: $includeInRoutine) { Text("ホームの読み上げセットに含める") }
                }
                Section(header: Text("期間 (任意)")) {
                    Toggle("開始日を設定する", isOn: $hasStartDate)
                    if hasStartDate {
                        DatePicker("開始日", selection: $startDate, displayedComponents: .date)
                    }
                    Toggle("終了日を設定する (期限切れ後はホームから自動除外)", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("終了日", selection: $endDate, displayedComponents: .date)
                    }
                }

                Section(header: Text("読み上げる曜日")) {
                    weekdayPicker
                }

                Section(header: Text("自分の声")) {
                    RecordingControl(fileName: $recordingFileName, affirmationId: affirmation.id)
                }
                Section {
                    PrimaryButton(titleKey: "common.save", action: save, isEnabled: canSave)
                }
            }
            .navigationTitle(Text("edit.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("common.cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Text("common.save") }
                        .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let customName = customCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        store.update(affirmation,
                     text: trimmed,
                     category: category,
                     morningEnabled: true,
                     eveningEnabled: false,
                     customCategoryName: .some(category == .custom && !customName.isEmpty ? customName : nil),
                     startDate: .some(hasStartDate ? startDate : nil),
                     endDate: .some(hasEndDate ? endDate : nil),
                     weekdayMask: weekdayMask,
                     recordingFileName: .some(recordingFileName),
                     includeInRoutine: includeInRoutine)
        dismiss()
    }
}
