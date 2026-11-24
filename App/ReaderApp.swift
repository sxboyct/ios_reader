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
                NavigationStack { SourcesView() }.tabItem { Label("书源", systemImage: "list.bullet.rectangle") }.tag(2)
            }
            .environment(library)
            .tint(Color(red: 0.27, green: 0.43, blue: 0.35))
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

@MainActor @Observable
final class ReaderLibrary {
    var shelf = NovelLibrary.load("shelf.json", as: [NovelLibrary.ShelfBook].self) ?? []
    var searchHistory = ReaderSearchHistory(NovelLibrary.load("search-history.json", as: [String].self) ?? [])
    var sources: [NovelSource] = []
    var lists: [NovelSourceList] = []
    func reloadSources() { sources = NovelSources.shared.all; lists = NovelSources.shared.lists }
    func entry(_ book: NovelBook) -> NovelLibrary.ShelfBook? { shelf.first { $0.id == book.match } }
    func save(_ entry: NovelLibrary.ShelfBook) {
        shelf.removeAll { $0.id == entry.id }; shelf.insert(entry, at: 0)
        NovelLibrary.save(shelf, as: "shelf.json")
    }
    func remove(_ book: NovelBook) {
        shelf.removeAll { $0.id == book.match }; NovelLibrary.save(shelf, as: "shelf.json")
    }
    func recordSearch(_ keyword: String) {
        searchHistory.record(keyword)
        NovelLibrary.save(searchHistory.entries, as: "search-history.json")
    }
    func removeSearch(_ keyword: String) {
        searchHistory.remove(keyword)
        NovelLibrary.save(searchHistory.entries, as: "search-history.json")
    }
    func clearSearchHistory() {
        searchHistory.clear()
        NovelLibrary.save(searchHistory.entries, as: "search-history.json")
    }
}

struct BookRow: View {
    let book: NovelBook
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "text.book.closed.fill").font(.title).foregroundStyle(.tint)
                .frame(width: 48, height: 64).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 6) {
                Text(book.name).font(.headline)
                Text(book.author.isEmpty ? "佚名" : book.author).font(.subheadline).foregroundStyle(.secondary)
                if !book.lastChapter.isEmpty { Text(book.lastChapter).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
        }.padding(.vertical, 4)
    }
}

