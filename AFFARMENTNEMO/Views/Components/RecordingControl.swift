//
//  RecordingControl.swift
//  Add/Edit 共通の「自分の声を録音/再生/削除」コンポーネント
//  ユーザー要望: 録音後に再生マーク・削除マーク・録音時間を明確に表示
//

import SwiftUI

struct RecordingControl: View {
    @Binding var fileName: String?
    let affirmationId: UUID

    @StateObject private var rec = RecordingService.shared
    @State private var error: String?
    @State private var savedDuration: TimeInterval = 0

    private var hasRecording: Bool {
        rec.hasRecording(fileName: fileName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // ヘッダー: タイトル + 状態バッジ
            HStack {
                Image(systemName: "mic.fill").foregroundStyle(Color.brandPrimary)
                Text("自分の声で録音 (任意)")
                    .appFont(.bodyEmphasis)
                Spacer()
                if hasRecording {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Color.semanticSuccess)
                        Text("\(formatDuration(savedDuration))")
                            .appFont(.caption)
                            .foregroundStyle(Color.semanticSuccess)
                    }
                }
            }

            // 録音中: 経過時間 + 音量メータ
            if rec.isRecording {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle()
                            .fill(Color.semanticError)
                            .frame(width: 10, height: 10)
                            .opacity(0.6 + Double(rec.currentLevel) * 0.4)
                        Text("録音中… \(formatDuration(rec.recordingElapsed))")
                            .appFont(.caption)
                            .foregroundStyle(Color.semanticError)
                    }
                    ProgressView(value: Double(rec.currentLevel))
                        .tint(Color.semanticError)
                }
            }

            // 再生中: 進捗バー
            if rec.isPlaying {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(Color.brandPrimary)
                        Text("再生中…")
                            .appFont(.caption)
                            .foregroundStyle(Color.brandPrimary)
                    }
                    ProgressView(value: rec.playbackProgress)
                        .tint(Color.brandPrimary)
                }
            }

            // ボタン群
            HStack(spacing: AppSpacing.sm) {
                if !hasRecording && !rec.isRecording {
                    // 初回録音
                    Button {
                        Task { await startRecording() }
                    } label: {
                        Label("録音する", systemImage: "record.circle.fill")
                            .appFont(.bodyEmphasis)
                            .foregroundStyle(Color.bgPrimary)
                            .frame(maxWidth: .infinity, minHeight: AppTouchTarget.buttonHeight)
                            .background(Color.brandPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.buttonSecondary))
                    }
                    .buttonStyle(.plain)
                } else if rec.isRecording {
                    // 録音停止
                    Button {
                        rec.stopRecording()
                        if let fn = fileName {
                            savedDuration = rec.duration(of: fn)
                        }
                    } label: {
                        Label("録音を保存", systemImage: "stop.circle.fill")
                            .appFont(.bodyEmphasis)
                            .foregroundStyle(Color.bgPrimary)
                            .frame(maxWidth: .infinity, minHeight: AppTouchTarget.buttonHeight)
                            .background(Color.semanticError)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.buttonSecondary))
                    }
                    .buttonStyle(.plain)
                } else {
                    // 再生 / 録音し直す / 削除
                    Button {
                        play()
                    } label: {
                        Label(rec.isPlaying ? "停止" : "再生",
                              systemImage: rec.isPlaying ? "stop.fill" : "play.fill")
                            .appFont(.bodyEmphasis)
                            .foregroundStyle(Color.brandPrimary)
                            .frame(maxWidth: .infinity, minHeight: AppTouchTarget.buttonHeight)
                            .background(Color.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.buttonSecondary))
                    }
                    .buttonStyle(.plain)
                    Button {
                        Task { await startRecording() }
                    } label: {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.brandSecondary)
                            .frame(width: AppTouchTarget.buttonHeight, height: AppTouchTarget.buttonHeight)
                            .background(Color.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.buttonSecondary))
                    }
                    .accessibilityLabel(Text("録音し直す"))
                    .buttonStyle(.plain)
                    Button(role: .destructive) {
                        if let fn = fileName {
                            rec.stopPlaying()
                            rec.deleteRecording(fileName: fn)
                            fileName = nil
                            savedDuration = 0
                        }
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.semanticError)
                            .frame(width: AppTouchTarget.buttonHeight, height: AppTouchTarget.buttonHeight)
                            .background(Color.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.buttonSecondary))
                    }
                    .accessibilityLabel(Text("録音を削除"))
                    .buttonStyle(.plain)
                }
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
        .contentShape(Rectangle())
        .onAppear {
            if let fn = fileName, rec.hasRecording(fileName: fn) {
                savedDuration = rec.duration(of: fn)
            }
        }
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

    private func play() {
        if rec.isPlaying { rec.stopPlaying(); return }
        guard let fn = fileName else { return }
        do {
            try rec.play(fileName: fn) { _ in }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func formatDuration(_ secs: TimeInterval) -> String {
        let total = Int(secs.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
