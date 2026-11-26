import Foundation
import Testing
import TVCore

@Suite(.serialized) @MainActor struct ReaderLibraryTests {
    @Test func openingResumesByChapterTitleAfterCatalogInsertion() throws {
        let book = NovelBook(sourceKey: "fixture", url: "/resume", name: "恢复进度")
        let chapters = [NovelChapter(index: 0, title: "第一卷", url: "", isVolume: true),
                        NovelChapter(index: 1, title: "第一章 初见", url: "/1"),
                        NovelChapter(index: 2, title: "第二章 重逢", url: "/2")]
        var entry = NovelLibrary.ShelfBook(book: book, chapterIndex: 1, chapterTitle: "第二章 重逢", position: 0.35)
        entry.characterOffset = 260
        let resume = try #require(ReaderResume.resolve(entry, chapters: chapters))
        #expect(resume.index == 2)
        #expect(resume.position == 0.35)
        #expect(resume.offset == 260)
        let first = try #require(ReaderResume.resolve(nil, chapters: chapters))
        #expect(first.index == 1)
        #expect(first.position == 0)
        #expect(first.offset == nil)
    }
    @Test func openingDiscardsOffsetWhenOriginalChapterIsGone() throws {
        let book = NovelBook(sourceKey: "fixture", url: "/resume", name: "恢复进度")
        let chapters = [NovelChapter(index: 0, title: "第一章", url: "/1"),
                        NovelChapter(index: 1, title: "第二章", url: "/2")]
        var entry = NovelLibrary.ShelfBook(book: book, chapterIndex: 999, chapterTitle: "已删除章节", position: 0.9)
        entry.characterOffset = 9000
        let fallback = try #require(ReaderResume.resolve(entry, chapters: chapters))
        #expect(fallback.index == 1)
        #expect(fallback.position == 0)
        #expect(fallback.offset == nil)
        entry.chapterIndex = 0; entry.chapterTitle = "第一章"; entry.position = .nan; entry.characterOffset = -10
        let clamped = try #require(ReaderResume.resolve(entry, chapters: chapters))
        #expect(clamped.position == 0)
        #expect(clamped.offset == 0)
        #expect(ReaderResume.resolve(entry, chapters: []) == nil)
        #expect(ReaderResume.resolve(entry, chapters: [NovelChapter(index: 0, title: "卷一", url: "", isVolume: true)]) == nil)
    }
    @Test func readingDoesNotCollectUntilExplicitlySaved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = ReaderLibrary(directory: folder)
        let book = NovelBook(sourceKey: "fixture", url: "/book", name: "测试书籍")
        var progress = NovelLibrary.ShelfBook(book: book, chapterIndex: 3, chapterTitle: "第四章", chapterCount: 20, position: 0.4)
        progress.characterOffset = 120
        progress.mark(NovelBookmark(chapterIndex: 3, chapterTitle: "第四章", position: 0.4, excerpt: "书签", characterOffset: 120))
        #expect(!library.recordProgress(progress))
        library.flushShelf()
        #expect(ReaderLibrary(directory: folder).shelf.isEmpty)
        library.save(progress) // The exit dialog's explicit add action.
        library.flushShelf()
        let restored = ReaderLibrary(directory: folder)
        #expect(restored.entry(book)?.characterOffset == 120)
        #expect(restored.entry(book)?.bookmarks.count == 1)
        progress.characterOffset = 240
        #expect(restored.recordProgress(progress))
        restored.flushShelf()
        #expect(ReaderLibrary(directory: folder).entry(book)?.characterOffset == 240)
        restored.remove(book)
        #expect(!restored.recordProgress(progress)) // A delayed save must not re-add a removed book.
        restored.flushShelf()
        #expect(ReaderLibrary(directory: folder).shelf.isEmpty)
    }
}
