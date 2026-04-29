//
//  AuthService.swift
//  Firebase Anonymous Authentication
//  仕様: MASTER §24 (匿名サインイン + 後で Apple/Google 連携)
//

import Foundation

#if canImport(FirebaseAuth)
import FirebaseAuth

@MainActor
final class AuthService {
    static let shared = AuthService()
    private init() {}

    var currentUID: String? { Auth.auth().currentUser?.uid }
    var isSignedIn: Bool { Auth.auth().currentUser != nil }

    /// アプリ起動時に匿名サインインを保証する。既にサインイン済みなら何もしない。
    func signInAnonymouslyIfNeeded() async {
        if Auth.auth().currentUser != nil { return }
        do {
            let result = try await Auth.auth().signInAnonymously()
            print("[AuthService] anonymous signed in: \(result.user.uid)")
        } catch {
            print("[AuthService] anonymous sign-in failed: \(error)")
        }
    }

    func signOut() {
        try? Auth.auth().signOut()
    }
}
#else
// SDK未統合時のスタブ
@MainActor
final class AuthService {
    static let shared = AuthService()
    private init() {}
    var currentUID: String? { nil }
    var isSignedIn: Bool { false }
    func signInAnonymouslyIfNeeded() async {}
    func signOut() {}
}
#endif
