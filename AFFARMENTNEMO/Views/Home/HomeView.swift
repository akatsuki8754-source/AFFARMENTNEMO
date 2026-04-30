//
//  HomeView.swift
//  ホーム: ストリーク + 今日のセット + 追加 + 今日のヒント + バナー
//  仕様: UX v4 §6
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(AffirmationStore.self) private var store
    /// ホーム読み上げセット (順序保持・includeInRoutine=true のみ)
    @Query(filter: #Predicate<Affirmation> { $0.isActive && $0.includeInRoutine },
           sort: [SortDescriptor(\.orderIndex)])
    private var routineItems: [Affirmation]
    @State private var showAdd = false
    @State private var showReadAloud = false
    @State private var showHelp = false
    @State private var showSettings = false
    @State private var dismissedTipToday = false
    @State private var navigateToTemplateForTip: AffirmationTemplate?
    @State private var firstReadPromptShown = false
    @State private var showRoutineEditor = false

    var body: some View {
        let stats = store.userStats()
        // ルーティン (順序付き) を主データソースに変更
        let morning: [Affirmation] = routineItems
        let evening: [Affirmation] = []

        NavigationStack {
            ScrollView {
                // v2: スリム化 — Hero (今日のセット) を主役にし、ヒント・ストリークは控えめに
                VStack(spacing: AppSpacing.lg) {
                    // Hero: 今日読み上げる短冊 (中央配置、breathing space 確保)
                    todaysSetCard(morningSet: morning, eveningSet: evening)
                        .padding(.top, AppSpacing.md)

                    // Primary CTA: 短冊追加
                    PrimaryButton(titleKey: "home.add.tanzaku", action: { showAdd = true })

                    // ストリーク (小さく、副次情報として)
                    StreakHeader(stats: stats)
                        .padding(.top, AppSpacing.xs)

                    // 今日のヒント (1日1回、消去可、最後に表示)
                    if !dismissedTipToday {
                        dailyTipCard
                            .padding(.top, AppSpacing.sm)
                    }

                    // バナーは Stack 内には置かず、ScrollView 外で safeAreaInset で底固定 (上に来すぎバグ修正)
                }
                .padding(.horizontal, AppSpacing.screenEdge)
                .padding(.bottom, AppSpacing.lg)
                .responsivePage()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // AdMob バナーを画面底部に固定 (内容が短くても上に被ってこない)
                AdBannerSlot()
                    .background(Color.bgPrimary)
            }
            .background(Color.bgPrimary.ignoresSafeArea())
            .navigationTitle(greetingTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showHelp = true } label: {
                            Label(NSLocalizedString("home.menu.help", comment: ""), systemImage: "questionmark.circle")
                        }
                        Button { showSettings = true } label: {
                            Label(NSLocalizedString("home.menu.settings", comment: ""), systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Color.textPrimary)
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddAffirmationView(initialTemplate: navigateToTemplateForTip)
                    .onDisappear { navigateToTemplateForTip = nil }
            }
            .sheet(isPresented: $showRoutineEditor) {
                RoutineEditorView()
            }
            .fullScreenCover(isPresented: $showReadAloud) {
                ReadAloudView(items: routineItems, slot: "routine")
            }
            .sheet(isPresented: $showHelp) {
                HelpView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .onAppear {
                if !firstReadPromptShown && !morning.isEmpty {
                    firstReadPromptShown = true
                }
            }
        }
    }

    /// 内部分類 → 表示アイコン (MASTER §11.2)
    private func iconFor(_ aff: Affirmation) -> String {
        switch aff.internalMode {
        case "value": return "⭐"
        case "ifThen": return "💪"
        default:      return "🌟"
        }
    }

    private var greetingTitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let key: String
        switch hour {
        case 4..<11: key = "home.greeting.morning"
        case 11..<17: key = "home.greeting.afternoon"
        default: key = "home.greeting.evening"
        }
        return NSLocalizedString(key, comment: "")
    }

    @ViewBuilder
    private func todaysSetCard(morningSet: [Affirmation], eveningSet: [Affirmation]) -> some View {
        if morningSet.isEmpty && eveningSet.isEmpty {
            AppCard {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("home.empty.title")
                        .appFont(.h3)
                        .foregroundStyle(Color.textPrimary)
                    Text("home.empty.body")
                        .appFont(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        } else {
            // 「朝」「夜」名称中立化 + RPA見た目の順次フロー UI
            // ユーザー要望: 「朝のセット」も中立に / RPAみたいな見た目で順次タスク化
            let combined: [Affirmation] = {
                // 重複排除して順序保持
                var seen = Set<String>()
                var result: [Affirmation] = []
                for a in (morningSet + eveningSet) where seen.insert(a.id.uuidString).inserted {
                    result.append(a)
                }
                return result
            }()
            VStack(spacing: AppSpacing.md) {
                routineFlowCard(items: combined)
            }
        }
    }

    /// RPA "見た目だけ" の順次フロー UI: ステップ番号 + 矢印 + 全部読むCTA
    private func routineFlowCard(items: [Affirmation]) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Text("home.todaysSet")
                        .appFont(.h3)
                        .foregroundStyle(Color.textPrimary)
                    Text("(\(items.count))")
                        .appFont(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    // ユーザー要望: ホームから編集 (順序・追加・削除)
                    Button {
                        showRoutineEditor = true
                    } label: {
                        Label("編集", systemImage: "slider.horizontal.3")
                            .appFont(.caption)
                            .foregroundStyle(Color.brandSecondary)
                    }
                }

                // RPA風ステップ表示 (上から順に①②③)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    ForEach(Array(items.prefix(5).enumerated()), id: \.element.id) { idx, aff in
                        HStack(alignment: .top, spacing: AppSpacing.xs) {
                            // ステップ番号
                            ZStack {
                                Circle()
                                    .fill(Color.brandAccent.opacity(0.2))
                                    .frame(width: 22, height: 22)
                                Text("\(idx + 1)")
                                    .appFont(.micro)
                                    .foregroundStyle(Color.brandPrimary)
                            }
                            Text(iconFor(aff))
                                .font(.system(size: 14))
                            Text(aff.text)
                                .appFont(.body)
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(2)
                        }
                        // 矢印 (最後以外)
                        if idx < min(items.count, 5) - 1 {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.textDisabled)
                                .padding(.leading, 11)
                        }
                    }
                    if items.count > 5 {
                        Text("home.set.more.\(items.count - 5)")
                            .appFont(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .padding(.top, AppSpacing.xs)
                    }
                }

                Button {
                    showReadAloud = true
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("home.set.read")
                    }
                    .appFont(.bodyEmphasis)
                    .foregroundStyle(Color.bgPrimary)
                    .frame(maxWidth: .infinity, minHeight: AppTouchTarget.buttonHeight)
                    .background(Color.brandPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.button))
                }
                .padding(.top, AppSpacing.xs)
            }
        }
    }

    private func setCard(titleKey: LocalizedStringKey,
                         items: [Affirmation],
                         slot: String) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Text(titleKey)
                        .appFont(.h3)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text("(\(items.count))")
                        .appFont(.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                ForEach(items.prefix(3)) { aff in
                    HStack(alignment: .top, spacing: AppSpacing.xs) {
                        // MASTER §11.2: 内部分類でアイコン自動付与
                        Text(iconFor(aff))
                            .font(.system(size: 14))
                        Text(aff.text)
                            .appFont(.body)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(2)
                    }
                }
                if items.count > 3 {
                    Text("home.set.more.\(items.count - 3)")
                        .appFont(.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                Button {
                    showReadAloud = true
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("home.set.read")
                    }
                    .appFont(.bodyEmphasis)
                    .foregroundStyle(Color.bgPrimary)
                    .frame(maxWidth: .infinity, minHeight: AppTouchTarget.buttonHeight)
                    .background(Color.brandPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.button))
                }
                .padding(.top, AppSpacing.xs)
            }
        }
    }

    private var dailyTipCard: some View {
        let tip = DailyTipProvider.tipForToday()
        return DismissableCard(content: {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(Color.brandAccent)
                        .font(.system(size: 14))
                    Text("home.tip.title")
                        .appFont(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Text(LocalizedStringKey(tip.messageKey))
                    .appFont(.body)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let tplId = tip.templateId,
                   let tpl = AffirmationTemplate.all.first(where: { $0.id == tplId }) {
                    Button {
                        navigateToTemplateForTip = tpl
                        showAdd = true
                    } label: {
                        Text("home.tip.try")
                            .appFont(.caption)
                            .foregroundStyle(Color.brandSecondary)
                    }
                    .padding(.top, 2)
                }
            }
        }, onDismiss: { dismissedTipToday = true })
    }
}

// MARK: - Streak Header

struct StreakHeader: View {
    let stats: UserStats

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(Color.brandAccent)
                    Text("home.streak.\(stats.currentStreak)")
                        .appFont(.bodyEmphasis)
                        .foregroundStyle(Color.textPrimary)
                    if stats.currentStreak >= 7 {
                        Text("✨")
                    }
                    Spacer()
                }
                HStack {
                    Text("home.level.\(stats.level)")
                        .appFont(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text("XP \(stats.xp)/\(stats.xpForNextLevel())")
                        .appFont(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                ProgressView(value: stats.levelProgress)
                    .tint(Color.brandSecondary)
            }
        }
    }
}
