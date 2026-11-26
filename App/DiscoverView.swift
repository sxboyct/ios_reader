import SwiftUI
import TVCore

struct DiscoverView: View {
    @Environment(ReaderLibrary.self) private var library
    var body: some View {
        List {
            ForEach(library.sources.filter { $0.explorable && NovelSources.shared.isEnabled($0) }) { source in
                NavigationLink { SourceDiscoverView(source: source) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(source.name, systemImage: "sparkles")
                        Text(source.group).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
            }
        }
        .overlay {
            if !library.sources.contains(where: { $0.explorable && NovelSources.shared.isEnabled($0) }) {
                ContentUnavailableView("暂无发现书源", systemImage: "safari",
                    description: Text("在书源中导入并启用支持发现的 JSON 书源。"))
            }
        }
        .navigationTitle("发现")
    }
}

struct SourceDiscoverView: View {
    let source: NovelSource
    @State private var kinds: [NovelExploreKind] = []
    @State private var loading = false
    @State private var error: String?
    @State private var settings = false
    @State private var loadID = UUID()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if source.signsIn { Button { settings = true } label: {
                    Label("登录与书源设置", systemImage: "person.crop.circle")
                        .frame(maxWidth: .infinity).padding()
                        .background(.background, in: RoundedRectangle(cornerRadius: 20))
                } }
                if loading { ProgressView("正在加载发现…").frame(maxWidth: .infinity) }
                if let error { Text(error).foregroundStyle(.secondary); Button("重试") { Task { await load() } } }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Array(kinds.enumerated()), id: \.offset) { _, kind in
                        if kind.url.isEmpty {
                            Text(kind.title).font(.headline).frame(maxWidth: .infinity).padding()
                        } else {
                            NavigationLink { DiscoverBooksView(source: source, kind: kind) } label: {
                                Text(kind.title).frame(maxWidth: .infinity, minHeight: 48).padding(10)
                                    .background(.background, in: RoundedRectangle(cornerRadius: 18))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if !loading && error == nil && kinds.isEmpty { Text("此书源暂无发现分类，可在书源设置中选择线路后刷新。") }
            }.padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(source.name).navigationBarTitleDisplayMode(.inline)
        .toolbar { Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }.disabled(loading) }
        .task { await load() }.refreshable { await load() }
        .sheet(isPresented: $settings, onDismiss: { Task { await load(force: true) } }) {
            SourceSignInView(source: source)
        }
    }
    private func load(force: Bool = false) async {
        guard !loading || force else { return }
        let request = UUID(); loadID = request
        loading = true; error = nil; kinds = []
        defer { if loadID == request { loading = false } }
        do {
            let found = try await NovelRuntime.shared.exploreKinds(source)
            if loadID == request { kinds = found }
        } catch { if loadID == request { self.error = error.localizedDescription } }
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
            ForEach(books) { book in
                NavigationLink { BookDetailView(book: book) } label: { BookRow(book: book) }
            }
            if let error { Text(error); Button("重试") { Task { await load() } } }
            if loading { ProgressView("正在加载…") }
            else if !ended && error == nil { Button("加载更多") { Task { await load() } } }
            if ended && books.isEmpty { Text("暂无书籍") }
        }
        .navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
        .task { if books.isEmpty { await load() } }
    }
    private func load() async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let found = try await NovelRuntime.shared.explore(source, url: kind.url, page: nextPage)
            var seen = Set(books.map(\.id))
            let additions = found.filter { seen.insert($0.id).inserted }
            books.append(contentsOf: additions); nextPage += 1; ended = additions.isEmpty
        } catch { self.error = error.localizedDescription }
    }
}

