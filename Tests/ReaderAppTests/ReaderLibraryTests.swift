import Foundation
import Testing
import TVCore

@Suite(.serialized) @MainActor struct ReaderLibraryTests {
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
