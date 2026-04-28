//
//  SmartHintEngine.swift
//  書いた文章へのインラインヒント (UX v4 §4)
//  研究: Wood et al. 2009 (特性アファメ警告) / Gollwitzer 1999 (If-Then) / Steele 1988 (価値)
//

import Foundation

enum SmartHint: String, CaseIterable, Identifiable {
    case traitAffirmationWarning  // 特性アファメ警告
    case tooShort                  // 短すぎ
    case ifThenPraise              // If-Then 検知
    case valuePraise               // 価値アファメ 検知

    var id: String { rawValue }

    var messageKey: String {
        switch self {
        case .traitAffirmationWarning: "hint.trait"
        case .tooShort: "hint.short"
        case .ifThenPraise: "hint.ifthen"
        case .valuePraise: "hint.value"
        }
    }

    var isPositive: Bool {
        switch self {
        case .ifThenPraise, .valuePraise: true
        default: false
        }
    }
}

enum SmartHintEngine {
    /// 入力されたテキストに対する最初に該当するヒントを返す
    /// 優先度: 肯定ヒント > 警告 > 短すぎ
    static func evaluate(_ text: String) -> SmartHint? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. If-Then 肯定 (もし...したら / もし...すれば)
        if Self.containsIfThen(trimmed) {
            return .ifThenPraise
        }

        // 2. 価値アファメ 肯定 (...を大切に / ...が大切)
        if trimmed.contains("大切") {
            return .valuePraise
        }

        // 3. 特性アファメ警告 (Wood 2009)
        //    「私は最高」「私は完璧」「私は富裕層」「私は◯◯だ/である」型を緩く検出
        if Self.isTraitAffirmation(trimmed) {
            return .traitAffirmationWarning
        }

        // 4. 短すぎ (5文字以下)
        if trimmed.count <= 5 {
            return .tooShort
        }

        return nil
    }

    private static func containsIfThen(_ text: String) -> Bool {
        let pattern = "もし.*(したら|すれば|たら)"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func isTraitAffirmation(_ text: String) -> Bool {
        // 「私は」+ 断定表現 (「だ」「である」「最高」「完璧」)
        let traitPatterns = [
            "私は.*最高",
            "私は.*完璧",
            "私は.*富裕",
            "私は.*天才",
            "私は.*愛されている",
            "^私は[^。]*だ$",
            "^私は[^。]*である$",
        ]
        return traitPatterns.contains { p in
            text.range(of: p, options: .regularExpression) != nil
        }
    }
}
