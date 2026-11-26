import SwiftUI
import TVCore

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
                    VStack(alignment: .leading, spacing: 5) {
                        BookRow(book: hit.book)
                        Text("\(hit.books.count) 个书源可选").font(.caption).foregroundStyle(.secondary).padding(.leading, 14)
                    }
                }.cardListRow()
            }
            if !searching && hits.isEmpty {
                ContentUnavailableView("搜索书名或作者", systemImage: "magnifyingglass", description: Text("搜索已启用的文字书源；结果取决于书源网站。"))
            }
        }
        .listStyle(.plain).appPage()
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
                VStack(alignment: .leading, spacing: 6) {
                    BookRow(book: book)
                    Text(NovelSources.shared.source(book.sourceKey)?.name ?? book.sourceKey).font(.caption)
                }
            }.cardListRow()
        }.listStyle(.plain).appPage().navigationTitle("选择书源")
    }
}

