//
//  TimelineView.swift
//  流すだけタイムライン (MASTER §14)
//  Firestore 24時間TTL + 言語ルーム + NGワード/PIIフィルタ + 通報
//

import SwiftUI

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

struct TimelineView: View {
    @AppStorage("kotodama.timeline.firstSeen") private var firstSeen: Bool = false
    @AppStorage("kotodama.timeline.canPost") private var canPost: Bool = false
    @State private var room: String = TimelineService.defaultLanguageRoom()
    @State private var posts: [TimelinePost] = []
    @State private var showCompose = false
    @State private var showOptInForPost = false
    #if canImport(FirebaseFirestore)
    @State private var listener: ListenerRegistration?
    #endif

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                if !firstSeen {
                    optInView
                } else {
                    streamView
                }
            }
            .navigationTitle(Text("timeline.title"))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showCompose) {
                ComposeView(room: room) { posted in
                    if posted { canPost = true }
                }
            }
            .alert("timeline.optin.post.title", isPresented: $showOptInForPost) {
                Button("common.cancel", role: .cancel) {}
                Button("timeline.optin.post.cta") {
                    canPost = true
                    showCompose = true
                }
            } message: {
                Text("timeline.optin.post.body")
            }
        }
        .onAppear { subscribe() }
        .onDisappear { unsubscribe() }
    }

    // MASTER §14.1
    private var optInView: some View {
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

            PrimaryButton(titleKey: "timeline.optin.cta") {
                firstSeen = true
                subscribe()
            }

            Spacer().frame(height: AppSpacing.lg)
        }
        .padding(.horizontal, AppSpacing.screenEdge)
    }

    private var streamView: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "globe").foregroundStyle(Color.semanticInfo)
                Text("timeline.room.\(roomLabel)")
                    .appFont(.caption)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("timeline.expires.note")
                    .appFont(.micro)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, AppSpacing.screenEdge)
            .padding(.vertical, AppSpacing.sm)
            .background(Color.bgSecondary)

            if posts.isEmpty {
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
                        ForEach(posts) { post in
                            postCard(post)
                        }
                    }
                    .padding(.horizontal, AppSpacing.screenEdge)
                    .padding(.vertical, AppSpacing.md)
                }
            }

            AdBannerSlot()
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                if canPost {
                    showCompose = true
                } else {
                    showOptInForPost = true
                }
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
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text(relativeTime(post.createdAt))
                    .appFont(.micro)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Menu {
                    Button("timeline.copy") {
                        UIPasteboard.general.string = post.text
                    }
                    Button("timeline.report", role: .destructive) {
                        Task {
                            try? await TimelineService.shared.report(
                                postId: post.id, room: post.languageRoom, reason: "user-reported")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: AppTouchTarget.minimum, height: AppTouchTarget.minimum)
                }
            }
            Text(post.text)
                .appFont(.body)
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppSpacing.md)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
    }

    private var roomLabel: String {
        switch room {
        case "ja_JP": "日本語"
        case "en": "English"
        case "zh_CN": "中文(简)"
        case "zh_TW": "中文(繁)"
        case "ko_KR": "한국어"
        default: room
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.current
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func subscribe() {
        guard firstSeen else { return }
        #if canImport(FirebaseFirestore)
        listener?.remove()
        listener = TimelineService.shared.subscribePosts(room: room) { newPosts in
            self.posts = newPosts
        }
        #endif
    }

    private func unsubscribe() {
        #if canImport(FirebaseFirestore)
        listener?.remove()
        listener = nil
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
            Label("timeline.notice.expire", systemImage: "info.circle")
                .appFont(.caption)
                .foregroundStyle(Color.semanticInfo)
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
