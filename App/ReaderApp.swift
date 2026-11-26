import SwiftUI
import TVCore

@main
struct ReaderApp: App {
    @State private var library = ReaderLibrary()
    @State private var selectedTab = 0
    @State private var importMessage: String?
    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                NavigationStack { ShelfView() }.tabItem { Label("书架", systemImage: "books.vertical") }.tag(0)
                NavigationStack { SearchView() }.tabItem { Label("找书", systemImage: "magnifyingglass") }.tag(1)
                NavigationStack { DiscoverView() }.tabItem { Label("发现", systemImage: "safari") }.tag(3)
                NavigationStack { SourcesView() }.tabItem { Label("书源", systemImage: "list.bullet.rectangle") }.tag(2)
            }
            .environment(library)
            .tint(AppPalette.accent)
            .toolbarBackground(.regularMaterial, for: .tabBar)
            .task { await NovelSources.shared.loaded(); library.reloadSources() }
            .onReceive(NotificationCenter.default.publisher(for: NovelSources.changedNotification)) { _ in library.reloadSources() }
            .onOpenURL { url in
                guard url.isFileURL else { return }
                Task {
                    do {
                        let data = try await Task.detached(priority: .userInitiated) {
                            try ImportedFile.read(url, extensions: ["json", "xbs"], limit: HTTPClient.subscriptionLimit)
                        }.value
                        let identity = URL(fileURLWithPath: "/ImportedSources/" + url.lastPathComponent)
                        let list = try NovelSources.shared.add(identity, data: data, name: url.deletingPathExtension().lastPathComponent)
                        library.reloadSources(); selectedTab = 2
                        importMessage = "已导入 \(list.count) 个文字书源"
                    } catch { importMessage = error.localizedDescription }
                }
            }
            .alert("书源导入", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
                Button("确定") { importMessage = nil }
            } message: { Text(importMessage ?? "") }
        }
    }
}

