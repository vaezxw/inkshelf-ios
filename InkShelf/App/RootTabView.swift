import SwiftUI

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var sync: SyncService

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                modernTabs
            } else {
                legacyTabs
            }
        }
        .task {
            sync.bind(context: context)
            guard CloudAuthStore.isLoggedIn, CloudConfig.syncEnabled else { return }
            await sync.syncNow(context: context)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            sync.bind(context: context)
            guard CloudAuthStore.isLoggedIn, CloudConfig.syncEnabled else { return }
            Task { await sync.syncNow(context: context) }
        }
    }

    @available(iOS 26, *)
    private var modernTabs: some View {
        TabView {
            Tab("书架", systemImage: "book.fill") {
                ShelfView()
            }
            Tab("书源", systemImage: "globe") {
                SourcesView()
            }
            Tab("设置", systemImage: "slider.horizontal.3") {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(InkShelfColors.lamp)
    }

    private var legacyTabs: some View {
        TabView {
            ShelfView()
                .tabItem {
                    Label("书架", systemImage: "book.fill")
                }
            SourcesView()
                .tabItem {
                    Label("书源", systemImage: "globe")
                }
            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "slider.horizontal.3")
                }
        }
        .tint(InkShelfColors.lamp)
    }
}
