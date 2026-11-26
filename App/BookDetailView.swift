import SwiftUI
import TVCore

struct BookDetailView: View {
    @Environment(ReaderLibrary.self) private var library
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var book: NovelBook
    @State private var chapters: [NovelChapter] = []
    @State private var error: String?
    @State private var loading = false
    @State private var reading: ReadingStart?
    @State private var introExpanded = false
    private var resume: ReaderResume? { ReaderResume.resolve(library.entry(book), chapters: chapters) }
    private var currentChapter: Int? { library.entry(book)?.started == true ? resume?.index : nil }
    private struct ReadingStart: Identifiable {
        let id = UUID()
        let index: Int
        var position: Double = 0
        var offset: Int? = nil
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                bookHeader.padding(.top, 12).padding(.bottom, 26)
                if !book.intro.isEmpty {
                    introduction.padding(.bottom, 24)
                    Divider().padding(.bottom, 24)
                }
                HStack {
                    Text("目录").font(.title3.bold())
                    Spacer()
                    Text("\(chapters.filter { !$0.isVolume }.count) 章").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.bottom, 12)
                if loading { ProgressView("正在加载目录…").frame(maxWidth: .infinity).padding(.vertical, 24) }
                if let error {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("目录加载失败", systemImage: "wifi.exclamationmark").font(.headline)
                        Text(error).font(.subheadline).foregroundStyle(.secondary)
                        Button("重试") { Task { await load() } }.buttonStyle(.bordered)
                    }.padding(.vertical, 20)
                }
                if !loading && error == nil && chapters.allSatisfy(\.isVolume) {
                    Text("暂无可阅读章节").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 24)
                }
                ForEach(chapters) { chapter in
                    if chapter.isVolume {
                        Text(chapter.title).font(.headline).padding(.top, 20).padding(.bottom, 12)
                    }
                    else {
                        Button { reading = ReadingStart(index: chapter.index) } label: {
                            HStack(spacing: 12) {
                                Text(chapter.title).font(.subheadline)
                                    .foregroundStyle(currentChapter == chapter.index ? AppPalette.accent : Color.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                if currentChapter == chapter.index {
                                    Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(AppPalette.accent)
                                } else { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                            }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                .padding(.vertical, 3).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Divider().opacity(0.45)
                    }
                }
            }.padding(.horizontal, 24).padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppPalette.paper.ignoresSafeArea())
        .navigationTitle("书籍详情").navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(AppPalette.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { readingActions }
        .task { await load() }
        .refreshable { await load(refresh: true) }
        .fullScreenCover(item: $reading) { start in
            ReaderView(book: book, chapters: chapters, start: start.index, position: start.position, characterOffset: start.offset)
                .environment(library)
        }
    }
    private var bookHeader: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 18) {
                    BookCover(book: book, width: 104)
                    metadata
                }
            } else {
                HStack(alignment: .top, spacing: 20) {
                    BookCover(book: book, width: 104)
                    metadata.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
    private var metadata: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(book.name).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
            Text(book.author.isEmpty ? "佚名" : book.author).font(.subheadline).foregroundStyle(.secondary)
            if !book.kind.isEmpty {
                Text(book.kind).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !book.wordCount.isEmpty {
                Text(book.wordCount).font(.subheadline.weight(.semibold)).foregroundStyle(AppPalette.accent)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: toggleIntroduction) {
                HStack {
                    Text("内容简介").font(.title3.bold()).foregroundStyle(.primary)
                    Spacer()
                    Text(introExpanded ? "收起" : "展开").font(.subheadline)
                    Image(systemName: introExpanded ? "chevron.up" : "chevron.down").font(.caption)
                }.frame(minHeight: 36).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityValue(introExpanded ? "已展开" : "已收起")
            Text(book.intro).font(.subheadline).foregroundStyle(.secondary).lineSpacing(6)
                .lineLimit(introExpanded ? nil : 4).frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle()).onTapGesture { toggleIntroduction() }
        }
    }
    private func toggleIntroduction() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { introExpanded.toggle() }
    }
    private var readingActions: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) { collectButton; readButton }
            } else {
                HStack(spacing: 12) { collectButton; readButton }
            }
        }
        .controlSize(.large).padding(.horizontal, 24).padding(.vertical, 12)
        .background(AppPalette.paper)
        .overlay(alignment: .top) { Divider().opacity(0.5) }
    }
    private var collectButton: some View {
        Button {
            if library.entry(book) == nil { library.save(NovelLibrary.ShelfBook(book: book, chapterCount: chapters.count)) }
        } label: {
            Label(library.entry(book) == nil ? "加入书架" : "已在书架",
                  systemImage: library.entry(book) == nil ? "plus" : "checkmark")
                .frame(maxWidth: .infinity, minHeight: 24)
        }.buttonStyle(.bordered).disabled(library.entry(book) != nil)
    }
    private var readButton: some View {
        Button {
            if let resume { reading = ReadingStart(index: resume.index, position: resume.position, offset: resume.offset) }
        } label: {
            Text(library.entry(book)?.started == true ? "继续阅读" : "开始阅读").fontWeight(.semibold)
                .frame(maxWidth: .infinity, minHeight: 24)
        }.buttonStyle(.borderedProminent).disabled(resume == nil)
    }
    private func load(refresh: Bool = false) async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            // Cached chapters remain readable when the website is offline.
            chapters = try await NovelBooks.shared.chapters(book, refresh: refresh)
            guard !Task.isCancelled else { return }
            if let details = try? await NovelBooks.shared.details(book) {
                guard !Task.isCancelled else { return }
                // Metadata enrichment must keep the identity used by existing shelf entries.
                var enriched = details
                enriched.name = book.name; enriched.author = book.author
                if enriched.cover.isEmpty { enriched.cover = book.cover }
                book = enriched
                library.updateDetails(enriched, chapterCount: chapters.count)
            }
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
