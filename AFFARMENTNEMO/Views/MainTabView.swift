//
//  MainTabView.swift
//  4タブ構成 (MASTER仕様書 §9.2): ホーム / アファメ / 流すだけ / 設定
//

import SwiftUI

struct MainTabView: View {
    @AppStorage("kotodama.timeline.showTab") private var showTimelineTab: Bool = true

    var body: some View {
        TabView {
            // Wish Tree v2: 笹/木モチーフ
            HomeView()
                .tabItem {
                    Label("tab.home", systemImage: "leaf.fill")
                }

            // 自分の短冊一覧
            LibraryView()
                .tabItem {
                    Label("tab.affirmations", systemImage: "star.bubble")
                }

            // みんなの願い (夜空 / star)
            if showTimelineTab {
                TimelineView()
                    .tabItem {
                        Label("tab.timeline", systemImage: "sparkles")
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
