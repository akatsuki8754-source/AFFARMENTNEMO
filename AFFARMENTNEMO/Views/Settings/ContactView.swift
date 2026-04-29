//
//  ContactView.swift
//  Apple Guideline 1.2 / 1.5 — アプリ内に連絡先・通報窓口を提供
//

import SwiftUI

struct ContactView: View {
    @Environment(\.dismiss) private var dismiss

    private let supportEmail = "akatsuki0207@hotmail.co.jp"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text("お問い合わせ")
                        .appFont(.h2)

                    Text("ご意見・不具合報告・タイムラインの不適切コンテンツに関する通報は、以下のメールアドレスまでお寄せください。24時間以内に確認・対応します。")
                        .appFont(.body)
                        .foregroundStyle(Color.textPrimary)

                    Button {
                        if let url = URL(string: "mailto:\(supportEmail)?subject=コトダマ%20お問い合わせ") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "envelope.fill")
                            Text(supportEmail)
                                .appFont(.bodyEmphasis)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }
                        .padding()
                        .background(Color.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
                    }
                    .foregroundStyle(Color.brandPrimary)

                    Text("通報されたコンテンツは内容を確認の上、ガイドライン違反と判断されたものは削除し、投稿者の今後の投稿を停止します。")
                        .appFont(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.top, AppSpacing.sm)
                }
                .padding(AppSpacing.lg)
            }
            .navigationTitle(Text("お問い合わせ"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}
