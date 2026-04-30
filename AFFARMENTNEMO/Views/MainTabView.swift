//
//  MainTabView.swift
//  4タブ構成 (MASTER仕様書 §9.2): ホーム / アファメ / 流すだけ / 設定
//

import SwiftUI

struct MainTabView: View {
    @AppStorage("kotodama.timeline.showTab") private var showTimelineTab: Bool = true
    /// デバッグ/スクショ用: 起動時の初期タブ (0=Home, 1=Library, 2=Timeline, 3=Settings)
    @AppStorage("kotodama.debug.startTab") private var startTab: Int = 0
    @State private var selection: Int = 0

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("tab.home", systemImage: "house.fill") }
                .tag(0)

            LibraryView()
                .tabItem { Label("tab.affirmations", systemImage: "text.quote") }
                .tag(1)

            if showTimelineTab {
                TimelineView()
                    .tabItem { Label("tab.timeline", systemImage: "bubble.left.and.bubble.right") }
                    .tag(2)
            }

            SettingsView()
                .tabItem { Label("tab.settings", systemImage: "gearshape") }
                .tag(3)
        }
        .tint(Color.brandPrimary)
        .onAppear {
            selection = startTab
        }
    }
}
