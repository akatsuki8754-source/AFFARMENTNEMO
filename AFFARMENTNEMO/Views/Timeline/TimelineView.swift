//
//  TimelineView.swift
//  流すだけタイムライン (MASTER §14)
//  Firestore 24時間TTL + 言語ルーム + NGワード/PIIフィルタ + 通報
//

import SwiftUI

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

private enum TimelineReaction: String, CaseIterable {
    case like, heart, peace

    var icon: String {
        switch self {
        case .like: "hand.thumbsup.fill"
        case .heart: "heart.fill"
        case .peace: "sparkles"      // 「祈り・応援」のキラキラ (peace アイコン未表示問題対策で sparkles に変更)
        }
    }

    var label: String {
        switch self {
        case .like: "いいね"
        case .heart: "ハート"
        case .peace: "応援"
        }
    }
}

struct TimelineView: View {
    @AppStorage("kotodama.timeline.firstSeen") private var firstSeen: Bool = false
    @AppStorage("kotodama.timeline.canPost") private var canPost: Bool = false
    @AppStorage("kotodama.eula.accepted") private var eulaAccepted: Bool = false
    @State private var room: String = UserDefaults.standard.string(forKey: "kotodama.debug.timelineRoom")
        ?? TimelineService.defaultLanguageRoom()
    @State private var posts: [TimelinePost] = []
    @State private var showCompose = false
    @State private var showOptInForPost = false
    @State private var showEULAGate = false
    @State private var showContact = false
    @StateObject private var blocks = UserBlockStore.shared
    @State private var locallyHiddenPostIds: Set<String> = []
    @State private var sampleReactions: [String: String] = [:]
    @State private var refreshNonce = UUID()
    @State private var subscribeTask: Task<Void, Never>?
    #if canImport(FirebaseFirestore)
    @State private var listener: ListenerRegistration?
    #endif

    /// 擬似サンプル投稿 (リアル投稿数に応じて自動生成、運用無料)
    private var sampleFiller: [TimelinePost] {
        SakuraTemplateProvider.samples(for: room, realPostCount: posts.count)
    }

