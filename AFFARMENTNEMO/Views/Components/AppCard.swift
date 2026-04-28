//
//  AppCard.swift
//  カード共通コンテナ (仕様 §1.5)
//

import SwiftUI

struct AppCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            .appCardShadow()
    }
}

struct DismissableCard<Content: View>: View {
    @ViewBuilder var content: Content
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: AppTouchTarget.minimum, height: AppTouchTarget.minimum)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("common.close"))
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm + 2)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
    }
}
