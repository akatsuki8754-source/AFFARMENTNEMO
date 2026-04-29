//
//  HelpView.swift
//  「コトダマの書き方のコツ」 (UX v4 §8.2 / 04_アファメーション科学的根拠)
//  研究紹介を「興味のある人だけ」見られる場所に集約
//

import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    Text("help.intro")
                        .appFont(.body)
                        .foregroundStyle(Color.textPrimary)

                    helpSection(numberKey: "help.tip1.num",
                                titleKey: "help.tip1.title",
                                bodyKey: "help.tip1.body",
                                citeKey: "help.tip1.cite")

                    helpSection(numberKey: "help.tip2.num",
                                titleKey: "help.tip2.title",
                                bodyKey: "help.tip2.body",
                                citeKey: "help.tip2.cite")

                    helpSection(numberKey: "help.tip3.num",
                                titleKey: "help.tip3.title",
                                bodyKey: "help.tip3.body",
                                citeKey: "help.tip3.cite")

                    helpSection(numberKey: "help.tip4.num",
                                titleKey: "help.tip4.title",
                                bodyKey: "help.tip4.body",
                                citeKey: nil)

                    Divider().padding(.vertical, AppSpacing.sm)

                    Text("help.disclaimer")
                        .appFont(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, AppSpacing.screenEdge)
                .padding(.vertical, AppSpacing.lg)
                .responsivePage()
            }
            .background(Color.bgPrimary.ignoresSafeArea())
            .navigationTitle(Text("help.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("common.close") }
                }
            }
        }
    }

    private func helpSection(numberKey: LocalizedStringKey,
                              titleKey: LocalizedStringKey,
                              bodyKey: LocalizedStringKey,
                              citeKey: LocalizedStringKey?) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(numberKey)
                    .appFont(.bodyEmphasis)
                    .foregroundStyle(Color.brandAccent)
                Text(titleKey)
                    .appFont(.h3)
                    .foregroundStyle(Color.textPrimary)
            }
            Text(bodyKey)
                .appFont(.body)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let citeKey {
                Text(citeKey)
                    .appFont(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .italic()
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
    }
}