    /// 表示順: リアル投稿 + サンプル を createdAt 降順で混合
    private var visiblePosts: [TimelinePost] {
        let combined = posts + sampleFiller
        return combined
            .filter { !blocks.isBlocked($0.authorUid) && !locallyHiddenPostIds.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                if !firstSeen || !eulaAccepted {
                    // Apple Guideline 1.2: 流すだけ機能を初めて使う前に正式 EULA への同意必須
                    optInView
                } else {
                    streamView
                }
            }
            .navigationTitle(Text("timeline.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showContact = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel(Text("settings.contact"))
                }
            }
            .sheet(isPresented: $showCompose) {
                ComposeView(room: room) { posted in
                    if posted { canPost = true }
                }
            }
            .sheet(isPresented: $showEULAGate) {
                TimelineEULAGate(
                    onAgreed: {
                        firstSeen = true
                        eulaAccepted = true
                        canPost = true
                        showEULAGate = false
                        subscribe()
                    },
                    onCancel: { showEULAGate = false }
                )
                .interactiveDismissDisabled(true)
            }
            .sheet(isPresented: $showContact) { ContactView() }
        }
        .onAppear {
            subscribe()
            runTimelineSmokePostIfNeeded()
        }
        .onDisappear { unsubscribe() }
    }

    // MASTER §14.1
    private var optInView: some View {
        optInContent.responsivePage()
    }

    private var optInContent: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()
            Text("💬").font(.system(size: 72))
            Text("timeline.optin.title")
                .appFont(.h2)
                .foregroundStyle(Color.textPrimary)

            Text("timeline.optin.lead")
                .appFont(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                bullet("timeline.optin.b1")
                bullet("timeline.optin.b2")
                bullet("timeline.optin.b3")
            }

            Text("timeline.optin.note")
                .appFont(.caption)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, AppSpacing.sm)

            Spacer()

            // Apple Guideline 1.2: タイムライン使用前に正式 EULA への明示同意が必要
            PrimaryButton(titleKey: "timeline.eula.gate.cta") {
                showEULAGate = true
            }

            Button {
                showContact = true
            } label: {
                Text("settings.contact")
                    .appFont(.caption)
                    .foregroundStyle(Color.brandSecondary)
            }
            .padding(.top, AppSpacing.xs)

            Spacer().frame(height: AppSpacing.lg)
        }
        .padding(.horizontal, AppSpacing.screenEdge)
    }

    private var streamView: some View {
        streamContent.responsivePage(maxWidth: 720)
    }

    private var streamContent: some View {
        VStack(spacing: 0) {
            // ロケーション切替Picker (ユーザー要望: 国別タップで切替)
            HStack {
                Image(systemName: "globe").foregroundStyle(Color.semanticInfo)
                Menu {
                    ForEach(supportedRooms, id: \.timelineRoom) { entry in
                        Button {
                            if room != entry.timelineRoom {
                                room = entry.timelineRoom
                                resubscribe()
                            }
                        } label: {
                            HStack {
                                Text("\(entry.flag)  \(entry.label)")
                                if room == entry.timelineRoom { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(currentRoomFlag)
                        Text(roomLabel)
                            .appFont(.bodyEmphasis)
                            .foregroundStyle(Color.textPrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, AppSpacing.screenEdge)
            .padding(.vertical, AppSpacing.sm)
            .background(Color.bgSecondary)

            if visiblePosts.isEmpty {
                Spacer()
                VStack(spacing: AppSpacing.sm) {
                    ProgressView()
                    Text("timeline.empty")
                        .appFont(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppSpacing.sm) {
                        ForEach(visiblePosts) { post in
                            postCard(post)
                        }
                    }
                    .padding(.horizontal, AppSpacing.screenEdge)
                    .padding(.vertical, AppSpacing.md)
                }
                .refreshable {
                    await refreshTimeline()
                }
            }

            AdBannerSlot()
        }
        .id(refreshNonce)
        .overlay(alignment: .bottomTrailing) {
            Button {
                // EULA はタイムライン入場時に同意済 (eulaAccepted=true)。投稿前の追加同意は不要
                showCompose = true
            } label: {
                Label("timeline.compose", systemImage: "square.and.pencil")
                    .appFont(.bodyEmphasis)
                    .foregroundStyle(Color.bgPrimary)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .background(Color.brandPrimary)
                    .clipShape(Capsule())
            }
            .padding([.trailing, .bottom], AppSpacing.lg)
            .padding(.bottom, 50) // バナー上に被らせない
        }
    }

    private func postCard(_ post: TimelinePost) -> some View {
        let isMyPost: Bool = {
            #if canImport(FirebaseAuth)
            return post.authorUid == AuthService.shared.currentUID
            #else
            return false
            #endif
        }()
        return VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text(relativeTime(post.createdAt))
                    .appFont(.micro)
                    .foregroundStyle(Color.textSecondary)
                if isMyPost {
                    Text("timeline.myPost")
                        .appFont(.micro)
                        .foregroundStyle(Color.brandSecondary)
                }
                Spacer()
                Menu {
                    if isMyPost {
                        // 自分の投稿のみコピー可 (\u4ed6\u4eba\u306e\u30b3\u30d4\u30fc\u306f\u8155\u632f\u308a\u8868\u793a\u3092\u606f\u8a18 - \u30e6\u30fc\u30b6\u30fc\u8981\u671b)
                        Button("timeline.copy") {
                            UIPasteboard.general.string = post.text
                        }
                        Button("common.delete", role: .destructive) {
                            Task {
                                try? await TimelineService.shared.deleteOwnPost(
                                    postId: post.id, room: post.languageRoom)
                                locallyHiddenPostIds.insert(post.id)
                            }
                        }
                    } else {
                        Button("timeline.hide") {
                            locallyHiddenPostIds.insert(post.id)
                        }
                        // \u30b5\u30f3\u30d7\u30eb\u6295\u7a3f\u306f\u5831\u544a\u30fb\u30d6\u30ed\u30c3\u30af\u4e0d\u8981
                        if !SakuraTemplateProvider.isSample(post) {
                            Button("timeline.report", role: .destructive) {
                                Task {
                                    try? await TimelineService.shared.report(
                                        postId: post.id, room: post.languageRoom, reason: "user-reported")
                                    locallyHiddenPostIds.insert(post.id)
                                }
                            }
                            Button("timeline.block", role: .destructive) {
                                blocks.block(post.authorUid)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: AppTouchTarget.minimum, height: AppTouchTarget.minimum)
                }
                .accessibilityLabel(Text("timeline.menu"))
            }
            Text(post.text)
                .appFont(.body)
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            reactionRow(post)
        }
        .padding(AppSpacing.md)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
        .contextMenu {
            if !isMyPost {
                Button {
                    locallyHiddenPostIds.insert(post.id)
                } label: {
                    Label("このフィードから隠す", systemImage: "eye.slash")
                }
                if !SakuraTemplateProvider.isSample(post) {
                    Button(role: .destructive) {
                        blocks.block(post.authorUid)
                    } label: {
                        Label("このユーザーをブロック", systemImage: "person.crop.circle.badge.xmark")
                    }
                    Button(role: .destructive) {
                        Task {
                            try? await TimelineService.shared.report(
                                postId: post.id, room: post.languageRoom, reason: "long-press-report")
                            locallyHiddenPostIds.insert(post.id)
                        }
                    } label: {
                        Label("報告する", systemImage: "exclamationmark.triangle")
                    }
                }
            } else {
                Button {
                    UIPasteboard.general.string = post.text
                } label: {
                    Label("コピー", systemImage: "doc.on.doc")
                }
            }
        }
    }

    private func reactionRow(_ post: TimelinePost) -> some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(TimelineReaction.allCases, id: \.rawValue) { reaction in
                let selected = selectedReaction(for: post) == reaction.rawValue
                Button {
                    Task { await toggleReaction(post, reaction: reaction) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: reaction.icon)
                        Text("\(reactionCount(post, reaction: reaction))")
                    }
                    .appFont(.micro)
                    .foregroundStyle(selected ? Color.bgPrimary : Color.textSecondary)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, 6)
                    .background(selected ? Color.brandPrimary : Color.bgPrimary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(reaction.label))
            }
            Spacer()
        }
        .padding(.top, AppSpacing.xs)
    }

    private func selectedReaction(for post: TimelinePost) -> String? {
        if SakuraTemplateProvider.isSample(post) {
            return sampleReactions[post.id]
        }
        return post.myReaction
    }

    private func reactionCount(_ post: TimelinePost, reaction: TimelineReaction) -> Int {
        let base: Int
        switch reaction {
        case .like: base = post.reactionLike
        case .heart: base = post.reactionHeart
        case .peace: base = post.reactionPeace
        }
        if SakuraTemplateProvider.isSample(post),
           selectedReaction(for: post) == reaction.rawValue {
            return base + 1
        }
        return max(0, base)
    }

    private func toggleReaction(_ post: TimelinePost, reaction: TimelineReaction) async {
        if SakuraTemplateProvider.isSample(post) {
            if sampleReactions[post.id] == reaction.rawValue {
                sampleReactions.removeValue(forKey: post.id)
            } else {
                sampleReactions[post.id] = reaction.rawValue
            }
            refreshNonce = UUID()
            return
        }
        do {
            try await TimelineService.shared.toggleReaction(post: post, reaction: reaction.rawValue)
            await refreshTimeline()
        } catch {
            print("[Timeline] reaction failed: \(error)")
        }
    }

    private var supportedRooms: [LanguageOption] { LanguageCatalog.timelineRooms }

    private var roomLabel: String {
        LanguageCatalog.timelineRoomLabel(for: room)
    }
    private var currentRoomFlag: String {
        LanguageCatalog.timelineRoomFlag(for: room)
    }

    private func resubscribe() {
        unsubscribe()
        posts = []
        sampleReactions.removeAll()
        subscribe()
    }

    private func refreshTimeline() async {
        #if canImport(FirebaseFirestore)
        if let fetched = try? await TimelineService.shared.fetchPosts(room: room) {
            posts = fetched
        }
        #endif
        refreshNonce = UUID()
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.current
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func subscribe() {
        guard firstSeen && eulaAccepted else { return }
        #if canImport(FirebaseFirestore)
        subscribeTask?.cancel()
        let targetRoom = room
        subscribeTask = Task {
            await AuthService.shared.signInAnonymouslyIfNeeded()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                listener?.remove()
                listener = TimelineService.shared.subscribePosts(room: targetRoom) { newPosts in
                    self.posts = newPosts
                }
            }
        }
        #endif
    }

    private func unsubscribe() {
        subscribeTask?.cancel()
        subscribeTask = nil
        #if canImport(FirebaseFirestore)
        listener?.remove()
        listener = nil
        #endif
    }

    private func runTimelineSmokePostIfNeeded() {
        #if DEBUG
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "kotodama.debug.timelinePostSubmitted") == false else { return }
        let text = (defaults.string(forKey: "kotodama.debug.timelinePost") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        defaults.set(true, forKey: "kotodama.debug.timelinePostSubmitted")
        Task { @MainActor in
            do {
                try await TimelineService.shared.post(text: text, room: room)
                print("[TimelineSmoke] posted room=\(room) text=\(text)")
                await refreshTimeline()
            } catch {
                print("[TimelineSmoke] post failed room=\(room) error=\(error)")
            }
        }
        #endif
    }

    private func bullet(_ key: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.xs) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.semanticSuccess)
            Text(key)
                .appFont(.body)
                .foregroundStyle(Color.textPrimary)
        }
    }
}

