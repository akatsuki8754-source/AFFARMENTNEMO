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

    /// オンボーディング 1 ページ目から呼ばれた場合 true (リワード広告ゲートをスキップ)
    let isOnboardingFirstUse: Bool

    init(isOnboardingFirstUse: Bool = false) {
        self.isOnboardingFirstUse = isOnboardingFirstUse
    }

    @State private var path: [WishMapNode] = []
    @State private var candidates: [String] = []
    @State private var liveEnabledHint: Bool? = nil  // 起動時 prefetch、UI でバッジ表示
    @State private var selectedTexts: Set<String> = []
    @State private var step: WizardStep = .selectingPath
    @State private var generationTask: Task<Void, Never>?
    /// 任意の追加コンテキスト (300 字上限 — Hick's Law / Context Rot 配慮 / コスト設計)
    @State private var freeformContext: String = ""
    @State private var showFreeformInput: Bool = false
    @StateObject private var freeformHandler = EditableTextHandler()
    @State private var freeformFocused: Bool = false
    private let maxFreeformLen = 300
    /// 各階層で「その他」を押した回数 (3択ローテーションのため)
    @State private var rotationOffsetByLevel: [Int: Int] = [:]
    /// 候補再生成カウント (静的サンプルでも順序を変えるため)
    @State private var regenerateNonce: Int = 0
    /// 候補の生成元 ("gemini" / "local" / "fallback")
    @State private var candidateSource: CandidateSource = .local

    enum CandidateSource {
        case gemini   // Gemini API から本物
        case local    // 静的サンプル (Phase 1.5)
        case fallback // Gemini 失敗 → 静的フォールバック

        var label: String {
            switch self {
            case .gemini:   return "✨ AI 生成 (Gemini)"
            case .local:    return "📚 ローカル候補"
            case .fallback: return "📚 ローカル候補 (AIフォールバック)"
            }
        }

        var color: Color {
            switch self {
            case .gemini:   return .brandPrimary
            case .local:    return .textSecondary
            case .fallback: return .textSecondary
            }
        }
    }

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
            .task {
                // 起動時に liveGenerationEnabled を prefetch (auth + Firestore 読み)
                // ユーザーが path 選択中に並列で済ませる → generate() 時には判定済
                if liveEnabledHint == nil {
                    let live = await AIWishGenerationService.shared.liveGenerationEnabled()
                    await MainActor.run { liveEnabledHint = live }
                }
                // DEBUG: kotodama.debug.autoGenerateAI=true で path 自動選択 + 生成
                #if DEBUG
                if UserDefaults.standard.bool(forKey: "kotodama.debug.autoGenerateAI") && path.isEmpty {
                    try? await Task.sleep(for: .milliseconds(500))
                    await MainActor.run {
                        // 「達成したい > 資格・試験 > 1ヶ月以内」を自動選択
                        if let achievement = KnowledgeMap.root.children.first,
                           let exam = achievement.children.first,
                           let oneMonth = exam.children.first {
                            path = [achievement, exam, oneMonth]
                            generate()
                        }
                    }
                }
                #endif
            }
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

                    HStack(spacing: AppSpacing.xs) {
                        Text("3つから選んでみてね")
                            .appFont(.caption)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        // AI 利用可否バッジ (起動時 prefetch 済)
                        if let live = liveEnabledHint {
                            HStack(spacing: 2) {
                                Image(systemName: live ? "sparkles" : "doc.text")
                                Text(live ? "AI 生成 ON" : "ローカル候補")
                                    .appFont(.micro)
                            }
                            .foregroundStyle(live ? Color.brandPrimary : Color.textSecondary)
                            .padding(.horizontal, AppSpacing.xs)
                            .padding(.vertical, 2)
                            .background(
                                live
                                    ? Color.brandAccent.opacity(0.18)
                                    : Color.bgSecondary
                            )
                            .clipShape(Capsule())
                        }
                    }
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

                    // 自分で入力 — Choice Architecture (Thaler) で「自由記述」を明示的選択肢に格上げ
                    Button {
                        withAnimation { showFreeformInput = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            freeformFocused = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: "pencil.and.outline")
                                .foregroundStyle(Color.brandPrimary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("自分の言葉で伝える")
                                    .appFont(.bodyEmphasis)
                                    .foregroundStyle(Color.textPrimary)
                                Text("300字までAIに状況を伝えて生成")
                                    .appFont(.micro)
                                    .foregroundStyle(Color.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.md)
                        .background(Color.brandAccent.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, AppSpacing.screenEdge)

                if !currentChildren.isEmpty {
                    Text("最後まで進むと、AIが3つの言葉を提案します")
                        .appFont(.micro)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, AppSpacing.screenEdge)
                        .padding(.top, AppSpacing.sm)
                }

                // 自由入力 (showFreeformInput が ON のとき path に依らず表示)
                if showFreeformInput {
                    freeformInputSection
                        .padding(.horizontal, AppSpacing.screenEdge)
                        .padding(.top, AppSpacing.md)

                    // 自由入力からそのまま AI 生成へ進める CTA
                    Button {
                        if path.isEmpty {
                            // path なしでも動くよう root の最初の子を仮 path として設定
                            if let first = KnowledgeMap.root.children.first {
                                path = [first]
                            }
                        }
                        generate()
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("この内容で AI に作ってもらう")
                                .appFont(.bodyEmphasis)
                        }
                        .frame(maxWidth: .infinity, minHeight: AppTouchTarget.buttonHeight)
                        .foregroundStyle(Color.bgPrimary)
                        .background(Color.brandPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
                    }
                    .buttonStyle(.plain)
                    .disabled(freeformContext.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                    .opacity(freeformContext.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 ? 0.5 : 1)
                    .padding(.horizontal, AppSpacing.screenEdge)
                    .padding(.top, AppSpacing.md)
                }

                Spacer().frame(height: AppSpacing.xl)
            }
            .padding(.top, AppSpacing.md)
        }
    }

    /// AIに渡す自由テキスト入力エリア
    /// - 300字上限: Hick's Law / Context Rot (Chroma 2024 研究) / コスト管理
    /// - パス選択肢に並ぶ独立 CTA から展開
    /// - EditableTextView を流用 (全選択/コピー/貼付/取消/全削除)
    private var freeformInputSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "pencil.and.outline")
                    .foregroundStyle(Color.brandPrimary)
                Text("自分の言葉で詳しく")
                    .appFont(.bodyEmphasis)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("\(freeformContext.count) / \(maxFreeformLen)")
                    .appFont(.micro)
                    .foregroundStyle(freeformContext.count > maxFreeformLen
                        ? Color.semanticError : Color.textSecondary)
                Button {
                    withAnimation { showFreeformInput = false }
                    freeformFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.textSecondary)
                }
            }
            EditableTextView(
                text: $freeformContext,
                handler: .constant(freeformHandler),
                placeholder: "例: 来月の英語試験で 8 割取りたい。集中力が課題で、毎晩スマホを見て寝るのが遅くなる。改善したい。",
                maxLength: maxFreeformLen,
                minHeight: 120,
                isFocused: $freeformFocused
            )
            .frame(minHeight: 120)
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.buttonSecondary))
            .overlay(alignment: .top) {
                EditableActionToast(handler: freeformHandler)
                    .padding(.top, 4)
            }
            Text("※ あなたの状況・期間・障害を入れると AI が具体的な言葉を返します")
                .appFont(.micro)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Step 2: 生成中 (ライブ AI かローカルかで表示を変える)
    @State private var generatingMode: GeneratingMode = .checking

    enum GeneratingMode {
        case checking   // aiRuntime.clientEnabled をチェック中
        case askingAI   // Gemini に問合せ中
        case localOnly  // 静的サンプルから準備中

        var icon: String {
            switch self {
            case .checking, .localOnly: return "sparkles"
            case .askingAI: return "wand.and.stars"
            }
        }
        var title: String {
            switch self {
            case .checking:   return "準備中…"
            case .askingAI:   return "✨ AI が言葉を編んでいます…"
            case .localOnly:  return "📚 候補を準備中…"
            }
        }
        var subtitle: String {
            switch self {
            case .checking:   return "サービス状態を確認しています"
            case .askingAI:   return "Gemini Flash-Lite が研究知見ベースで言葉を生成中です"
            case .localOnly:  return "ローカルに用意されたテンプレートから候補を準備しています"
            }
        }
        var color: Color {
            switch self {
            case .checking, .localOnly: return .textSecondary
            case .askingAI: return .brandPrimary
            }
        }
    }

    private var generatingView: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: generatingMode.icon)
                    .font(.system(size: 32))
                    .foregroundStyle(generatingMode.color)
                ProgressView()
                    .scaleEffect(1.4)
            }
            Text(generatingMode.title)
                .appFont(.h3)
                .foregroundStyle(generatingMode.color)
                .multilineTextAlignment(.center)
            Text(generatingMode.subtitle)
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
                    // 生成元バッジ (Gemini か ローカルか 一目でわかる)
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: candidateSource == .gemini ? "sparkles" : "doc.text")
                        Text(candidateSource.label)
                            .appFont(.caption)
                    }
                    .foregroundStyle(candidateSource.color)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.xs)
                    .background(
                        candidateSource == .gemini
                            ? Color.brandAccent.opacity(0.15)
                            : Color.bgSecondary
                    )
                    .clipShape(Capsule())
                    .padding(.horizontal, AppSpacing.screenEdge)

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
        // candidateSource が gemini なら再度 AI 呼出、それ以外はローカルで順序変え
        if candidateSource == .gemini {
            performGenerate()  // AI に再依頼 (リワード広告 + クォータ消費する)
            return
        }
        let base = KnowledgeMap.generateCandidates(for: path)
        if base.count > 1 {
            let rotateBy = regenerateNonce % base.count
            candidates = Array(base[rotateBy...] + base[..<rotateBy])
        } else {
            candidates = base
        }
        candidateSource = .local
    }

    private func generate() {
        performGenerate()
    }

    private func performGenerate() {
        step = .generating
        generatingMode = .checking
        generationTask?.cancel()
        // B7: Task を保持してキャンセル可能に
        generationTask = Task { @MainActor in
            // ── 1. Firestore aiRuntime.clientEnabled をチェック (runtime gate) ──
            let liveEnabled = await AIWishGenerationService.shared.liveGenerationEnabled()
            if Task.isCancelled { return }

            if !liveEnabled {
                // Phase 1.5: 静的サンプルにフォールバック
                generatingMode = .localOnly
                try? await Task.sleep(for: .milliseconds(700))
                if Task.isCancelled { return }
                candidates = KnowledgeMap.generateCandidates(for: path)
                candidateSource = .local
                selectedTexts = []
                step = .showCandidates
                return
            }

            // ── 2. リワード広告ゲート ──
            // - DEBUG: autoGenerateAI フラグ ON 時はスキップ
            // - オンボ初回 (isOnboardingFirstUse=true): スキップ (体験を阻害しない)
            // - それ以外: 1日1回無料、以降リワード必須
            let granted: Bool
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "kotodama.debug.autoGenerateAI") {
                granted = true
            } else {
                granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                    AdRewardGate.shared.presentBeforeAIGeneration(isOnboardingFirstUse: isOnboardingFirstUse) { g in
                        cont.resume(returning: g)
                    }
                }
            }
            #else
            granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AdRewardGate.shared.presentBeforeAIGeneration(isOnboardingFirstUse: isOnboardingFirstUse) { g in
                    cont.resume(returning: g)
                }
            }
            #endif
            if !granted {
                // ユーザーが広告スキップ → 生成中断、選択画面に戻る
                step = .selectingPath
                return
            }
            if Task.isCancelled { return }

            // ── 3. Gemini Cloud Function 呼出 ──
            generatingMode = .askingAI
            do {
                let result = try await AIWishGenerationService.shared.generate(
                    path: path,
                    userContext: freeformContext
                )
                if Task.isCancelled { return }
                candidates = result
                candidateSource = .gemini
            } catch {
                // Gemini 失敗時は静的サンプルにフォールバック (UX 阻害しない)
                if Task.isCancelled { return }
                candidates = KnowledgeMap.generateCandidates(for: path)
                candidateSource = .fallback
            }
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
