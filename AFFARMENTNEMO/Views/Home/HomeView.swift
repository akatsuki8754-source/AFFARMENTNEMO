//
//  HomeView.swift
//  ホーム: ストリーク + 今日のセット + 追加 + 今日のヒント + バナー
//  仕様: UX v4 §6
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(AffirmationStore.self) private var store
    @State private var showAdd = false
    @State private var showReadAloud = false
    @State private var showHelp = false
    @State private var showSettings = false
    @State private var dismissedTipToday = false
    @State private var navigateToTemplateForTip: AffirmationTemplate?
    @State private var firstReadPromptShown = false

    var body: some View {
        let stats = store.userStats()
        let morning = store.morningSet()
        let evening = store.eveningSet()

        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    StreakHeader(stats: stats)

                    todaysSetCard(morningSet: morning, eveningSet: evening)

                    PrimaryButton(titleKey: "home.add", action: { showAdd = true })

                    if !dismissedTipToday {
                        dailyTipCard
                    }

                    AdBannerSlot()
                        .padding(.top, AppSpacing.md)
                }
                .padding(.horizontal, AppSpacing.screenEdge)
                .padding(.bottom, AppSpacing.lg)
                .responsivePage()
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
            .fullScreenCover(isPresented: $showReadAloud) {
                ReadAloudView(items: morning.isEmpty ? evening : morning, slot: morning.isEmpty ? "evening" : "morning")
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
            VStack(spacing: AppSpacing.md) {
                if !morningSet.isEmpty {
                    setCard(titleKey: "home.set.morning",
                            items: morningSet,
                            slot: "morning")
                }
                if !eveningSet.isEmpty {
                    setCard(titleKey: "home.set.evening",
                            items: eveningSet,
                            slot: "evening")
                }
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
