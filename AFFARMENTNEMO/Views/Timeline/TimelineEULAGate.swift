//
//  TimelineEULAGate.swift
//  Apple Guideline 1.2 — タイムライン利用前の正式 EULA 同意ゲート
//

import SwiftUI

struct TimelineEULAGate: View {
    let onAgreed: () -> Void
    let onCancel: () -> Void
    @State private var hasScrolledToEnd: Bool = false
    @State private var checkedAgreement: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text("利用規約 (End-User License Agreement)")
                        .appFont(.h2)

                    Text("「流すだけタイムライン」を利用する前に、本利用規約に同意してください。")
                        .appFont(.body)
                        .foregroundStyle(Color.textSecondary)

                    Group {
                        section("1. ライセンス付与",
                                "本アプリ「コトダマ｜自分の言葉」は、ユーザに対して個人利用に限る譲渡不可・非独占・取消可能なライセンスを付与します。")

                        section("2. ユーザー生成コンテンツ — 不適切な内容に対するゼロ寛容方針",
                                """
                                開発者は、流すだけタイムラインに投稿される不適切なコンテンツ及び \
                                悪質なユーザーに対して、一切の許容(寛容)を行いません。

                                以下を厳格に禁止します:
                                ・性的・わいせつな表現、ポルノ
                                ・暴力、脅迫、ヘイトスピーチ、差別 (人種・宗教・性別・性的指向など)
                                ・特定個人への中傷、嫌がらせ、ターゲット攻撃
                                ・スパム、広告、詐欺、出会い系勧誘
                                ・URL・電話番号・メール・SNS ID 等の個人連絡先
                                ・自他への危害を扇動する内容、自殺扇動
                                ・違法薬物の促進、その他違法行為の助長
                                ・知的財産権の侵害
                                """)

                        section("3. 通報・モデレーション体制",
                                """
                                ・各投稿の「⋯」メニューから「報告する」「ブロック」「隠す」「削除」が可能です。
                                ・通報されたコンテンツは開発者が【24時間以内】に確認します。違反と判断された場合は \
                                投稿を削除し、投稿者の今後の投稿を停止します。
                                ・流すだけタイムラインの全投稿は【24時間で自動削除】されます。
                                ・自分の投稿は「⋯」→「削除」で即時に削除可能です。
                                ・他人の投稿は「⋯」→「ブロック」または「隠す」で即時に自分のフィードから除外可能です。
                                """)

                        section("4. ユーザの責任",
                                """
                                ・禁止コンテンツを投稿しないことに同意します。
                                ・違反時は投稿停止・利用停止措置の対象となることを了承します。
                                ・投稿内容についてはユーザに帰属しますが、表示期間 (最大24時間) について開発者に表示権を許諾します。
                                """)

                        section("5. プライバシー",
                                "本アプリは Firebase Anonymous Authentication を使用し、必要以上の個人情報は収集しません。詳細はプライバシーポリシーをご確認ください。")

                        section("6. 免責",
                                "本アプリは現状のまま提供されます。開発者は商品性・特定目的適合性を含め、明示・黙示を問わずいかなる保証も行いません。")

                        section("7. 変更",
                                "本規約は予告なく変更されることがあります。変更後の利用は変更後の規約への同意とみなされます。")

                        section("8. お問い合わせ・通報窓口",
                                "akatsuki0207@hotmail.co.jp\n(24時間以内に応答)")
                    }
                    .id("body-content")

                    Color.clear.frame(height: 1)
                        .onAppear { hasScrolledToEnd = true }

                    Toggle(isOn: $checkedAgreement) {
                        Text("上記の規約をすべて読み、同意します")
                            .appFont(.body)
                            .foregroundStyle(Color.textPrimary)
                    }
                    .padding(.top, AppSpacing.md)
                    .disabled(!hasScrolledToEnd)
                    .opacity(hasScrolledToEnd ? 1 : 0.4)

                    if !hasScrolledToEnd {
                        Text("⬇ 最後までスクロールしてください")
                            .appFont(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .padding(AppSpacing.lg)
            }
            .background(Color.bgPrimary)
            .navigationTitle(Text("利用規約への同意"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("同意する") { onAgreed() }
                        .disabled(!checkedAgreement)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .appFont(.bodyEmphasis)
                .foregroundStyle(Color.textPrimary)
            Text(body)
                .appFont(.body)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
