//
//  MainTabView.swift
//  4タブ構成 (MASTER仕様書 §9.2): ホーム / アファメ / 流すだけ / 設定
//

import SwiftUI

struct MainTabView: View {
    @AppStorage("kotodama.timeline.showTab") private var showTimelineTab: Bool = true

    var body: some View {
        TabView {
            // ホーム
            HomeView()
                .tabItem {
                    Label("tab.home", systemImage: "house.fill")
                }

            // 自分の言葉
            LibraryView()
                .tabItem {
                    Label("tab.affirmations", systemImage: "text.quote")
                }

            // みんなの願い (星モチーフは反応のみ、タブは言葉系で統一)
            if showTimelineTab {
                TimelineView()
                    .tabItem {
                        Label("tab.timeline", systemImage: "bubble.left.and.bubble.right")
                    }
            }

            SettingsView()
                .tabItem {
                    Label("tab.settings", systemImage: "gearshape")
                }
        }
        .tint(Color.brandPrimary)
    }
}
