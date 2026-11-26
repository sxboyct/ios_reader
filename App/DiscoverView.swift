import SwiftUI
import TVCore

struct DiscoverView: View {
    @Environment(ReaderLibrary.self) private var library
    @AppStorage("discover.source") private var selectedKey = ""
    private var sources: [NovelSource] { library.sources.filter { $0.explorable && NovelSources.shared.isEnabled($0) } }
    private var selected: NovelSource? { sources.first { $0.key == selectedKey } ?? sources.first }
    var body: some View {
        Group {
            if let selected {
                SourceDiscoverView(source: selected).id(selected.revision + selected.key)
            } else {
                ContentUnavailableView("发现下一本好书", systemImage: "safari",
                    description: Text("在书源中导入并启用支持发现的书源，分类与榜单会显示在这里。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).appPage().navigationTitle("发现")
            }
        }
        .toolbar {
            if sources.count > 1 {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(sources) { source in
                            Button { selectedKey = source.key } label: {
                                if source.key == selected?.key { Label(source.name, systemImage: "checkmark") }
                                else { Text(source.name) }
                            }
                        }
                    } label: { Image(systemName: "books.vertical") }.accessibilityLabel("切换发现书源")
                }
            }
        }
    }
}

struct SourceDiscoverView: View {
    let source: NovelSource
    @State private var model = DiscoverPageModel()
    @State private var settings = false
    @State private var categories = false
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                if model.form != nil { filters }
                if let error = model.error {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("暂时无法加载", systemImage: "wifi.exclamationmark").font(.headline)
                        Text(error).font(.caption).foregroundStyle(.secondary)
                        Button("重新加载") { Task { await model.reload(source) } }
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading).bookCard()
                }
                if model.loading { ProgressView("正在寻找好书…").frame(maxWidth: .infinity).padding(20) }
                ForEach(model.sections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(section.kind.title).font(.title3.bold()).lineLimit(2)
                            Spacer(minLength: 12)
                            NavigationLink { DiscoverBooksView(source: source, kind: section.kind) } label: {
                                HStack(spacing: 3) { Text("查看全部"); Image(systemName: "chevron.right").font(.caption) }
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }.buttonStyle(.plain)
                        }
                        if section.loading { ProgressView().frame(maxWidth: .infinity).padding(24) }
                        else if let error = section.error {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                Button("重试此书单") { Task { await model.retry(section, source: source) } }
                                    .disabled(model.loadingPreviews)
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).bookCard()
                        } else if section.books.isEmpty {
                            Text("暂无内容").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
                        }
                        ForEach(Array(section.books.enumerated()), id: \.element.id) { index, book in
                            NavigationLink { BookDetailView(book: book) } label: { BookRow(book: book, rank: index + 1) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                if model.canLoadMore {
                    Button { Task { await model.more(source) } } label: {
                        Label("更多发现", systemImage: "plus.circle").frame(maxWidth: .infinity).padding(16).bookCard()
                    }.disabled(model.loading || model.loadingPreviews)
                }
                if !model.loading && model.kinds.isEmpty && model.error == nil {
                    ContentUnavailableView("暂无分类", systemImage: "books.vertical", description: Text("可尝试在书源设置中更换线路或来源。"))
                }
            }.padding(20)
        }
        .appPage().navigationTitle(source.name).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { categories = true } label: { Image(systemName: "square.grid.2x2") }
                    .accessibilityLabel("全部分类").disabled(model.kinds.isEmpty)
                if source.signsIn {
                    Button { settings = true } label: { Image(systemName: "person.crop.circle") }.accessibilityLabel("登录与书源设置")
                }
            }
        }
        .task {
            if model.kinds.isEmpty || model.sections.contains(where: { $0.loading }) { await model.reload(source) }
        }
        .refreshable { await model.reload(source) }
        .sheet(isPresented: $settings, onDismiss: { Task { await model.reload(source) } }) { SourceSignInView(source: source) }
        .sheet(isPresented: $categories) { DiscoverCategoriesView(source: source, kinds: model.kinds) }
    }
    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(model.filterFields, id: \.name) { field in
                    Menu {
                        ForEach(field.chars, id: \.self) { choice in
                            Button {
                                Task { await model.select(field, value: choice, source: source) }
                            } label: {
                                if model.form?.values[field.name] == choice { Label(choice, systemImage: "checkmark") }
                                else { Text(choice) }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(model.filterLabel(field)).lineLimit(1)
                            Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                        }.font(.caption.weight(.medium)).foregroundStyle(.primary)
                            .padding(.horizontal, 14).padding(.vertical, 11).background(AppPalette.card, in: Capsule())
                    }.disabled(model.loading || model.saving)
                }
                if !model.filterFields.isEmpty {
                    Text("小说").font(.caption.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 11)
                        .background(AppPalette.card, in: Capsule())
                }
                if model.saving { ProgressView() }
            }
        }
    }
}

private struct DiscoverCategoriesView: View {
    @Environment(\.dismiss) private var dismiss
    let source: NovelSource
    let kinds: [NovelExploreKind]
    @State private var query = ""
    var body: some View {
        NavigationStack {
            List(kinds.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }) { kind in
                NavigationLink { DiscoverBooksView(source: source, kind: kind) } label: { Text(kind.title).padding(.vertical, 6) }
            }.appPage().navigationTitle("全部分类").searchable(text: $query, prompt: "搜索榜单或分类")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

struct DiscoverBooksView: View {
    let source: NovelSource
    let kind: NovelExploreKind
    @State private var books: [NovelBook] = []
    @State private var nextPage = 1
    @State private var loading = false
    @State private var ended = false
    @State private var error: String?
    var body: some View {
        List {
            ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                NavigationLink { BookDetailView(book: book) } label: { BookRow(book: book, rank: index + 1) }.cardListRow()
            }
            if let error { Text(error).font(.caption); Button("重试") { Task { await load() } } }
            if loading { ProgressView("正在加载…").frame(maxWidth: .infinity) }
            else if !ended && error == nil { Button("加载更多") { Task { await load() } }.frame(maxWidth: .infinity) }
            if ended { Text(books.isEmpty ? "暂无书籍" : "已经到底了").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
        }
        .listStyle(.plain).appPage().navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
        .task { if books.isEmpty { await load() } }
    }
    private func load() async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let found = try await NovelRuntime.shared.explore(source, url: kind.url, page: nextPage)
            guard !Task.isCancelled else { return }
            var seen = Set(books.map(\.id))
            let additions = found.filter { seen.insert($0.id).inserted }
            books.append(contentsOf: additions); nextPage += 1; ended = additions.isEmpty
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
