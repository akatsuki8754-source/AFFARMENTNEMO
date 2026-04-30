//
//  LanguageCatalog.swift
//  App-wide language and timeline-room options.
//

import Foundation

struct LanguageOption: Identifiable, Hashable {
    let code: String
    let timelineRoom: String
    let label: String
    let flag: String

    var id: String { code }
}

enum LanguageCatalog {
    static let appLanguages: [LanguageOption] = [
        LanguageOption(code: "ja", timelineRoom: "ja_JP", label: "日本語", flag: "JP"),
        LanguageOption(code: "en", timelineRoom: "en", label: "English", flag: "US"),
        LanguageOption(code: "zh-Hans", timelineRoom: "zh_CN", label: "中文(简体)", flag: "CN"),
        LanguageOption(code: "zh-Hant", timelineRoom: "zh_TW", label: "中文(繁體)", flag: "TW"),
        LanguageOption(code: "ko", timelineRoom: "ko_KR", label: "한국어", flag: "KR"),
        LanguageOption(code: "es", timelineRoom: "es", label: "Español", flag: "ES"),
        LanguageOption(code: "fr", timelineRoom: "fr", label: "Français", flag: "FR"),
        LanguageOption(code: "de", timelineRoom: "de", label: "Deutsch", flag: "DE"),
        LanguageOption(code: "pt-BR", timelineRoom: "pt_BR", label: "Português", flag: "BR"),
        LanguageOption(code: "id", timelineRoom: "id", label: "Bahasa Indonesia", flag: "ID"),
        LanguageOption(code: "vi", timelineRoom: "vi", label: "Tiếng Việt", flag: "VN"),
        LanguageOption(code: "th", timelineRoom: "th", label: "ไทย", flag: "TH"),
        LanguageOption(code: "hi", timelineRoom: "hi", label: "हिन्दी", flag: "IN"),
        LanguageOption(code: "ar", timelineRoom: "ar", label: "العربية", flag: "SA"),
    ]

    static var timelineRooms: [LanguageOption] { appLanguages }

    static func appLanguageLabel(for code: String) -> String {
        if code == "system" { return "システム言語に従う" }
        return appLanguages.first { $0.code == code }?.label ?? code
    }

    static func timelineRoomLabel(for room: String) -> String {
        timelineRooms.first { $0.timelineRoom == room }?.label ?? room
    }

    static func timelineRoomFlag(for room: String) -> String {
        timelineRooms.first { $0.timelineRoom == room }?.flag ?? "GLOBAL"
    }

    static func defaultTimelineRoom(for locale: Locale = .current) -> String {
        let languageCode = locale.language.languageCode?.identifier ?? "en"
        let region = locale.language.region?.identifier ?? ""

        if languageCode == "zh" {
            return (region == "TW" || region == "HK" || region == "MO") ? "zh_TW" : "zh_CN"
        }
        if languageCode == "pt" && region == "BR" { return "pt_BR" }
        if let match = appLanguages.first(where: { $0.code == languageCode }) {
            return match.timelineRoom
        }
        return "en"
    }

    static func effectiveAppLocaleIdentifier(userDefaultValue: String,
                                             systemLocale: Locale = .current) -> String {
        if userDefaultValue == "system" { return systemLocale.identifier }
        return userDefaultValue
    }
}
