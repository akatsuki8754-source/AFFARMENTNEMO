//
//  RoutineEditorView.swift
//  ホームの読み上げセット (ルーティン) を編集: 順序入れ替え + 含める/除外
//  ユーザー要望: 「自分の言葉から順番や追加削除を編集できるように」
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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("タップで含める/外す。長押しでドラッグして順序を入れ替え。")
                        .appFont(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Section(header: Text("読み上げセット (順番にこの順で読み上げ)")) {
                    if working.isEmpty {
                        Text("まだ含まれている言葉がありません。下から追加してください。")
                            .appFont(.caption)
                            .foregroundStyle(Color.textSecondary)
                    } else {
                        ForEach(working) { aff in
                            row(aff: aff, included: true)
                        }
                        .onMove(perform: move)
                    }
                }
                Section(header: Text("含めない")) {
                    ForEach(allActive.filter { !$0.includeInRoutine }) { aff in
                        row(aff: aff, included: false)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(Text("読み上げセットを編集"))
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, .constant(.active))  // 常時 onMove 可能
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
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
                    .font(.system(size: 22))
                    .foregroundStyle(included ? Color.brandPrimary : Color.textSecondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(aff.text)
                    .appFont(.body)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                if let fn = aff.recordingFileName, RecordingService.shared.hasRecording(fileName: fn) {
                    Label("録音あり", systemImage: "waveform")
                        .appFont(.micro)
                        .foregroundStyle(Color.brandSecondary)
                }
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
        // 順序のみ反映 (ON/OFF はトグルで保存済み)
        store.updateRoutineOrder(working)
    }
}
