//
//  MainTabView.swift
//  メインタブ: ホーム / ライブラリ / 設定
//  ※流すだけタイムラインは Phase 1.5 (Firebase) で追加予定
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("tab.home", systemImage: "house.fill")
                }

            LibraryView()
                .tabItem {
                    Label("tab.library", systemImage: "list.bullet")
                }

            SettingsContainerView()
                .tabItem {
                    Label("tab.settings", systemImage: "gearshape")
                }
        }
        .tint(Color.brandPrimary)
    }
}

private struct SettingsContainerView: View {
    var body: some View {
        SettingsView()
    }
}