// MARK: - Compose

private struct ComposeView: View {
    @Environment(\.dismiss) private var dismiss
    let room: String
    let onResult: (Bool) -> Void

    @State private var text = ""
    @State private var error: String?
    @State private var isPosting = false
    private let maxLen = 100

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                infoBanner

                TextEditor(text: $text)
                    .appFont(.body)
                    .scrollContentBackground(.hidden)
                    .padding(AppSpacing.sm)
                    .frame(minHeight: 140)
                    .background(Color.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.buttonSecondary))
                    .onChange(of: text) { _, new in
                        if new.count > maxLen { text = String(new.prefix(maxLen)) }
                    }

                HStack {
                    if let error {
                        Text(error)
                            .appFont(.caption)
                            .foregroundStyle(Color.semanticError)
                    }
                    Spacer()
                    Text("\(text.count) / \(maxLen)")
                        .appFont(.micro)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, AppSpacing.screenEdge)
            .padding(.vertical, AppSpacing.md)
            .navigationTitle(Text("timeline.compose.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        onResult(false); dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: post) {
                        if isPosting { ProgressView() } else { Text("timeline.post") }
                    }
                    .disabled(isPosting || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var infoBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("timeline.notice.pii", systemImage: "info.circle")
                .appFont(.caption)
                .foregroundStyle(Color.semanticInfo)
        }
        .padding(AppSpacing.sm)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.buttonSecondary))
    }

    private func post() {
        let v = TimelineService.validatePost(text)
        switch v {
        case .ok:
            error = nil
            isPosting = true
            Task {
                do {
                    try await TimelineService.shared.post(text: text, room: room)
                    isPosting = false
                    onResult(true)
                    dismiss()
                } catch {
                    self.error = error.localizedDescription
                    isPosting = false
                }
            }
        case .error(let msg):
            error = msg
        }
    }
}
