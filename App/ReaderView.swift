import SwiftUI
import TVCore

struct ReaderView: View {
    @Environment(ReaderLibrary.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    let book: NovelBook
    let chapters: [NovelChapter]
    @State private var index: Int
    @State private var paragraph: Int?
    @State private var resumePosition: Double
    @State private var content: NovelContent?
    @State private var failure: String?
    @State private var settings = false
    @State private var contents = false
    @State private var bookmarks = false
    @State private var revision = UUID()
    @State private var fonts = ReaderFonts.shared
    @AppStorage("reader.fontName") private var fontName = ""
    @AppStorage("reader.fontSize") private var fontSize = 20.0
    @AppStorage("reader.lineSpacing") private var lineSpacing = 10.0
    @AppStorage("reader.theme") private var theme = "自动"
    @AppStorage("reader.script") private var script = ""
    init(book: NovelBook, chapters: [NovelChapter], start: Int, position: Double = 0) {
        self.book = book; self.chapters = chapters
        _index = State(initialValue: start); _resumePosition = State(initialValue: position)
    }
    private var dark: Bool { theme == "夜间" || (theme == "自动" && colorScheme == .dark) }
    private var background: Color { dark ? Color(white: 0.1) : theme == "纸张" ? Color(red: 0.95, green: 0.91, blue: 0.81) : Color(white: 0.99) }
    private var transformed: NovelContent? { content.map { (NovelScript(rawValue: script) ?? .original).convert($0) } }
    private var position: Double { Double(paragraph ?? 0) / Double(max(1, (content?.paragraphs.count ?? 1) - 1)) }
    var body: some View {
        VStack(spacing: 0) {
            if let text = transformed {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: fontSize * 0.7) {
                        Text(text.title).font(fonts.font(fontName, size: fontSize * 1.2)).padding(.vertical, 20)
                        ForEach(Array(text.paragraphs.enumerated()), id: \.offset) { offset, line in
                            Text("　　" + line.trimmingCharacters(in: .whitespacesAndNewlines))
                                .font(fonts.font(fontName, size: fontSize)).lineSpacing(lineSpacing)
                                .frame(maxWidth: .infinity, alignment: .leading).id(offset)
                        }
                    }.scrollTargetLayout().padding(.horizontal, 24).padding(.bottom, 32)
                }.scrollPosition(id: $paragraph, anchor: .top)
                .onChange(of: paragraph) { _, _ in record() }
                .onAppear {
                    paragraph = Int(resumePosition * Double(max(0, text.paragraphs.count - 1)))
                }
            } else if let failure {
                ContentUnavailableView {
                    Label("章节加载失败", systemImage: "wifi.exclamationmark")
                } description: { Text(failure) } actions: {
                    Button("重试") { revision = UUID() }
                }.frame(maxHeight: .infinity)
            } else { ProgressView("正在加载章节…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            Divider()
            HStack {
                Button { move(-1) } label: { Image(systemName: "chevron.left") }.disabled(neighbor(-1) == nil)
                Spacer()
                Text("\(index + 1)/\(chapters.count) · \(Int(position * 100))%").font(.caption).monospacedDigit()
                Spacer()
                Button { move(1) } label: { Image(systemName: "chevron.right") }.disabled(neighbor(1) == nil)
            }.padding()
        }
        .foregroundStyle(dark ? Color(white: 0.87) : Color(white: 0.16)).background(background)
        .navigationTitle(book.name).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { contents = true } label: { Image(systemName: "list.bullet") }.accessibilityLabel("目录")
                Menu {
                    Button("添加书签", systemImage: "bookmark") { addBookmark() }.disabled(content == nil)
                    Button("查看书签", systemImage: "bookmark.fill") { bookmarks = true }
                    Button("阅读设置", systemImage: "textformat.size") { settings = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .task(id: "\(index)-\(revision)") { await load() }
        .onDisappear { record() }
        .onChange(of: scenePhase) { _, value in if value != .active { record() } }
        .sheet(isPresented: $settings) {
            NavigationStack {
                Form {
                    Section("字号 \(Int(fontSize))") { Slider(value: $fontSize, in: 14...34, step: 1) }
                    Section("行距") { Slider(value: $lineSpacing, in: 2...20, step: 1) }
                    NavigationLink("导入与更换字体") { FontSettingsView() }
                    Picker("主题", selection: $theme) { ForEach(["自动", "纸张", "日间", "夜间"], id: \.self) { Text($0) } }
                    Picker("简繁转换", selection: $script) {
                        Text("原文").tag(""); Text("简体").tag("simplified"); Text("繁体").tag("traditional")
                    }
                }.navigationTitle("阅读设置").toolbar { Button("完成") { settings = false } }
            }.presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $contents) {
            NavigationStack {
                List(chapters) { chapter in
                    Button(chapter.title) { jump(chapter.index); contents = false }.disabled(chapter.isVolume)
                }.navigationTitle("目录").toolbar { Button("关闭") { contents = false } }
            }
        }
        .sheet(isPresented: $bookmarks) {
            NavigationStack {
                List {
                    ForEach(library.entry(book)?.bookmarks ?? []) { mark in
                        Button { jump(mark.chapterIndex, position: mark.position); bookmarks = false } label: {
                            VStack(alignment: .leading) { Text(mark.chapterTitle); Text(mark.excerpt).font(.caption).lineLimit(2) }
                        }.swipeActions {
                            Button("删除", role: .destructive) {
                                guard var entry = library.entry(book) else { return }
                                entry.bookmarks.removeAll { $0.id == mark.id }; library.save(entry)
                            }
                        }
                    }
                }.overlay { if library.entry(book)?.bookmarks.isEmpty != false { ContentUnavailableView("暂无书签", systemImage: "bookmark") } }
                    .navigationTitle("书签").toolbar { Button("关闭") { bookmarks = false } }
            }
        }
    }
    private func load() async {
        content = nil; failure = nil; paragraph = nil
        let requestedIndex = index
        do {
            let loaded = try await NovelBooks.shared.content(book, chapters: chapters, index: requestedIndex)
            guard !Task.isCancelled, requestedIndex == index else { return }
            content = loaded
            paragraph = Int(resumePosition * Double(max(0, loaded.paragraphs.count - 1)))
            record()
            await NovelBooks.shared.prefetch(book, chapters: chapters, after: requestedIndex)
        } catch { if !Task.isCancelled { failure = error.localizedDescription } }
    }
    private func record() {
        guard content != nil, chapters.indices.contains(index) else { return }
        var entry = library.entry(book) ?? NovelLibrary.ShelfBook(book: book)
        entry.chapterIndex = index; entry.chapterTitle = chapters[index].title
        entry.chapterCount = chapters.count; entry.position = position; entry.updated = Date()
        library.save(entry)
    }
    private func addBookmark() {
        record()
        guard var entry = library.entry(book), let content else { return }
        let at = min(paragraph ?? 0, max(0, content.paragraphs.count - 1))
        entry.mark(NovelBookmark(chapterIndex: index, chapterTitle: chapters[index].title, position: position,
                                excerpt: content.paragraphs.isEmpty ? "" : String(content.paragraphs[at].prefix(100))))
        library.save(entry)
    }
    private func neighbor(_ direction: Int) -> Int? {
        var next = index + direction
        while chapters.indices.contains(next) {
            if !chapters[next].isVolume { return next }; next += direction
        }
        return nil
    }
    private func move(_ direction: Int) { if let next = neighbor(direction) { jump(next) } }
    private func jump(_ next: Int, position: Double = 0) {
        record(); content = nil; paragraph = nil; resumePosition = position; index = next; revision = UUID()
    }
}
