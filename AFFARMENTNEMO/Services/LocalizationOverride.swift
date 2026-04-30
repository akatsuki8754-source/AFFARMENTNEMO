//
//  LocalizationOverride.swift
//  アプリ内で言語を切替する仕組み (システム言語 / 個別言語)
//
//  実装: Bundle subclass swizzling で localizedString を強制上書き
//  AppStorage("kotodama.appLanguage") = "system" | "ja" | "en" | "zh-Hans" | "zh-Hant" | "ko" | ...
//

import Foundation

private let kKey = "kotodama.appLanguage"

extension Bundle {
    /// 言語上書き対応した bundle を返す
    static let dynamic: Bundle = {
        object_setClass(Bundle.main, AnyLanguageBundle.self)
        return Bundle.main
    }()
}

private class AnyLanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        let pref = UserDefaults.standard.string(forKey: kKey) ?? "system"
        if pref == "system" {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
        // 該当言語の lproj が見つかれば差し替え
        guard
            let path = Bundle.main.path(forResource: pref, ofType: "lproj"),
            let langBundle = Bundle(path: path)
        else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
        return langBundle.localizedString(forKey: key, value: value, table: tableName)
    }
}

enum LocalizationOverride {
    /// 起動時に呼ぶことで Bundle.main を AnyLanguageBundle にすり替える
    static func install() {
        _ = Bundle.dynamic
    }

    static var current: String {
        UserDefaults.standard.string(forKey: kKey) ?? "system"
    }

    static func set(_ code: String) {
        UserDefaults.standard.set(code, forKey: kKey)
    }
}
