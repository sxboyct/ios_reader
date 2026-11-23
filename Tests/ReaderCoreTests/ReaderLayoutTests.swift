import Foundation
import UIKit
import Testing
@testable import TVCore

@MainActor struct ReaderLayoutTests {
    private let content = NovelContent(title: "第一章 测试", paragraphs: [
        String(repeating: "长段落需要跨页，但任何一个字都不应丢失。😀 👨‍👩‍👧‍👦 e\u{301} ", count: 140),
        "最后一段，确认能翻到结尾。"
    ])
    private func layout(size: CGSize = CGSize(width: 320, height: 600), fontSize: Double = 20) -> ReaderTextLayout {
        ReaderTextLayout(content: content, size: size, fontName: "", fontSize: fontSize, lineSpacing: 8, color: .black)
    }
    @Test func longParagraphPagesCoverAllCharactersWithoutGapsOrDuplicates() {
        let pages = layout()
        #expect(pages.count > 2)
        #expect(pages.isComplete)
        var expectedStart = 0
        var reconstructed = ""
        for (index, range) in pages.pageRanges.enumerated() {
            #expect(range.location == expectedStart)
            #expect(range.length > 0)
            reconstructed += pages.text.attributedSubstring(from: range).string
            #expect(pages.page(containing: range.location) == index)
            #expect(pages.page(containing: NSMaxRange(range) - 1) == index)
            expectedStart = NSMaxRange(range)
        }
        #expect(expectedStart == pages.text.length)
        #expect(reconstructed == pages.text.string)
        #expect(reconstructed.hasSuffix("最后一段，确认能翻到结尾。"))
    }
    @Test func sizeAndFontChangesPreserveTheSameTextOffset() {
        let original = layout()
        let offset = original.offset(page: original.count / 2)
        let enlarged = layout(size: CGSize(width: 280, height: 440), fontSize: 32)
        let page = enlarged.page(containing: offset)
        #expect(NSLocationInRange(offset, enlarged.pageRanges[page]))
        #expect(enlarged.count > original.count)
        #expect(original.text.string == enlarged.text.string)
        #expect(original.paragraph(at: offset) == enlarged.paragraph(at: offset))
    }
    @Test func oldShelfMigratesAndPreciseBookmarksRoundTrip() throws {
        let book = NovelBook(sourceKey: "a", url: "https://a/book", name: "书")
        var shelf = NovelLibrary.ShelfBook(book: book, chapterIndex: 3, position: 0.5)
        let oldData = try JSONEncoder().encode(shelf)
        let old = try JSONDecoder().decode(NovelLibrary.ShelfBook.self, from: oldData)
        #expect(old.characterOffset == nil)
        #expect(old.position == 0.5)
        shelf.characterOffset = 1350
        shelf.mark(NovelBookmark(chapterIndex: 3, chapterTitle: "第三章", position: 0.5, excerpt: "文字", characterOffset: 1350))
        let restored = try JSONDecoder().decode(NovelLibrary.ShelfBook.self, from: JSONEncoder().encode(shelf))
        #expect(restored.characterOffset == 1350)
        #expect(restored.bookmarks.first?.characterOffset == 1350)
    }
}

@Test func folderImportListsSourcesWithoutDependingOnTheirUTI() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    for name in ["suduguu.json", "SOURCE.JSON", "books.xbs", "ignore.txt", ".hidden.json"] {
        try Data("{}".utf8).write(to: directory.appendingPathComponent(name))
    }
    try FileManager.default.createDirectory(at: directory.appendingPathComponent("书源"), withIntermediateDirectories: true)
    let entries = try ImportDirectory.entries(at: directory)
    #expect(Set(entries.map { $0.url.lastPathComponent }) == ["suduguu.json", "SOURCE.JSON", "books.xbs", "书源"])
    #expect(entries.first?.isDirectory == true)
    let selected = try #require(entries.first { $0.url.lastPathComponent == "suduguu.json" })
    #expect(try ImportedFile.read(selected.url, extensions: ["json", "xbs"], limit: 1024) == Data("{}".utf8))
}
