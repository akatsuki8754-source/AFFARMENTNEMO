//
//  EULAView.swift
//  Apple Guideline 1.2 (UGC) 必須 — 利用規約 / 不適切コンテンツ無寛容方針
//

import SwiftUI

struct EULAView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Group {
                        Text("利用規約 (EULA)")
                            .appFont(.h2)

                        Text("最終更新: 2026年4月29日")
                            .appFont(.micro)
                            .foregroundStyle(Color.textSecondary)

                        Text("1. 本アプリは「自分の言葉で自分を変える」習慣化アプリです。完全無料で運営し、課金やサブスクリプションは一切ありません。")
                            .appFont(.body)

                        Text("2. 「流すだけタイムライン」での投稿について")
                            .appFont(.bodyEmphasis)
                        Text("本アプリは、流すだけタイムラインでの不適切なコンテンツやユーザー行為に対して一切の許容(寛容)を行いません。以下のコンテンツの投稿は禁止です:")
                            .appFont(.body)
                        VStack(alignment: .leading, spacing: 4) {
                            bullet("性的・暴力的・差別的な表現")
                            bullet("特定個人への中傷・攻撃")
                            bullet("詐欺・出会い系・スパム的な内容")
                            bullet("URL・電話番号・SNS ID 等の個人連絡先")
                            bullet("自他への危害を扇動する内容")
                        }

                        Text("3. 違反への対応")
                            .appFont(.bodyEmphasis)
                        Text("通報を受けた投稿は24時間以内に運営者が確認し、不適切と判断したコンテンツは削除し、投稿者は今後の投稿を停止する措置を取ります。")
                            .appFont(.body)

                        Text("4. ユーザーの権利")
                            .appFont(.bodyEmphasis)
                        Text("ユーザーは自身の投稿を任意のタイミングで削除できます。他のユーザーは『…』メニューから通報・ブロックが可能です。ブロックしたユーザーの投稿は端末上で非表示になります。")
                            .appFont(.body)

                        Text("5. 自動削除")
                            .appFont(.bodyEmphasis)
                        Text("流すだけタイムラインの全投稿は24時間で自動的に削除され、サーバーに永続化されません。")
                            .appFont(.body)

                        Text("6. 同意")
                            .appFont(.bodyEmphasis)
                        Text("本アプリの「投稿する」機能を初めて利用する際に本規約への同意を求めます。同意後も、いつでも投稿の停止・本アプリの削除が可能です。")
                            .appFont(.body)

                        Text("7. お問い合わせ・通報窓口")
                            .appFont(.bodyEmphasis)
                        Text("akatsuki8754@gmail.com")
                            .appFont(.body)
                            .foregroundStyle(Color.brandSecondary)
                    }
                }
                .padding(AppSpacing.lg)
            }
            .navigationTitle(Text("利用規約"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func bullet(_ s: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").foregroundStyle(Color.textSecondary)
            Text(s).appFont(.body).foregroundStyle(Color.textPrimary)
        }
    }
}
