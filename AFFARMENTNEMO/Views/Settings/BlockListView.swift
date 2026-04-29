//
//  BlockListView.swift
//  Apple Guideline 1.2 — ブロックしたユーザーの一覧 + 解除
//

import SwiftUI

struct BlockListView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var blocks = UserBlockStore.shared

    var body: some View {
        NavigationStack {
            Group {
                if blocks.blockedUIDs.isEmpty {
                    VStack(spacing: AppSpacing.md) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.textDisabled)
                        Text("ブロック中のユーザーはいません")
                            .appFont(.body)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            ForEach(Array(blocks.blockedUIDs.sorted()), id: \.self) { uid in
                                HStack {
                                    Image(systemName: "person.crop.circle")
                                        .foregroundStyle(Color.textSecondary)
                                    Text("コトダマユーザー#\(uid.suffix(4))")
                                        .appFont(.body)
                                    Spacer()
                                    Button("解除") {
                                        blocks.unblock(uid)
                                    }
                                    .foregroundStyle(Color.brandSecondary)
                                }
                            }
                        }
                        if blocks.blockedUIDs.count > 1 {
                            Section {
                                Button("すべて解除", role: .destructive) {
                                    blocks.unblockAll()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(Text("ブロック中のユーザー"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}
