//
//  RoutineEditorView.swift
//  ホーム読み上げセット (ルーティン) 編集
//  ユーザー要望:
//   - 「含めない」表現が分かりづらい → 「セットに入れる」「セットから外す」を明確化
//   - 長押しで削除メニュー
//   - 文字大きく
//   - 検索機能
//   - ボタンを大きく
//

import SwiftUI
import SwiftData

struct RoutineEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AffirmationStore.self) private var store
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<Affirmation> { $0.isActive },
           sort: [SortDescriptor(\.orderIndex)])
    private var allActive: [Affirmation]

    @State private var working: [Affirmation] = []
    @State private var searchText: String = ""
    @State private var pendingDelete: Affirmation?
    @State private var showAdd = false

    private var inSetItems: [Affirmation] {
        let q = searchText.lowercased()
        return working.filter {
            q.isEmpty || $0.text.lowercased().contains(q)
        }
    }
    private var notInSetItems: [Affirmation] {
        let q = searchText.lowercased()
        return allActive.filter { !$0.includeInRoutine }
            .filter { q.isEmpty || $0.text.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("読み上げの順番に並べたり、含めるかどうかを切り替えられます。")
                        .appFont(.caption)
                        .foregroundStyle(Color.textSecondary)
                } header: {
                    Text("使い方")
                }

                Section {
                    if inSetItems.isEmpty {
                        Text("まだ含めている言葉がありません。下のリストから選んで「セットに入れる」をタップしてください。")
                            .appFont(.body)
                            .foregroundStyle(Color.textSecondary)
                            .padding(.vertical, AppSpacing.sm)
                    } else {
                        ForEach(inSetItems) { aff in
                            row(aff: aff, included: true)
                        }
                        .onMove(perform: move)
                    }
                } header: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.brandPrimary)
                        Text("読み上げセットに入っている言葉")
                            .appFont(.bodyEmphasis)
                        Spacer()
                        Text("\(inSetItems.count) 件")
                            .appFont(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                Section {
                    if notInSetItems.isEmpty {
                        Text("すべての言葉がセットに入っています。")
                            .appFont(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .padding(.vertical, AppSpacing.sm)
                    } else {
                        ForEach(notInSetItems) { aff in
                            row(aff: aff, included: false)
                        }
                    }
                } header: {
                    HStack {
                        Image(systemName: "circle.dashed")
                            .foregroundStyle(Color.textSecondary)
                        Text("セットに入っていない言葉")
                            .appFont(.bodyEmphasis)
                        Spacer()
                        Text("\(notInSetItems.count) 件")
                            .appFont(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                Section {
                    Button {
                        showAdd = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.brandPrimary)
                            Text("新しい言葉を追加")
                                .appFont(.bodyEmphasis)
                                .foregroundStyle(Color.brandPrimary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "言葉を検索")
            .navigationTitle(Text("読み上げセットを編集"))
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, .constant(.active))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showAdd) {
                AddAffirmationView()
            }
            .alert("この言葉を削除しますか?", isPresented: .constant(pendingDelete != nil), presenting: pendingDelete) { aff in
                Button("キャンセル", role: .cancel) { pendingDelete = nil }
                Button("削除する", role: .destructive) {
                    store.softDelete(aff)
                    pendingDelete = nil
                    rebuildWorking()
                }
            } message: { aff in
                Text("「\(aff.text.prefix(40))」")
            }
            .onAppear { rebuildWorking() }
            .onChange(of: allActive.map(\.id)) { _, _ in rebuildWorking() }
        }
    }

    @ViewBuilder
    private func row(aff: Affirmation, included: Bool) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Button {
                toggle(aff)
            } label: {
                Image(systemName: included ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26))
                    .foregroundStyle(included ? Color.brandPrimary : Color.textSecondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(aff.text)
                    .appFont(.body)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                HStack(spacing: AppSpacing.xs) {
                    if let cat = AffirmationCategoryKind(rawValue: aff.category) {
                        Text(LocalizedStringKey(cat.localizedKey))
                            .appFont(.micro)
                            .foregroundStyle(Color.brandSecondary)
                    }
                    if let fn = aff.recordingFileName, RecordingService.shared.hasRecording(fileName: fn) {
                        Label("録音あり", systemImage: "waveform")
                            .appFont(.micro)
                            .foregroundStyle(Color.brandSecondary)
                    }
                }
            }
            Spacer()
            Button {
                toggle(aff)
            } label: {
                Text(included ? "外す" : "入れる")
                    .appFont(.caption)
                    .foregroundStyle(included ? Color.semanticError : Color.brandPrimary)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, 6)
                    .background(included ? Color.semanticError.opacity(0.1) : Color.brandPrimary.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .contextMenu {
            Button(role: .destructive) {
                pendingDelete = aff
            } label: {
                Label("この言葉を削除", systemImage: "trash")
            }
            Button {
                toggle(aff)
            } label: {
                Label(included ? "セットから外す" : "セットに入れる",
                      systemImage: included ? "minus.circle" : "plus.circle")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                pendingDelete = aff
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
    }

    private func rebuildWorking() {
        working = allActive
            .filter { $0.includeInRoutine }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    private func toggle(_ aff: Affirmation) {
        aff.includeInRoutine.toggle()
        try? ctx.save()
        rebuildWorking()
    }

    private func move(from src: IndexSet, to dst: Int) {
        working.move(fromOffsets: src, toOffset: dst)
    }

    private func save() {
        store.updateRoutineOrder(working)
    }
}
