//
//  AppTheme.swift
//  デザイントークン (色・タイポ・スペーシング)
//  仕様: design_and_qa_spec.md §1
//

import SwiftUI

// MARK: - Color Tokens
// Asset Catalog (Assets.xcassets) で定義したカラーは
// ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS=YES により
// Color.brandPrimary / Color.semanticError などとして自動生成される。
// 詳細は Assets.xcassets/*.colorset/Contents.json 参照。

// MARK: - Typography Tokens
// Dynamic Type 対応 (xSmall〜accessibility5 で破綻しない)

enum AppFont {
    // 仕様 §1.3: pt + weight + line height
    case display      // 32 Bold
    case h1           // 24 Semibold
    case h2           // 20 Semibold
    case h3           // 17 Semibold
    case body         // 15 Regular
    case bodyEmphasis // 15 Semibold
    case caption      // 13 Regular
    case micro        // 11 Medium

    var size: CGFloat {
        switch self {
        case .display: 32
        case .h1: 24
        case .h2: 20
        case .h3: 17
        case .body, .bodyEmphasis: 15
        case .caption: 13
        case .micro: 11
        }
    }

    var weight: Font.Weight {
        switch self {
        case .display: .bold
        case .h1, .h2, .h3, .bodyEmphasis: .semibold
        case .body, .caption: .regular
        case .micro: .medium
        }
    }

    var relativeTo: Font.TextStyle {
        switch self {
        case .display: .largeTitle
        case .h1: .title
        case .h2: .title2
        case .h3: .headline
        case .body, .bodyEmphasis: .body
        case .caption: .caption
        case .micro: .caption2
        }
    }

    var swiftUIFont: Font {
        .system(size: size, weight: weight, design: .default)
    }
}

extension AppFont {
    /// 日本語可読性のための line spacing (Ling & van Schaik 2007 / Hayataki 2020 — CJK は英文比 +0.1em 推奨)
    /// SwiftUI の lineSpacing は 行間の "追加余白" のため、目標行高 1.65-1.7 を達成するための値
    var lineSpacing: CGFloat {
        switch self {
        case .display: 6
        case .h1: 5
        case .h2: 4
        case .h3: 3
        case .body, .bodyEmphasis: 5   // 17pt 文字 + 5pt → 行高 ~1.65
        case .caption: 3
        case .micro: 2
        }
    }

    /// 日本語の "詰まり感" を防ぐ字間 (kerning) — タイトル系のみ若干広め
    var tracking: CGFloat {
        switch self {
        case .display, .h1: 0.4
        case .h2, .h3: 0.3
        default: 0.0
        }
    }
}

extension View {
    /// Dynamic Type 対応 + 日本語可読性最適化された行間/字間
    func appFont(_ token: AppFont) -> some View {
        self
            .font(.system(token.relativeTo, weight: token.weight))
            .lineSpacing(token.lineSpacing)
            .tracking(token.tracking)
    }
}

// MARK: - Spacing Tokens (8pt grid)

enum AppSpacing {
    static let xs: CGFloat  = 4
    static let sm: CGFloat  = 8
    static let md: CGFloat  = 16
    static let lg: CGFloat  = 24
    static let xl: CGFloat  = 32
    static let xxl: CGFloat = 48
    /// 画面端マージン (仕様 §1.4)
    static let screenEdge: CGFloat = 20
}

// MARK: - Radius

enum AppRadius {
    static let button: CGFloat        = 12
    static let buttonSecondary: CGFloat = 8
    static let card: CGFloat          = 16
}

// MARK: - Shadow

extension View {
    /// 仕様 §1.5: y=2, blur=8, opacity=0.08
    func appCardShadow() -> some View {
        self.shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Min Touch Target

enum AppTouchTarget {
    /// 仕様 §1.5 / §2.9: 最小タップ領域 44pt
    static let minimum: CGFloat = 44
    /// ボタンの最小高さ (タップ + 視認性): 48pt
    static let buttonHeight: CGFloat = 48
}
