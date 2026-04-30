//
//  RoutinePlaybackRouter.swift
//  通知タップやホーム操作から読み上げ画面へ移動するための軽量ルーター
//

import Foundation
import Combine

@MainActor
final class RoutinePlaybackRouter: ObservableObject {
    static let shared = RoutinePlaybackRouter()

    @Published private(set) var requestID = UUID()
    @Published private(set) var requestedMode: ReadPlaybackMode = .ai

    private init() {}

    func requestPlayback(mode: ReadPlaybackMode = .ai) {
        requestedMode = mode
        requestID = UUID()
    }
}
