import SwiftUI
import UIKit
import TVCore

struct ReaderView: View {
    @Environment(ReaderLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let book: NovelBook
    let chapters: [NovelChapter]
    @State private var index: Int
    @State private var resumePosition: Double
    @State private var resumeOffset: Int?
    @State private var content: NovelContent?
    @State private var layout: ReaderTextLayout?
    @State private var characterOffset = 0
    @State private var page = 0
    @State private var restorePending = true
    @State private var failure: String?
    @State private var controls = false
    @State private var settings = false
    @State private var contents = false
    @State private var bookmarks = false
    @State private var revision = UUID()
    @State private var notice: String?
    @State private var saveTask: Task<Void, Never>?
    @AppStorage("reader.fontName") private var fontName = ""
    @AppStorage("reader.fontSize") private var fontSize = 20.0
    @AppStorage("reader.lineSpacing") private var lineSpacing = 10.0
    @AppStorage("reader.theme") private var theme = "自动"
    @AppStorage("reader.script") private var script = ""
    @AppStorage("reader.turnStyle") private var turnStyle = ReaderTurnStyle.slide.rawValue
    @AppStorage("reader.turnAnimation") private var turnAnimation = true
    @AppStorage("reader.tapTurns") private var tapTurns = true
    @AppStorage("reader.tapFraction") private var tapFraction = 0.3
    @AppStorage("reader.hideStatusBar") private var hideStatusBar = true
    @AppStorage("reader.hideHomeIndicator") private var hideHomeIndicator = true
    @AppStorage("reader.showProgress") private var showProgress = false
    @AppStorage("reader.didShowControlsHint") private var didShowHint = false

    init(book: NovelBook, chapters: [NovelChapter], start: Int, position: Double = 0, characterOffset: Int? = nil) {
        self.book = book; self.chapters = chapters
        _index = State(initialValue: start); _resumePosition = State(initialValue: position)
        _resumeOffset = State(initialValue: characterOffset)
    }
    private var style: ReaderTurnStyle { ReaderTurnStyle(rawValue: turnStyle) ?? .slide }
    private var dark: Bool { theme == "夜间" || (theme == "自动" && colorScheme == .dark) }
    private var background: Color { dark ? Color(white: 0.1) : theme == "纸张" ? Color(red: 0.95, green: 0.91, blue: 0.81) : Color(white: 0.99) }
    private var ink: Color { dark ? Color(white: 0.87) : Color(white: 0.16) }
    private var transformed: NovelContent? { content.map { (NovelScript(rawValue: script) ?? .original).convert($0) } }
    private var position: Double {
        Double(layout?.paragraph(at: characterOffset) ?? 0) / Double(max(1, (content?.paragraphs.count ?? 1) - 1))
    }
    private var progressText: String { "第 \(index + 1)/\(chapters.count) 章 · \(page + 1)/\(max(1, layout?.count ?? 1)) 页" }
    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            GeometryReader { geometry in
                let size = CGSize(width: max(80, geometry.size.width - 48), height: max(100, geometry.size.height - 28))
                Group {
                    if let layout, content != nil {
                        ReaderPageSurface(layout: layout, style: style, offset: characterOffset,
                            background: UIColor(background), animated: turnAnimation && !reduceMotion,
                            tapFraction: tapFraction, tapsEnabled: tapTurns,
                            moved: moved, boundary: boundary, center: { controls.toggle() })
                    } else if let failure {
                        ContentUnavailableView {
                            Label("章节加载失败", systemImage: "wifi.exclamationmark")
                        } description: { Text(failure) } actions: {
                            Button("重试") { revision = UUID() }
                            Button("阅读菜单") { controls = true }
                            Button("退出阅读") { dismiss() }
                        }
                    } else {
                        ProgressView("正在加载章节…").frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle()).onTapGesture { controls = true }
                    }
                }
                .frame(width: size.width, height: size.height)
                .padding(.horizontal, 24).padding(.vertical, 14)
                .task(id: LayoutKey(content: content, revision: revision, script: script, size: size, font: fontName, fontSize: fontSize, spacing: lineSpacing, dark: dark)) {
                    reflow(size: size)
                }
            }
            if showProgress && !controls {
                VStack { Spacer(); Text(progressText).font(.caption2).padding(.bottom, 2) }
                    .allowsHitTesting(false)
            }
            if controls { readerControls }
            if let notice {
                VStack { Spacer(); Text(notice).font(.footnote).padding(12).background(.regularMaterial, in: Capsule()).padding(.bottom, 100) }
                    .allowsHitTesting(false)
            }
        }
        .foregroundStyle(ink)
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .statusBarHidden(hideStatusBar)
        .persistentSystemOverlays(hideHomeIndicator ? .hidden : .visible)
        .interactiveDismissDisabled()
        .accessibilityAction(named: "阅读设置") { settings = true }
        .accessibilityAction(named: "退出阅读") { dismiss() }
        .task(id: "\(index)-\(revision)") { await load() }
        .task {
            if !didShowHint { didShowHint = true; notice = "左右点击或滑动翻页，点击中间显示菜单" }
        }
        .task(id: notice) {
            guard notice != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { notice = nil }
        }
        .onDisappear { saveTask?.cancel(); record() }
        .onChange(of: scenePhase) { _, value in if value != .active { saveTask?.cancel(); record() } }
        .sheet(isPresented: $settings, onDismiss: { controls = false }) { readingSettings }
        .sheet(isPresented: $contents) {
            NavigationStack {
                List(chapters) { chapter in
                    Button(chapter.title) { jump(chapter.index); contents = false; controls = false }.disabled(chapter.isVolume)
                }.navigationTitle("目录").toolbar { Button("关闭") { contents = false } }
            }
        }
        .sheet(isPresented: $bookmarks) { bookmarkList }
    }
    private var readerControls: some View {
        VStack {
            HStack(spacing: 16) {
                Button { record(); dismiss() } label: { Image(systemName: "chevron.left") }.accessibilityLabel("退出阅读")
                Text(book.name).font(.headline).lineLimit(1)
                Spacer(minLength: 0)
                Button { controls = false } label: { Image(systemName: "xmark") }.accessibilityLabel("隐藏菜单")
            }.padding().background(.regularMaterial)
            Spacer()
            VStack(spacing: 16) {
                HStack {
                    Button("上一章") { if let previous = neighbor(-1) { jump(previous) } }.disabled(neighbor(-1) == nil)
                    Spacer()
                    Text(progressText).font(.caption).monospacedDigit()
                    Spacer()
                    Button("下一章") { if let next = neighbor(1) { jump(next) } }.disabled(neighbor(1) == nil)
                }
                if let layout, layout.count > 1 {
                    Slider(value: Binding(get: { Double(page) }, set: {
                        page = Int($0); characterOffset = layout.offset(page: page); record()
                    }), in: 0...Double(layout.count - 1), step: 1).accessibilityLabel("本章阅读页码")
                }
                HStack {
                    Button { contents = true } label: { Label("目录", systemImage: "list.bullet") }
                    Spacer()
                    Menu {
                        Button("添加书签") { addBookmark() }.disabled(content == nil)
                        Button("查看书签") { bookmarks = true }
                    } label: { Label("书签", systemImage: "bookmark") }
                    Spacer()
                    Button { settings = true } label: { Label("设置", systemImage: "textformat.size") }
                }
            }.padding().background(.regularMaterial)
        }.buttonStyle(.plain)
    }
    private var readingSettings: some View {
        NavigationStack {
            Form {
                Section("翻页方式") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                        ForEach(ReaderTurnStyle.allCases) { item in
                            Button { turnStyle = item.rawValue } label: {
                                VStack(spacing: 5) {
                                    Text(item.title).font(.headline)
                                    Text(style == item ? "当前" : (item == .scroll ? "连续" : "翻页")).font(.caption)
                                }.frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(style == item ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                        }
                    }
                    Toggle("翻页动画", isOn: $turnAnimation)
                    Toggle("点击左右区域翻页", isOn: $tapTurns)
                    if tapTurns {
                        LabeledContent("每侧翻页区域", value: "\(Int(tapFraction * 100))%")
                        Slider(value: $tapFraction, in: 0.2...0.4, step: 0.05)
                    }
                    Text("点击中间区域显示菜单。滑到本章末页继续翻页可进入下一章；滚动模式在底部继续上拉进入下一章。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("全屏显示") {
                    Toggle("隐藏状态栏", isOn: $hideStatusBar)
                    Toggle("隐藏底部横条", isOn: $hideHomeIndicator)
                    Toggle("显示阅读进度", isOn: $showProgress)
                }
                Section("文字") {
                    NavigationLink("导入与更换字体") { FontSettingsView() }
                    LabeledContent("字号", value: "\(Int(fontSize))")
                    Slider(value: $fontSize, in: 14...34, step: 1)
                    LabeledContent("行距", value: "\(Int(lineSpacing))")
                    Slider(value: $lineSpacing, in: 2...20, step: 1)
                    Picker("简繁转换", selection: $script) {
                        Text("原文").tag(""); Text("简体").tag("simplified"); Text("繁体").tag("traditional")
                    }
                }
                Picker("主题", selection: $theme) { ForEach(["自动", "纸张", "日间", "夜间"], id: \.self) { Text($0) } }
            }.navigationTitle("阅读设置").toolbar { Button("完成") { settings = false } }
        }.presentationDetents([.medium, .large])
    }
    private var bookmarkList: some View {
        NavigationStack {
            List {
                ForEach(library.entry(book)?.bookmarks ?? []) { mark in
                    Button {
                        jump(mark.chapterIndex, position: mark.position, offset: mark.characterOffset)
                        bookmarks = false; controls = false
                    } label: {
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
    private func load() async {
        content = nil; layout = nil; failure = nil; restorePending = true
        let requestedIndex = index
        do {
            let loaded = try await NovelBooks.shared.content(book, chapters: chapters, index: requestedIndex)
            guard !Task.isCancelled, requestedIndex == index else { return }
            content = loaded
            await NovelBooks.shared.prefetch(book, chapters: chapters, after: requestedIndex)
        } catch { if !Task.isCancelled { failure = error.localizedDescription } }
    }
    private func reflow(size: CGSize) {
        guard let content = transformed else { return }
        // Restore process font registrations before TextKit resolves the saved PostScript name.
        _ = ReaderFonts.shared
        let newLayout = ReaderTextLayout(content: content, size: size, fontName: fontName,
            fontSize: fontSize, lineSpacing: lineSpacing, color: UIColor(ink))
        guard newLayout.count > 0, newLayout.isComplete else { failure = "当前页面无法完整排版，请在阅读设置中调整字号。"; layout = nil; return }
        let requested = restorePending ? (resumeOffset ?? newLayout.offset(paragraph: Int(resumePosition * Double(max(0, content.paragraphs.count - 1))))) : characterOffset
        characterOffset = min(max(0, requested), max(0, newLayout.text.length - 1))
        page = newLayout.page(containing: characterOffset)
        layout = newLayout; restorePending = false
        record()
    }
    private func moved(_ offset: Int, _ page: Int) {
        characterOffset = offset; self.page = page
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { record() }
        }
    }
    private func boundary(_ forward: Bool) {
        if let next = neighbor(forward ? 1 : -1) { jump(next, offset: forward ? 0 : Int.max) }
        else { notice = forward ? "已经是最后一章" : "已经是第一章" }
    }
    private func record() {
        guard content != nil, layout != nil, chapters.indices.contains(index) else { return }
        var entry = library.entry(book) ?? NovelLibrary.ShelfBook(book: book)
        entry.chapterIndex = index; entry.chapterTitle = chapters[index].title
        entry.chapterCount = chapters.count; entry.position = position; entry.characterOffset = characterOffset; entry.updated = Date()
        library.save(entry)
    }
    private func addBookmark() {
        record()
        guard var entry = library.entry(book), let content else { return }
        let at = min(layout?.paragraph(at: characterOffset) ?? 0, max(0, content.paragraphs.count - 1))
        entry.mark(NovelBookmark(chapterIndex: index, chapterTitle: chapters[index].title, position: position,
            excerpt: content.paragraphs.isEmpty ? "" : String(content.paragraphs[at].prefix(100)), characterOffset: characterOffset))
        library.save(entry); notice = "已添加书签"
    }
    private func neighbor(_ direction: Int) -> Int? {
        var next = index + direction
        while chapters.indices.contains(next) {
            if !chapters[next].isVolume { return next }; next += direction
        }
        return nil
    }
    private func jump(_ next: Int, position: Double = 0, offset: Int? = nil) {
        saveTask?.cancel(); record(); content = nil; layout = nil
        resumePosition = position; resumeOffset = offset; index = next; revision = UUID()
    }
    private struct LayoutKey: Equatable {
        let content: NovelContent?
        let revision: UUID
        let script: String
        let size: CGSize
        let font: String
        let fontSize: Double
        let spacing: Double
        let dark: Bool
    }
}
