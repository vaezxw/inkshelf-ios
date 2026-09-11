import SwiftUI

struct RootTabView: View {
    var body: some View {
        if #available(iOS 26, *) {
            modernTabs
        } else {
            legacyTabs
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