struct ShelfView: View {
    @Environment(ReaderLibrary.self) private var library
    var body: some View {
        List {
            if library.shelf.isEmpty {
                ContentUnavailableView("书架还是空的", systemImage: "books.vertical", description: Text("先在「书源」导入 Legado JSON 书源，再到「找书」搜索。"))
            }
            ForEach(library.shelf) { entry in
                NavigationLink { BookDetailView(book: entry.book) } label: {
                    VStack(alignment: .leading) {
                        BookRow(book: entry.book)
                        if entry.started { Text("读到：" + entry.chapterTitle).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .swipeActions { Button("移出书架", role: .destructive) { library.remove(entry.book) } }
            }
        }.navigationTitle("映夏阅读")
    }
}

struct SearchView: View {
    @Environment(ReaderLibrary.self) private var library
    @State private var query = ""
    @State private var hits: [NovelSearchHit] = []
    @State private var searching = false
    @State private var searchID = UUID()
    @State private var requested = ""
    @State private var status = ""
    @State private var confirmingClear = false
    var body: some View {
        List {
            if !searching && (query.isEmpty || requested.isEmpty) && !library.searchHistory.entries.isEmpty {
                Section {
                    ForEach(library.searchHistory.entries, id: \.self) { keyword in
                        Button { submit(keyword) } label: {
                            Label(keyword, systemImage: "clock.arrow.circlepath")
                                .foregroundStyle(.primary)
                        }
                        .swipeActions {
                            Button("删除", role: .destructive) { library.removeSearch(keyword) }
                        }
                    }
                } header: {
                    HStack {
                        Text("搜索历史")
                        Spacer()
                        Button("清空") { confirmingClear = true }
                    }
                }
            }
            if searching { ProgressView("正在搜索…") }
            if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
            ForEach(hits) { hit in
                NavigationLink { SearchCopiesView(hit: hit) } label: {
                    VStack(alignment: .leading) { BookRow(book: hit.book); Text("\(hit.books.count) 个书源").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if !searching && hits.isEmpty {
                ContentUnavailableView("搜索书名或作者", systemImage: "magnifyingglass", description: Text("搜索已启用的文字书源；结果取决于书源网站。"))
            }
        }
        .navigationTitle("找书")
        .searchable(text: $query, prompt: "书名、作者")
        .onSubmit(of: .search) { submit(query) }
        .confirmationDialog("清空全部搜索历史？", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("清空历史", role: .destructive) { library.clearSearchHistory() }
        }
        .task(id: searchID) {
            guard !requested.isEmpty else { searching = false; return }
            hits = []; searching = true; status = ""
            let keyword = requested
            let sources = NovelSources.shared.enabled.filter(\.searchable)
            var done = 0, failed = 0
            for await (_, result) in NovelBooks.search(keyword, in: sources, concurrency: 4) {
                guard !Task.isCancelled else { return }
                done += 1
                switch result {
                case .success(let books): NovelBooks.merge(books, into: &hits, keyword: keyword)
                case .failure: failed += 1
                }
                status = "已搜索 \(done)/\(sources.count) 个书源，\(failed) 个未响应"
            }
            guard !Task.isCancelled else { return }
            searching = false
            if sources.isEmpty { status = "请先导入并启用可搜索的文字书源。" }
        }
    }
    private func submit(_ keyword: String) {
        let cleaned = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        query = cleaned; requested = cleaned
        library.recordSearch(cleaned); searchID = UUID()
    }
}

struct SearchCopiesView: View {
    let hit: NovelSearchHit
    var body: some View {
        List(hit.books) { book in
            NavigationLink { BookDetailView(book: book) } label: {
                VStack(alignment: .leading) {
                    BookRow(book: book)
                    Text(NovelSources.shared.source(book.sourceKey)?.name ?? book.sourceKey).font(.caption)
                }
            }
        }.navigationTitle("选择书源")
    }
}

struct BookDetailView: View {
    @Environment(ReaderLibrary.self) private var library
    @State var book: NovelBook
    @State private var chapters: [NovelChapter] = []
    @State private var error: String?
    @State private var loading = true
    @State private var reading: ReadingStart?
    private struct ReadingStart: Identifiable {
        let id = UUID()
        let index: Int
        var position: Double = 0
        var offset: Int? = nil
    }
    var body: some View {
        List {
            Section {
                BookRow(book: book)
                if !book.intro.isEmpty { Text(book.intro).font(.subheadline) }
                Button(library.entry(book) == nil ? "加入书架" : "已在书架") {
                    if library.entry(book) == nil { library.save(NovelLibrary.ShelfBook(book: book)) }
                }.disabled(library.entry(book) != nil)
                if let index = NovelChapterMatch.index(title: library.entry(book)?.chapterTitle ?? "", index: library.entry(book)?.chapterIndex ?? 0, in: chapters) {
                    Button("继续阅读") {
                        reading = ReadingStart(index: index, position: library.entry(book)?.position ?? 0, offset: library.entry(book)?.characterOffset)
                    }
                }
            }
            if loading { ProgressView("正在加载目录…") }
            if let error { Section { Text(error); Button("重试") { Task { await load() } } } }
            Section("目录 · \(chapters.count)") {
                ForEach(chapters) { chapter in
                    if chapter.isVolume { Text(chapter.title).font(.headline) }
                    else { Button(chapter.title) { reading = ReadingStart(index: chapter.index) } }
                }
            }
        }.navigationTitle(book.name).navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load(refresh: true) }
        .fullScreenCover(item: $reading) { start in
            ReaderView(book: book, chapters: chapters, start: start.index, position: start.position, characterOffset: start.offset)
                .environment(library)
        }
    }
    private func load(refresh: Bool = false) async {
        loading = true; error = nil
        do {
            // Cached chapters remain readable when the website is offline.
            chapters = try await NovelBooks.shared.chapters(book, refresh: refresh)
            loading = false
            if let details = try? await NovelBooks.shared.details(book) { book = details }
        } catch { self.error = error.localizedDescription }
        loading = false
    }
}
