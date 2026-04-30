//
//  PrimaryButton.swift
//  仕様 §1.5: 最小高さ 48pt / コーナー 12pt / 1行のみ
//

import SwiftUI

struct PrimaryButton: View {
    let titleKey: LocalizedStringKey
    let action: () -> Void
    var isEnabled: Bool = true

    var body: some View {
        Button(action: action) {
            Text(titleKey)
                .appFont(.h3)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 56)
                .padding(.horizontal, AppSpacing.md)
                .background(isEnabled ? Color.brandPrimary : Color.textDisabled)
                .foregroundStyle(Color.bgPrimary)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
        }
        .disabled(!isEnabled)
    }
}

struct SecondaryButton: View {
    let titleKey: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(titleKey)
                .appFont(.bodyEmphasis)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: AppTouchTarget.buttonHeight)
                .padding(.horizontal, AppSpacing.md)
                .background(Color.bgSecondary)
                .foregroundStyle(Color.textPrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.buttonSecondary, style: .continuous)
                        .stroke(Color.borderDefault, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.buttonSecondary, style: .continuous))
        }
    }
}

struct TextLinkButton: View {
    let titleKey: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(titleKey)
                .appFont(.body)
                .foregroundStyle(Color.brandSecondary)
                .frame(minHeight: AppTouchTarget.minimum)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        PrimaryButton(titleKey: "onboard.start", action: {})
        SecondaryButton(titleKey: "common.skip", action: {})
        TextLinkButton(titleKey: "common.later", action: {})
    }
    .padding()
}
