//
//  AIWishWizardView.swift
//  AI 短冊作成ウィザード — 知識マップ (3択 → 候補3個 → 複数選択 → 入力欄に追記)
//  仕様: 00_コトダマ_AI短冊機能 §6 ユーザー体験フロー (v2)
//
//  v2 改修内容 (今セッションで対応):
//   B1 「選び直す」で空ビューになるバグ → resetWizard() で path/rotation も完全初期化
//   B2 戻るボタンが selectingPath だけ → step 別に出すように
//   B3 候補1個ずつしか採用できない → 複数選択して一括追加
//   B4 編集画面が冗長 → 廃止、選択した文を kotodama.draft.text に改行追記して dismiss
//   B5 「その他」連打後、戻る時に rotation が残る → path.removeLast 時にリセット
//   B6 候補が毎回同じ → 「候補をもう一度生成」ボタンを candidates 画面に追加 (将来 Gemini 切替で動的に)
//   B7 generating Task が cancel されない → @State で保持してキャンセル
//   B8 AI生成にリワード広告ゲート → Phase3 の Gemini 本接続時のみ起動 (#if 静的サンプル時はスキップ)
//

import SwiftUI

struct AIWishWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AffirmationStore.self) private var store

    @State private var path: [WishMapNode] = []
    @State private var candidates: [String] = []
    @State private var selectedTexts: Set<String> = []
    @State private var step: WizardStep = .selectingPath
    @State private var generationTask: Task<Void, Never>?
    /// 各階層で「その他」を押した回数 (3択ローテーションのため)
    @State private var rotationOffsetByLevel: [Int: Int] = [:]
    /// 候補再生成カウント (静的サンプルでも順序を変えるため)
    @State private var regenerateNonce: Int = 0

    enum WizardStep {
        case selectingPath  // 知識マップ進行中
        case generating     // AI生成中演出
        case showCandidates // 3候補提示 + 複数選択
    }

    /// 現在の階層の全子ノード (rotation 適用前)
    private var allChildrenAtCurrentLevel: [WishMapNode] {
        if path.isEmpty {
            return KnowledgeMap.root.children
        }
        return path.last?.children ?? []
    }

    /// 現在表示すべき 3 件 (rotation offset を適用)
    private var currentChildren: [WishMapNode] {
        let all = allChildrenAtCurrentLevel
        guard all.count > 3 else { return all }
        let offset = rotationOffsetByLevel[path.count] ?? 0
        let start = (offset * 3) % all.count
        var result: [WishMapNode] = []
        for i in 0..<3 {
            result.append(all[(start + i) % all.count])
        }
        return result
    }

    /// 「その他」ボタンを表示するか (4件以上選択肢があり、ルートでない時)
    private var hasMoreOptions: Bool {
        guard !path.isEmpty else { return false }
        return allChildrenAtCurrentLevel.count > 3
    }

    /// 現ステップで戻るボタンを表示するか
    private var canGoBack: Bool {
        switch step {
        case .selectingPath: return !path.isEmpty
        case .generating: return true
        case .showCandidates: return true
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .selectingPath: pathSelector
                case .generating: generatingView
                case .showCandidates: candidatesView
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        generationTask?.cancel()
                        dismiss()
                    }
                }
                if canGoBack {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            goBack()
                        } label: {
                            Label("戻る", systemImage: "chevron.left")
                        }
                    }
                }
            }
        }
    }

    private var navigationTitle: String {
        switch step {
        case .selectingPath: return "AIで言葉を作る"
        case .generating: return "言葉を考えています…"
        case .showCandidates: return "候補から選ぶ (複数可)"
        }
    }

    // MARK: - Step 1: パス選択
    private var pathSelector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                // 現在のパスをパンくず表示
                if !path.isEmpty {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundStyle(Color.brandSecondary)
                        Text(path.map(\.title).joined(separator: " > "))
                            .appFont(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .background(Color.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.buttonSecondary))
                    .padding(.horizontal, AppSpacing.screenEdge)
                }

                // 質問文
                Text(path.isEmpty ? KnowledgeMap.root.title : (path.last?.title ?? ""))
                    .appFont(.h2)
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, AppSpacing.screenEdge)

                Text("3つから選んでみてね")
                    .appFont(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, AppSpacing.screenEdge)

                // 3択ボタン
                VStack(spacing: AppSpacing.md) {
                    ForEach(currentChildren) { child in
                        Button {
                            select(child)
                        } label: {
                            HStack {
                                Text(child.title)
                                    .appFont(.bodyEmphasis)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: child.children.isEmpty ? "sparkles" : "chevron.right")
                                    .foregroundStyle(Color.brandPrimary)
                            }
                            .foregroundStyle(Color.textPrimary)
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, AppSpacing.md)
                            .background(Color.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
                        }
                    }

                    // 「その他」で同階層の別3件にローテ
                    if hasMoreOptions {
                        Button {
                            rotateOptions()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundStyle(Color.brandSecondary)
                                Text("その他の選択肢を見る")
                                    .appFont(.body)
                                    .foregroundStyle(Color.brandSecondary)
                                Spacer()
                            }
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, AppSpacing.sm)
                            .background(Color.bgPrimary)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.card)
                                    .stroke(Color.brandSecondary.opacity(0.4), lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.screenEdge)

                if !currentChildren.isEmpty {
                    Text("最後まで進むと、AIが3つの言葉を提案します")
                        .appFont(.micro)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, AppSpacing.screenEdge)
                        .padding(.top, AppSpacing.sm)
                }

                Spacer().frame(height: AppSpacing.xl)
            }
            .padding(.top, AppSpacing.md)
        }
    }

    // MARK: - Step 2: 生成中
    private var generatingView: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()
            ProgressView()
                .scaleEffect(1.6)
            Text("あなたに合う言葉を考えています…")
                .appFont(.body)
                .foregroundStyle(Color.textPrimary)
            Text("研究で証明された手法 (Implementation Intentions / Self-Affirmation) に基づいて生成中")
                .appFont(.caption)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.lg)
            Spacer()
        }
    }

    // MARK: - Step 3: 候補提示 (複数選択)
    private var candidatesView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text("ピンとくるものをタップ (複数選択可)")
                        .appFont(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, AppSpacing.screenEdge)

                    ForEach(Array(candidates.enumerated()), id: \.offset) { idx, text in
                        let isSelected = selectedTexts.contains(text)
                        Button {
                            toggleSelection(text)
                        } label: {
                            HStack(alignment: .top, spacing: AppSpacing.sm) {
                                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 22))
                                    .foregroundStyle(isSelected ? Color.brandPrimary : Color.textSecondary)
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                    Text("候補 \(idx + 1)")
                                        .appFont(.micro)
                                        .foregroundStyle(Color.brandSecondary)
                                    Text(text)
                                        .appFont(.body)
                                        .foregroundStyle(Color.textPrimary)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(AppSpacing.md)
                            .background(
                                isSelected
                                    ? Color.brandAccent.opacity(0.18)
                                    : Color.bgSecondary
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.card)
                                    .stroke(
                                        isSelected ? Color.brandPrimary : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
                        }
                        .padding(.horizontal, AppSpacing.screenEdge)
                    }

                    // 候補をもう一度生成 (静的でも順序を変える)
                    Button {
                        regenerate()
                    } label: {
                        Label("候補をもう一度生成", systemImage: "arrow.clockwise")
                            .appFont(.body)
                            .foregroundStyle(Color.brandSecondary)
                            .frame(maxWidth: .infinity, minHeight: AppTouchTarget.buttonHeight)
                            .background(Color.bgPrimary)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.buttonSecondary)
                                    .stroke(Color.brandSecondary.opacity(0.5), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, AppSpacing.screenEdge)
                    .padding(.top, AppSpacing.sm)

                    // 選び直す (最初から)
                    Button {
                        resetWizard()
                    } label: {
                        Label("最初から選び直す", systemImage: "arrow.uturn.backward")
                            .appFont(.body)
                            .foregroundStyle(Color.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: AppTouchTarget.buttonHeight)
                            .background(Color.bgPrimary)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.buttonSecondary)
                                    .stroke(Color.borderDefault, lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, AppSpacing.screenEdge)

                    Spacer().frame(height: AppSpacing.xl)
                }
                .padding(.top, AppSpacing.md)
            }

            // 下部固定の「採用」ボタン
            VStack(spacing: 0) {
                Divider()
                Button {
                    applyToDraft()
                } label: {
                    HStack {
                        Image(systemName: "text.badge.plus")
                        Text(selectedTexts.isEmpty
                             ? "候補を選んでください"
                             : "選択した \(selectedTexts.count) 個を入力欄に追加")
                            .appFont(.h3)
                    }
                    .foregroundStyle(Color.bgPrimary)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(selectedTexts.isEmpty
                                ? Color.textDisabled
                                : Color.brandPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.button))
                }
                .disabled(selectedTexts.isEmpty)
                .padding(.horizontal, AppSpacing.screenEdge)
                .padding(.vertical, AppSpacing.md)
                .background(Color.bgPrimary)
            }
        }
    }

    // MARK: - Actions

    private func goBack() {
        switch step {
        case .selectingPath:
            guard !path.isEmpty else { return }
            // 戻る時に「次の階層の rotation」を捨てる (B5 対策)
            rotationOffsetByLevel.removeValue(forKey: path.count)
            path.removeLast()
        case .generating:
            generationTask?.cancel()
            step = .selectingPath
        case .showCandidates:
            // 候補画面 → パス選択画面 (最後の leaf を未選択状態に戻す)
            candidates = []
            selectedTexts = []
            if !path.isEmpty {
                rotationOffsetByLevel.removeValue(forKey: path.count)
                path.removeLast()
            }
            step = .selectingPath
        }
    }

    private func select(_ node: WishMapNode) {
        path.append(node)
        if node.children.isEmpty {
            generate()
        }
    }

    private func rotateOptions() {
        let level = path.count
        let current = rotationOffsetByLevel[level] ?? 0
        rotationOffsetByLevel[level] = current + 1
    }

    private func toggleSelection(_ text: String) {
        if selectedTexts.contains(text) {
            selectedTexts.remove(text)
        } else {
            selectedTexts.insert(text)
        }
    }

    /// B1 修正: 完全初期化
    private func resetWizard() {
        generationTask?.cancel()
        candidates = []
        selectedTexts = []
        path = []
        rotationOffsetByLevel = [:]
        regenerateNonce = 0
        step = .selectingPath
    }

    private func regenerate() {
        regenerateNonce += 1
        selectedTexts = []
        // 静的サンプルでも順序を変える
        let base = KnowledgeMap.generateCandidates(for: path)
        if base.count > 1 {
            let rotateBy = regenerateNonce % base.count
            candidates = Array(base[rotateBy...] + base[..<rotateBy])
        } else {
            candidates = base
        }
    }

    private func generate() {
        // B8: Phase 3 で Gemini 本接続が有効な時のみリワード広告
        // (現状は静的サンプルなので無料で出す)
        #if PHASE3_GEMINI_LIVE
        AdRewardGate.shared.presentBeforeAIGeneration { granted in
            if granted { performGenerate() }
            else { step = .selectingPath }
        }
        #else
        performGenerate()
        #endif
    }

    private func performGenerate() {
        step = .generating
        generationTask?.cancel()
        // B7: Task を保持してキャンセル可能に
        generationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if Task.isCancelled { return }
            candidates = KnowledgeMap.generateCandidates(for: path)
            selectedTexts = []
            step = .showCandidates
        }
    }

    /// B4: 編集画面廃止。選択した文を draft に追記して dismiss
    /// AddAffirmationView 側が onDismiss で draft を読み戻す
    private func applyToDraft() {
        guard !selectedTexts.isEmpty else { return }
        let appended = candidates
            .filter { selectedTexts.contains($0) }
            .joined(separator: "\n")
        let key = "kotodama.draft.text"
        let existing = UserDefaults.standard.string(forKey: key) ?? ""
        let merged: String
        if existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged = appended
        } else {
            merged = existing + "\n" + appended
        }
        // 長すぎ防止 (TextEditor は 200 字制限だが、複数追加時は緩めに 1000 で切る)
        UserDefaults.standard.set(String(merged.prefix(1000)), forKey: key)
        dismiss()
    }
}
