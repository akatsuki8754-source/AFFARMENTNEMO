//
//  TimelineView.swift
//  流すだけタイムライン (MASTER仕様書 §14)
//
//  Phase 1.5: Firebase Firestore TTL + 言語ルーム + NGワード + 通報・ブロック
//  現状: オプトイン画面 + 「準備中」プレースホルダ
//

import SwiftUI

struct TimelineView: View {
    @AppStorage("kotodama.timeline.firstSeen") private var firstSeen: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                if !firstSeen {
                    optInView
                } else {
                    placeholderView
                }
            }
            .navigationTitle(Text("timeline.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MASTER仕様書 §14.1
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
            }

            Spacer().frame(height: AppSpacing.lg)
        }
        .padding(.horizontal, AppSpacing.screenEdge)
    }

    private var placeholderView: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()
            Image(systemName: "hourglass")
                .font(.system(size: 56))
                .foregroundStyle(Color.brandAccent)
            Text("timeline.placeholder.title")
                .appFont(.h3)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
            Text("timeline.placeholder.body")
                .appFont(.caption)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.lg)
            Spacer()
            AdBannerSlot()
        }
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
