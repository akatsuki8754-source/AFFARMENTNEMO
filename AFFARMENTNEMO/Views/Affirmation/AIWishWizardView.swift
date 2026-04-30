//
//  AIWishWizardView.swift
//  AI 短冊作成ウィザード — 知識マップ (3択 → 候補3個 → 編集 → 保存)
//  仕様: 00_コトダマ_AI短冊機能 §6 ユーザー体験フロー
//

import SwiftUI

struct AIWishWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AffirmationStore.self) private var store

    @State private var path: [WishMapNode] = []
    @State private var candidates: [String] = []
    @State private var selectedCandidate: String?
    @State private var editedText: String = ""
    @State private var step: WizardStep = .selectingPath
    @State private var generating: Bool = false

    enum WizardStep {
        case selectingPath  // 知識マップ進行中
        case generating     // AI生成中演出
        case showCandidates // 3候補提示
        case editing        // 編集
    }

    private var currentNode: WishMapNode {
        if path.isEmpty { return KnowledgeMap.root }
        let last = path.last!
        return last.children.isEmpty ? last : last
    }

    private var canPickChildren: Bool {
        !currentChildren.isEmpty
    }

    private var currentChildren: [WishMapNode] {
        if path.isEmpty {
            return KnowledgeMap.root.children
        }
        return path.last?.children ?? []
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .selectingPath: pathSelector
                case .generating: generatingView
                case .showCandidates: candidatesView
                case .editing: editorView
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                if step == .selectingPath && !path.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            path.removeLast()
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
        case .showCandidates: return "3つの候補から選ぶ"
        case .editing: return "あなたの言葉に編集"
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

    // MARK: - Step 3: 候補提示
    private var candidatesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("ピンとくるものを選んで、自分の言葉に編集してね")
                    .appFont(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, AppSpacing.screenEdge)

                ForEach(Array(candidates.enumerated()), id: \.offset) { idx, text in
                    Button {
                        selectedCandidate = text
                        editedText = text
                        step = .editing
                    } label: {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            HStack {
                                Text("候補 \(idx + 1)")
                                    .appFont(.micro)
                                    .foregroundStyle(Color.brandSecondary)
                                Spacer()
                                Image(systemName: "pencil.circle.fill")
                                    .foregroundStyle(Color.brandPrimary)
                            }
                            Text(text)
                                .appFont(.body)
                                .foregroundStyle(Color.textPrimary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(AppSpacing.md)
                        .background(Color.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
                    }
                    .padding(.horizontal, AppSpacing.screenEdge)
                }

                Button {
                    // 戻ってやり直し
                    candidates = []
                    step = .selectingPath
                } label: {
                    Label("選び直す", systemImage: "arrow.uturn.backward")
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
                .padding(.top, AppSpacing.md)

                Spacer().frame(height: AppSpacing.xl)
            }
            .padding(.top, AppSpacing.md)
        }
    }

    // MARK: - Step 4: 編集
    private var editorView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("言葉を自分のものに調整しよう")
                .appFont(.bodyEmphasis)
                .foregroundStyle(Color.textPrimary)

            TextEditor(text: $editedText)
                .appFont(.body)
                .frame(minHeight: 180)
                .padding(AppSpacing.sm)
                .background(Color.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.buttonSecondary))

            HStack {
                Spacer()
                Text("\(editedText.count) / 200")
                    .appFont(.micro)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            Button {
                save()
            } label: {
                Label("この言葉を登録", systemImage: "checkmark.circle.fill")
                    .appFont(.h3)
                    .foregroundStyle(Color.bgPrimary)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Color.brandPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.button))
            }
            .disabled(editedText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, AppSpacing.screenEdge)
        .padding(.top, AppSpacing.md)
        .padding(.bottom, AppSpacing.lg)
    }

    // MARK: - Actions
    private func select(_ node: WishMapNode) {
        path.append(node)
        if node.children.isEmpty {
            // 末端ノード → 生成へ
            generate()
        }
    }

    private func generate() {
        step = .generating
        // Phase 1.5: 静的サンプル (Phase 2 で Gemini API に置き換え)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            candidates = KnowledgeMap.generateCandidates(for: path)
            step = .showCandidates
        }
    }

    private func save() {
        let text = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let limited = String(text.prefix(200))
        // 最終ノードのカテゴリ推定
        let cat: AffirmationCategoryKind = {
            let p = path.first?.prompt ?? ""
            switch p {
            case "achievement": return .goal
            case "improvement": return .habit
            case "balance": return .values
            default: return .custom
            }
        }()
        _ = store.add(
            text: limited,
            internalMode: cat == .values ? "value" : "affirmation",
            templateUsed: "ai_wizard",
            category: cat,
            morningEnabled: true,
            eveningEnabled: false
        )
        dismiss()
    }
}
