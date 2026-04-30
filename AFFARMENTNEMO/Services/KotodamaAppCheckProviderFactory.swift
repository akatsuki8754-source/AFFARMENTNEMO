//
//  KotodamaAppCheckProviderFactory.swift
//  本番ビルド用 App Check Provider Factory
//   - iOS 14+: AppAttest (Apple ハードウェア attestation)
//   - iOS 14未満: DeviceCheck フォールバック
//   - Debug ビルドでは AppCheckDebugProviderFactory を使う (これは別途 AFFARMENTNEMOApp.swift で分岐)
//

import Foundation

#if canImport(FirebaseAppCheck)
import FirebaseAppCheck
import FirebaseCore

final class KotodamaAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        if #available(iOS 14.0, *) {
            return AppAttestProvider(app: app)
        }
        return DeviceCheckProvider(app: app)
    }
}
#endif
