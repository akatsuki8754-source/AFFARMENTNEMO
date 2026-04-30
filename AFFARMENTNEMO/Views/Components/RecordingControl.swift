//
//  RecordingControl.swift
//  Add/Edit 共通の「自分の声を録音/再生/削除」コンポーネント
//

import SwiftUI

struct RecordingControl: View {
    /// 既存の録音ファイル名 (なければ nil)。録音/削除に応じて binding 経由で更新する。
    @Binding var fileName: String?
    /// 関連 Affirmation の id (新ファイル名生成用)
    let affirmationId: UUID

    @StateObject private var rec = RecordingService.shared
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Image(systemName: "mic.fill").foregroundStyle(Color.brandPrimary)
                Text("自分の声で録音 (任意)")
                    .appFont(.bodyEmphasis)
                Spacer()
                if rec.hasRecording(fileName: fileName) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.semanticSuccess)
                        .accessibilityLabel(Text("録音済み"))
                }
            }

            HStack(spacing: AppSpacing.sm) {
                // 録音 ↔ 停止
                Button {
                    if rec.isRecording {
                        rec.stopRecording()
                    } else {
                        Task { await startRecording() }
                    }
                } label: {
                    Label(rec.isRecording ? "停止" : (rec.hasRecording(fileName: fileName) ? "録音し直す" : "録音"),
                          systemImage: rec.isRecording ? "stop.circle.fill" : "record.circle")
                        .appFont(.body)
                        .frame(maxWidth: .infinity, minHeight: AppTouchTarget.buttonHeight)
                        .background(rec.isRecording ? Color.semanticError.opacity(0.15) : Color.bgSecondary)
                        .foregroundStyle(rec.isRecording ? Color.semanticError : Color.brandPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.buttonSecondary))
                }

                // 再生 (ファイルあり時のみ)
                if let fn = fileName, rec.hasRecording(fileName: fn) {
                    Button {
                        play(fileName: fn)
                    } label: {
                        Label(rec.isPlaying ? "停止" : "再生",
                              systemImage: rec.isPlaying ? "stop.fill" : "play.fill")
                            .appFont(.body)
                            .frame(maxWidth: .infinity, minHeight: AppTouchTarget.buttonHeight)
                            .background(Color.bgSecondary)
                            .foregroundStyle(Color.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.buttonSecondary))
                    }
                }

                // 削除
                if let fn = fileName, rec.hasRecording(fileName: fn) {
                    Button(role: .destructive) {
                        rec.deleteRecording(fileName: fn)
                        fileName = nil
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: AppTouchTarget.buttonHeight, height: AppTouchTarget.buttonHeight)
                            .background(Color.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.buttonSecondary))
                    }
                    .accessibilityLabel(Text("録音を削除"))
                }
            }

            // 録音中の音量メータ
            if rec.isRecording {
                ProgressView(value: Double(rec.currentLevel))
                    .tint(Color.brandAccent)
                Text("録音中… 言葉を声に出してみてください")
                    .appFont(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            if let error {
                Text(error)
                    .appFont(.caption)
                    .foregroundStyle(Color.semanticError)
            }
        }
        .padding(AppSpacing.sm)
        .background(Color.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
    }

    private func startRecording() async {
        let fn = fileName ?? RecordingService.newFileName(for: affirmationId)
        do {
            try await rec.startRecording(fileName: fn)
            fileName = fn
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func play(fileName fn: String) {
        if rec.isPlaying { rec.stopPlaying(); return }
        do {
            try rec.play(fileName: fn) { _ in }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
