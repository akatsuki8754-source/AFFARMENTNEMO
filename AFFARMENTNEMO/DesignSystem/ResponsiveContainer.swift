//
//  ResponsiveContainer.swift
//  iPad で内容が間延びしないよう最大幅を制限する ViewModifier
//  仕様: iPad 対応 (横幅広いと UI が左寄せ/間延びするのを防止)
//

import SwiftUI

extension View {
    /// iPad で中央寄せ + 最大幅制限。iPhone では maxWidth 以下なので影響なし。
    func responsivePage(maxWidth: CGFloat = 560) -> some View {
        self
            .frame(maxWidth: maxWidth, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    /// セルやリストアイテム用 (より広め)
    func responsiveCard(maxWidth: CGFloat = 720) -> some View {
        self
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}
