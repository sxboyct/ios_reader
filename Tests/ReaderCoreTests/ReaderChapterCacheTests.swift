import Foundation
import Testing
@testable import TVCore

@Test func nextTwoChaptersSkipAnyNumberOfVolumeHeadings() {
    let chapters = (0..<9).map { NovelChapter(index: $0, title: "\($0)", url: "chapter-\($0)", isVolume: (1...5).contains($0)) }
    #expect(NovelBooks.prefetchIndices(chapters, after: 0) == [6, 7])
    #expect(NovelBooks.prefetchIndices(chapters, after: 7) == [8])
    #expect(NovelBooks.prefetchIndices(chapters, after: 8).isEmpty)
    #expect(NovelBooks.prefetchIndices([], after: 0).isEmpty)
}

@Test func prefetchWarmsTwoOfflineChaptersAndClearInvalidatesMemory() async throws {
    let store = NovelBooks()
    let book = NovelBook(sourceKey: "missing-cache-test-\(UUID())", url: "https://example.invalid/\(UUID())", name: "Cache test")
    let chapters = (0..<3).map { NovelChapter(index: $0, title: "第\($0)章", url: "https://example.invalid/chapter/\($0)") }
    let folder = NovelLibrary.cache.appendingPathComponent(PluginChecksum.sha256(Data(book.id.utf8)), isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    for chapter in chapters {
        let file = folder.appendingPathComponent("\(chapter.index)-" + PluginChecksum.sha256(Data(chapter.url.utf8)).prefix(12) + ".json")
        try JSONEncoder().encode(NovelContent(title: chapter.title, paragraphs: ["已缓存的完整正文"])).write(to: file)
    }
    await store.prefetch(book, chapters: chapters, after: 0)
    try FileManager.default.removeItem(at: folder)
    // Disk no longer exists and this source cannot make a request: both chapters must be in memory.
    for index in [1, 2] {
        let text = try await store.content(book, chapters: chapters, index: index)
        #expect(text.title == chapters[index].title)
    }
    await store.clear(book)
    do {
        _ = try await store.content(book, chapters: chapters, index: 1)
        Issue.record("Clearing the book must invalidate memory as well as disk")
    } catch { }
}
