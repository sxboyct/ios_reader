import Foundation
import Testing
@testable import TVCore

struct ReaderSearchHistoryTests {
    @Test func normalizesAndMovesRepeatedSearchToFront() {
        var history = ReaderSearchHistory()
        history.record("  三体\n")
        history.record("Dune")
        history.record(" dune ")
        history.record(" \n ")
        #expect(history.entries == ["dune", "三体"])
        history.record("三体")
        #expect(history.entries == ["三体", "dune"])
    }

    @Test func boundsAndRestoresSavedHistory() throws {
        var history = ReaderSearchHistory()
        for index in 0..<40 { history.record("书名\(index)") }
        #expect(history.entries.count == ReaderSearchHistory.limit)
        #expect(history.entries.first == "书名39")
        #expect(history.entries.last == "书名10")
        let data = try JSONEncoder().encode(history.entries)
        let restored = ReaderSearchHistory(try JSONDecoder().decode([String].self, from: data))
        #expect(restored.entries == history.entries)
    }

    @Test func removesClearsAndSanitizesLegacyValues() {
        var history = ReaderSearchHistory(["三体", " Dune ", "三体", "", "dune"])
        #expect(history.entries == ["三体", "Dune"])
        history.remove("DUNE")
        #expect(history.entries == ["三体"])
        history.clear()
        #expect(history.entries.isEmpty)
    }
}