struct SourceSignInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let source: NovelSource
    @State private var form: NovelSignInForm?
    @State private var values: [String: String] = [:]
    @State private var busy = false
    @State private var message: String?
    @State private var pendingAction: NovelSignInForm.Field?
    @State private var browser: SourceBrowserPage?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if busy { ProgressView() }
                    if let message { Text(message).font(.footnote).textSelection(.enabled) }
                    if let form {
                        ForEach(Array(layoutRows(form.rows).enumerated()), id: \.offset) { _, fields in
                            HStack(spacing: 14) {
                                ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                                    fieldView(field).frame(maxWidth: .infinity, minHeight: 42).padding(12)
                                    .background(.background, in: RoundedRectangle(cornerRadius: 20))
                                }
                            }
                        }
                        if let web = form.web, let url = webURL(web) { Button("打开登录页") { browser = SourceBrowserPage(url: url) } }
                    }
                    if form == nil && !busy { Button("重新加载") { Task { await load() } } }
                }.padding().disabled(busy)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("登录与设置").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("登录") { Task { await run(nil) } }.disabled(busy || form == nil || form?.rows.isEmpty == true) }
            }
            .task { await load() }
            .confirmationDialog(pendingAction?.name ?? "书源操作", isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } })) {
                Button("确认清理", role: .destructive) { if let action = pendingAction?.action { Task { await run(action) } }; pendingAction = nil }
            }
            .sheet(item: $browser, onDismiss: { Task { await load() } }) { page in
                SourceBrowserView(source: source, page: page)
            }
        }
    }
    private func layoutRows(_ fields: [NovelSignInForm.Field]) -> [[NovelSignInForm.Field]] {
        var rows: [[NovelSignInForm.Field]] = []
        for field in fields {
            let compact = field.type == "button" && !field.wide && !dynamicTypeSize.isAccessibilitySize
            if compact, let previous = rows.last, previous.count == 1,
               previous[0].type == "button", !previous[0].wide {
                rows[rows.count - 1].append(field)
            } else { rows.append([field]) }
        }
        return rows
    }
    @ViewBuilder private func fieldView(_ field: NovelSignInForm.Field) -> some View {
        let binding = Binding(get: { values[field.name] ?? "" }, set: { values[field.name] = $0 })
        switch field.type {
        case "button":
            if let action = field.action {
                Button(field.name) {
                    if field.name.contains("清空") || field.name.contains("清理设备") { pendingAction = field }
                    else { Task { await run(action) } }
                }.frame(maxWidth: .infinity, minHeight: 42)
            } else { Text(field.name).font(.footnote).foregroundStyle(.secondary) }
        case "password": SecureField(field.name, text: binding)
        case "select", "toggle":
            Picker(field.name.replacingOccurrences(of: "（文字阅读）", with: ""), selection: binding) {
                ForEach(field.chars, id: \.self) { Text($0).tag($0) }
            }
                .onChange(of: values[field.name]) { _, _ in
                    if field.type == "toggle", !busy, let action = field.action { Task { await run(action) } }
                }
        case "label": Text(field.name)
        default: TextField(field.name, text: binding).textInputAutocapitalization(.never).autocorrectionDisabled()
        }
    }
    private func webURL(_ value: String) -> URL? {
        guard let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
    private func load() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do { let loaded = try await NovelRuntime.shared.signInForm(source); form = loaded; values = loaded.values }
        catch { message = error.localizedDescription }
    }
    private func run(_ action: String?) async {
        guard !busy else { return }
        busy = true; message = nil; defer { busy = false }
        do {
            let outcome: NovelSignInOutcome
            if let action { outcome = try await NovelRuntime.shared.signInAction(source, values: values, action: action) }
            else { outcome = try await NovelRuntime.shared.signIn(source, values: values) }
            message = outcome.said.joined(separator: "\n")
            if let address = outcome.open, let url = webURL(address) { browser = SourceBrowserPage(url: url) }
            let refreshed = try await NovelRuntime.shared.signInForm(source)
            form = refreshed; values.merge(refreshed.values) { _, new in new }
            if let updated = outcome.values { values.merge(updated) { _, new in new } }
        } catch { message = error.localizedDescription }
    }
}
