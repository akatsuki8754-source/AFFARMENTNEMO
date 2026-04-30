//
//  RecordingService.swift
//  自分の声録音 → 再生 (ユーザー要望: 録音/AI/自分で読む の3モード)
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class RecordingService: NSObject, ObservableObject {
    static let shared = RecordingService()

    @Published var isRecording: Bool = false
    @Published var isPlaying: Bool = false
    @Published var currentLevel: Float = 0  // 録音中の音量メータ (0-1)
    @Published var recordingElapsed: TimeInterval = 0  // 録音中の経過秒数
    @Published var playbackProgress: Double = 0       // 再生中の進捗 (0-1)

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var levelTimer: Timer?

    /// Documents/recordings/ ディレクトリ
    static var recordingsDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("recordings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func url(for fileName: String) -> URL {
        recordingsDir.appendingPathComponent(fileName)
    }

    static func newFileName(for affirmationId: UUID) -> String {
        "rec_\(affirmationId.uuidString).m4a"
    }

    // MARK: - Mic permission
    func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    // MARK: - Record
    func startRecording(fileName: String) async throws {
        if isRecording { stopRecording() }
        if isPlaying { stopPlaying() }

        let granted = await requestMicrophonePermission()
        guard granted else {
            throw NSError(domain: "RecordingService", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "マイク許可がありません"])
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: [])

        let url = Self.url(for: fileName)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.delegate = self
        recorder?.isMeteringEnabled = true
        recorder?.record()
        isRecording = true

        // 音量メータ + 経過時間更新
        recordingElapsed = 0
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.recorder?.updateMeters()
                let avg = self.recorder?.averagePower(forChannel: 0) ?? -160
                self.currentLevel = max(0, min(1, (avg + 60) / 60))
                self.recordingElapsed = self.recorder?.currentTime ?? 0
            }
        }
    }

    func stopRecording() {
        recorder?.stop()
        recorder = nil
        levelTimer?.invalidate()
        levelTimer = nil
        currentLevel = 0
        isRecording = false
    }

    // MARK: - Play
    /// 再生開始。完了時 onFinish 呼び出し (.didFinish or 中断含む)
    func play(fileName: String, onFinish: @escaping (Bool) -> Void) throws {
        if isRecording { stopRecording() }
        if isPlaying { stopPlaying() }

        let url = Self.url(for: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(domain: "RecordingService", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "録音ファイルが見つかりません"])
        }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true, options: [])

        player = try AVAudioPlayer(contentsOf: url)
        player?.delegate = PlayerDelegateBridge(onFinish: { [weak self] success in
            Task { @MainActor in
                self?.stopPlayingInternal()
                onFinish(success)
            }
        })
        player?.prepareToPlay()
        player?.play()
        isPlaying = true

        // 進捗タイマー (UI に再生中バーを出すため)
        playbackProgress = 0
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.player, p.duration > 0 else { return }
                self.playbackProgress = p.currentTime / p.duration
            }
        }
    }

    func stopPlaying() {
        player?.stop()
        stopPlayingInternal()
    }

    private func stopPlayingInternal() {
        player = nil
        isPlaying = false
        levelTimer?.invalidate()
        levelTimer = nil
        playbackProgress = 0
    }

    /// 既存ファイルの再生時間 (秒)
    func duration(of fileName: String) -> TimeInterval {
        let url = Self.url(for: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        if let p = try? AVAudioPlayer(contentsOf: url) {
            return p.duration
        }
        return 0
    }

    // MARK: - File ops
    func hasRecording(fileName: String?) -> Bool {
        guard let fileName, !fileName.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: Self.url(for: fileName).path)
    }

    func deleteRecording(fileName: String) {
        try? FileManager.default.removeItem(at: Self.url(for: fileName))
    }
}

extension RecordingService: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            self.isRecording = false
            self.levelTimer?.invalidate()
            self.levelTimer = nil
        }
    }
}

/// AVAudioPlayer.delegate を強参照保持するためのブリッジ
private final class PlayerDelegateBridge: NSObject, AVAudioPlayerDelegate {
    let onFinish: (Bool) -> Void
    init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish(flag)
    }
}
