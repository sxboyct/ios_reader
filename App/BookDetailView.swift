import SwiftUI
import TVCore

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
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 20) {
                        BookCover(book: book, width: 106)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(book.name).font(.title2.bold())
                            Text(book.author.isEmpty ? "佚名" : book.author).foregroundStyle(.secondary)
                            if !book.kind.isEmpty { Text(book.kind).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                            if !book.wordCount.isEmpty { Text(book.wordCount).font(.caption.weight(.medium)).foregroundStyle(AppPalette.accent) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 12) {
                        Button(library.entry(book) == nil ? "加入书架" : "已在书架") {
                            if library.entry(book) == nil { library.save(NovelLibrary.ShelfBook(book: book, chapterCount: chapters.count)) }
                        }.buttonStyle(.bordered).disabled(library.entry(book) != nil)
                        if let index = NovelChapterMatch.index(title: library.entry(book)?.chapterTitle ?? "", index: library.entry(book)?.chapterIndex ?? 0, in: chapters) {
                            Button(library.entry(book)?.started == true ? "继续阅读" : "开始阅读") {
                                reading = ReadingStart(index: index, position: library.entry(book)?.position ?? 0, offset: library.entry(book)?.characterOffset)
                            }.buttonStyle(.borderedProminent)
                        }
                    }.controlSize(.large)
                    if !book.intro.isEmpty {
                        Text("内容简介").font(.headline)
                        Text(book.intro).font(.subheadline).foregroundStyle(.secondary).lineSpacing(5).textSelection(.enabled)
                    }
                }.padding(18).bookCard()
                    .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)).listRowBackground(Color.clear)
            }
            if loading { ProgressView("正在加载目录…") }
            if let error { Section { Text(error); Button("重试") { Task { await load() } } } }
            Section("目录 · \(chapters.count)") {
                ForEach(chapters) { chapter in
                    if chapter.isVolume { Text(chapter.title).font(.headline) }
                    else {
                        Button { reading = ReadingStart(index: chapter.index) } label: {
                            HStack {
                                Text(chapter.title).foregroundStyle(library.entry(book)?.chapterIndex == chapter.index ? AppPalette.accent : Color.primary)
                                Spacer()
                                if library.entry(book)?.chapterIndex == chapter.index { Image(systemName: "bookmark.fill").font(.caption) }
                            }.padding(.vertical, 5)
                        }
                    }
                }
            }
        }.listStyle(.insetGrouped).appPage().navigationTitle("书籍详情").navigationBarTitleDisplayMode(.inline)
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
            if let details = try? await NovelBooks.shared.details(book) {
                // Metadata enrichment must keep the identity used by existing shelf entries.
                var enriched = details
                enriched.name = book.name; enriched.author = book.author
                if enriched.cover.isEmpty { enriched.cover = book.cover }
                book = enriched
                library.updateDetails(enriched, chapterCount: chapters.count)
            }
        } catch { self.error = error.localizedDescription }
        loading = false
    }
}
