import SwiftUI
import UIKit
import PhotosUI
import TVCore

struct ReaderView: View {
    @Environment(ReaderLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    let book: NovelBook
    let chapters: [NovelChapter]
    @State private var index: Int
    @State private var resumePosition: Double
    @State private var resumeOffset: Int?
    @State private var content: NovelContent?
    @State private var contentRevision = UUID()
    @State private var layout: ReaderTextLayout?
    @State private var renderer: ReaderPageRenderer?
    @State private var preparedNext: ReaderPreparedChapter?
    @State private var nextPreparation: Task<ReaderPreparedChapter, Error>?
    @State private var nextPreparationKey: LayoutKey?
    @State private var nextPreparationID = UUID()
    @State private var appliedConfiguration: ReaderRenderConfiguration?
    @State private var loadedIndex: Int?
    @State private var loadedRevision: UUID?
    @State private var isLoading = true
    @State private var refreshChapter = false
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
    @State private var backgrounds = ReaderBackgrounds.shared
    @State private var backgroundSelection: PhotosPickerItem?
    @AppStorage("reader.backgroundOpacity") private var backgroundOpacity = 0.3
    @AppStorage("reader.fontName") private var fontName = ""
    @AppStorage("reader.fontSize") private var fontSize = 20.0
    @AppStorage("reader.lineSpacing") private var lineSpacing = 10.0
    @AppStorage("reader.theme") private var theme = "自动"
    @AppStorage("reader.script") private var script = ""
    @AppStorage("reader.turnStyle") private var turnStyle = ReaderTurnStyle.slide.rawValue
    @AppStorage("reader.turnAnimation") private var turnAnimation = true
    @AppStorage("reader.slideForwardRight") private var slideForwardRight = true
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
    private var position: Double {
        Double(layout?.paragraph(at: characterOffset) ?? 0) / Double(max(1, (content?.paragraphs.count ?? 1) - 1))
    }
    private var progressText: String { "第 \(index + 1)/\(chapters.count) 章 · \(page + 1)/\(max(1, layout?.count ?? 1)) 页" }
    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            GeometryReader { geometry in
                let safeArea = geometry.safeAreaInsets
                let viewport = ReaderViewport(safeAreaSize: geometry.size,
                    safeAreaInsets: UIEdgeInsets(top: safeArea.top, left: safeArea.leading,
                        bottom: safeArea.bottom, right: safeArea.trailing))
                let configuration = ReaderRenderConfiguration(viewport: viewport, script: script, fontName: fontName,
                    fontSize: fontSize, lineSpacing: lineSpacing, appearance: "\(theme)-\(dark)",
                    ink: UIColor(ink), background: UIColor(background),
                    image: backgrounds.image, opacity: backgroundOpacity, scale: displayScale)
                ZStack(alignment: .topLeading) {
                Group {
                    if let layout, let renderer {
                        ReaderPageSurface(layout: layout, renderer: renderer, viewport: renderer.viewport, style: style, offset: characterOffset,
                            background: UIColor(background), backgroundImage: backgrounds.image,
                            backgroundOpacity: backgroundOpacity, animated: turnAnimation && !reduceMotion,
                            tapFraction: tapFraction, tapsEnabled: tapTurns, slideForwardRight: slideForwardRight,
                            moved: { [chapter = index, identity = layout] offset, page in
                                guard !isLoading, loadedIndex == chapter, self.layout === identity else { return }
                                moved(offset, page)
                            }, boundary: { [chapter = index, identity = layout] forward in
                                guard !isLoading, loadedIndex == chapter, self.layout === identity else { return }
                                boundary(forward)
                            }, center: { controls.toggle() },
                            nextLayout: preparedNext?.configuration == configuration ? preparedNext?.layout : nil,
                            nextRenderer: preparedNext?.configuration == configuration ? preparedNext?.renderer : nil,
                            crossedChapter: { adoptNext() },
                            loadNext: neighbor(1) == nil ? nil : {
                                let requestedIndex = index
                                await prepareNext(configuration: configuration)
                                guard requestedIndex == index, preparedNext?.configuration == configuration else { return nil }
                                return preparedNext
                            })
                            .allowsHitTesting(!isLoading)
                            .overlay {
                                if isLoading { ProgressView("正在准备章节…").padding().background(.regularMaterial, in: Capsule()) }
                            }
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
                .frame(width: viewport.size.width, height: viewport.size.height)
                .background {
                    if layout == nil, let image = backgrounds.image {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: viewport.size.width, height: viewport.size.height)
                            .clipped().opacity(backgroundOpacity)
                    }
                }
                .offset(x: viewport.origin.x, y: viewport.origin.y)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .task(id: LayoutKey(contentRevision: contentRevision, revision: revision, configuration: configuration)) {
                    if !restorePending, appliedConfiguration != configuration {
                        do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
                    }
                    guard !Task.isCancelled, geometry.size.width > 0, geometry.size.height > 0 else { return }
                    await reflow(configuration: configuration)
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
        .onDisappear { saveTask?.cancel(); nextPreparation?.cancel(); record(); library.flushShelf() }
        .onChange(of: scenePhase) { _, value in
            if value != .active { saveTask?.cancel(); record(); library.flushShelf() }
        }
        .overlay {
            if settings {
                ReaderSettingsPanel(background: background, close: { settings = false }) { readingSettings }
            }
        }
        .onChange(of: settings) { _, shown in if shown { controls = false } }
        .onChange(of: backgroundSelection) { _, item in
            guard let item else { return }
            Task { await backgrounds.importPhoto(item); backgroundSelection = nil }
        }
        .alert("背景图片", isPresented: Binding(get: { backgrounds.error != nil }, set: { if !$0 { backgrounds.error = nil } })) {
            Button("确定") { backgrounds.error = nil }
        } message: { Text(backgrounds.error ?? "") }
        .sheet(isPresented: $contents) {
            NavigationStack {
                ScrollViewReader { proxy in
                    List(chapters) { chapter in
                        Button { jump(chapter.index); contents = false; controls = false } label: {
                            HStack {
                                Text(chapter.title)
                                Spacer()
                                if chapter.index == index {
                                    Label("正在阅读", systemImage: "book.fill").font(.caption)
                                }
                            }
                            .foregroundStyle(chapter.index == index ? Color.accentColor : Color.primary)
                            .fontWeight(chapter.index == index ? .semibold : .regular)
                        }
                        .disabled(chapter.isVolume)
                        .listRowBackground(chapter.index == index ? Color.accentColor.opacity(0.12) : Color.clear)
                        .id(chapter.index)
                    }
                    .onAppear { proxy.scrollTo(index, anchor: .center) }
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
                Menu {
                    Button("重新加载本章") {
                        refreshChapter = true
                        jump(index, position: position, offset: characterOffset)
                        controls = false
                    }.disabled(isLoading)
                } label: { Image(systemName: "arrow.clockwise") }
                .accessibilityLabel("重新加载本章")
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
                Section("背景") {
                    HStack {
                        PhotosPicker(selection: $backgroundSelection, matching: .images) {
                            Label(backgrounds.image == nil ? "选择背景图" : "更换背景图", systemImage: "photo")
                        }.disabled(backgrounds.busy)
                        Spacer()
                        Button("删除背景图", role: .destructive) { backgrounds.remove() }
                            .disabled(backgrounds.image == nil || backgrounds.busy)
                    }.buttonStyle(.borderless)
                    if backgrounds.busy { ProgressView("正在保存背景图片…") }
                    if backgrounds.image != nil {
                        LabeledContent("图片浓度", value: "\(Int(backgroundOpacity * 100))%")
                        Slider(value: $backgroundOpacity, in: 0.1...1, step: 0.05)
                    }
                    Picker("主题", selection: $theme) { ForEach(["自动", "纸张", "日间", "夜间"], id: \.self) { Text($0) } }
                    Text("背景覆盖整个屏幕。删除后恢复主题底色，原照片不受影响。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
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
                    if style == .slide {
                        Toggle("右滑进入下一页", isOn: $slideForwardRight)
                        Text("页面跟随手指移动，短距离滑动或轻快一划即可翻页，无需超过半屏；不足距离时回弹。关闭上方选项后，左滑进入下一页。")
                            .font(.footnote).foregroundStyle(.secondary)
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
                    NavigationLink("导入与更换字体") { FontSettingsView(background: background) }
                    LabeledContent("字号", value: "\(Int(fontSize))")
                    Slider(value: $fontSize, in: 14...34, step: 1)
                    LabeledContent("行距", value: "\(Int(lineSpacing))")
                    Slider(value: $lineSpacing, in: 2...20, step: 1)
                    Picker("简繁转换", selection: $script) {
                        Text("原文").tag(""); Text("简体").tag("simplified"); Text("繁体").tag("traditional")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(background)
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { Button("完成") { settings = false } }
        }
        .environment(\.colorScheme, dark ? .dark : .light)
        .background(background)
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
        if loadedIndex == index, loadedRevision == revision, !restorePending { return }
        failure = nil; restorePending = true; isLoading = true
        loadedIndex = nil; loadedRevision = nil
        let requestedIndex = index
        let requestedRevision = revision
        do {
            let loaded: NovelContent
            if !refreshChapter, let preparedNext, preparedNext.index == requestedIndex { loaded = preparedNext.content }
            else { loaded = try await NovelBooks.shared.content(book, chapters: chapters, index: requestedIndex, refresh: refreshChapter) }
            guard !Task.isCancelled, requestedIndex == index, requestedRevision == revision else { return }
            refreshChapter = false
            content = loaded; loadedIndex = requestedIndex; loadedRevision = requestedRevision; contentRevision = UUID()
        } catch {
            if !Task.isCancelled, requestedIndex == index, requestedRevision == revision {
                failure = error.localizedDescription; layout = nil; renderer = nil; isLoading = false
            }
        }
    }
    private func reflow(configuration: ReaderRenderConfiguration) async {
        guard let content, loadedIndex == index, loadedRevision == revision else { return }
        if !restorePending, appliedConfiguration == configuration, layout != nil {
            await prepareNext(configuration: configuration)
            return
        }
        isLoading = true
        _ = ReaderFonts.shared
        let requestedIndex = index
        let requestedRevision = revision
        let requestedContent = contentRevision
        do {
            let prepared: ReaderPreparedChapter
            if let candidate = preparedNext, candidate.index == index, candidate.content == content,
               candidate.configuration == configuration {
                prepared = candidate
            } else {
                prepared = try await ReaderPreparedChapter.build(index: index, content: content, configuration: configuration,
                    position: restorePending ? resumePosition : 0, character: restorePending ? resumeOffset : characterOffset)
            }
            guard !Task.isCancelled, requestedIndex == index, requestedRevision == revision,
                  requestedContent == contentRevision else { return }
            let offset = prepared.offset(position: restorePending ? resumePosition : 0,
                character: restorePending ? resumeOffset : characterOffset)
            await prepared.renderer.prepareAsync(around: prepared.layout.page(containing: offset))
            guard !Task.isCancelled, requestedIndex == index, requestedRevision == revision,
                  requestedContent == contentRevision else { return }
            characterOffset = offset; page = prepared.layout.page(containing: offset)
            layout = prepared.layout; renderer = prepared.renderer; appliedConfiguration = configuration
            restorePending = false; isLoading = false; preparedNext = nil
            record()
            await prepareNext(configuration: configuration)
        } catch {
            if !Task.isCancelled, requestedIndex == index, requestedRevision == revision, isLoading {
                failure = error.localizedDescription; layout = nil; renderer = nil; isLoading = false
            }
        }
    }
    private func prepareNext(configuration: ReaderRenderConfiguration) async {
        guard let next = neighbor(1) else { preparedNext = nil; return }
        if preparedNext?.index == next, preparedNext?.configuration == configuration { return }
        let requestedIndex = index
        let requestedRevision = revision
        let key = LayoutKey(contentRevision: contentRevision, revision: revision, configuration: configuration)
        var taskID = nextPreparationID
        do {
            let task: Task<ReaderPreparedChapter, Error>
            if nextPreparationKey == key, let running = nextPreparation { task = running }
            else {
                nextPreparation?.cancel()
                taskID = UUID(); nextPreparationID = taskID
                task = Task {
                    let nextContent = try await NovelBooks.shared.content(book, chapters: chapters, index: next)
                    try Task.checkCancellation()
                    return try await ReaderPreparedChapter.build(index: next, content: nextContent,
                        configuration: configuration, priority: .utility)
                }
                nextPreparationKey = key; nextPreparation = task
            }
            let prepared = try await task.value
            guard !Task.isCancelled, index == requestedIndex, revision == requestedRevision,
                  contentRevision == key.contentRevision, nextPreparationID == taskID else { return }
            preparedNext = prepared
        } catch {
            if nextPreparationID == taskID { nextPreparation = nil; nextPreparationKey = nil }
        }
    }
    private func adoptNext() {
        guard let prepared = preparedNext, prepared.index == neighbor(1),
              prepared.configuration == appliedConfiguration else { return }
        saveTask?.cancel(); record()
        index = prepared.index; content = prepared.content
        layout = prepared.layout; renderer = prepared.renderer
        characterOffset = 0; page = 0; resumePosition = 0; resumeOffset = 0
        revision = UUID(); contentRevision = UUID()
        loadedIndex = index; loadedRevision = revision
        restorePending = false; isLoading = false; preparedNext = nil; failure = nil
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
        guard !isLoading, loadedIndex == index, loadedRevision == revision,
              content != nil, layout != nil, chapters.indices.contains(index) else { return }
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
        saveTask?.cancel(); record(); isLoading = true; loadedRevision = nil
        resumePosition = position; resumeOffset = offset; index = next; revision = UUID()
    }
    private struct LayoutKey: Equatable {
        let contentRevision: UUID
        let revision: UUID
        let configuration: ReaderRenderConfiguration
    }
}
