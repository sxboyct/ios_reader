import SwiftUI
import TVCore

@MainActor @Observable
final class ReaderLibrary {
    private let shelfWrites = DispatchQueue(label: "reader.shelf-writes", qos: .utility)
    private let directory: URL
    var shelf: [NovelLibrary.ShelfBook]
    var searchHistory: ReaderSearchHistory
    var sources: [NovelSource] = []
    var lists: [NovelSourceList] = []
    private var attemptedCovers: Set<String> = []
    init(directory: URL = NovelLibrary.root) {
        self.directory = directory
        shelf = (try? Data(contentsOf: directory.appendingPathComponent("shelf.json")))
            .flatMap { try? JSONDecoder().decode([NovelLibrary.ShelfBook].self, from: $0) } ?? []
        let history = (try? Data(contentsOf: directory.appendingPathComponent("search-history.json")))
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        searchHistory = ReaderSearchHistory(history)
    }
    func reloadSources() { sources = NovelSources.shared.all; lists = NovelSources.shared.lists }
    func entry(_ book: NovelBook) -> NovelLibrary.ShelfBook? { shelf.first { $0.id == book.match } }
    func save(_ entry: NovelLibrary.ShelfBook) {
        shelf.removeAll { $0.id == entry.id }; shelf.insert(entry, at: 0)
        persistShelf()
    }
    func remove(_ book: NovelBook) {
        shelf.removeAll { $0.id == book.match }; persistShelf()
    }
    /// Progress alone never adds a book the reader has not collected.
    @discardableResult func recordProgress(_ entry: NovelLibrary.ShelfBook) -> Bool {
        guard self.entry(entry.book) != nil else { return false }
        save(entry)
        return true
    }
    func updateDetails(_ book: NovelBook, chapterCount: Int) {
        guard let at = shelf.firstIndex(where: { $0.id == book.match }) else { return }
        shelf[at].book = book; shelf[at].chapterCount = chapterCount
        persistShelf()
    }
    func refreshMissingCovers() async {
        await NovelSources.shared.loaded()
        for entry in shelf where entry.book.cover.isEmpty && !attemptedCovers.contains(entry.book.id) {
            guard !Task.isCancelled else { return }
            attemptedCovers.insert(entry.book.id)
            let details = try? await NovelBooks.shared.details(entry.book)
            if Task.isCancelled { attemptedCovers.remove(entry.book.id); return }
            if let details,
               let at = shelf.firstIndex(where: { $0.book.id == entry.book.id }) {
                // Preserve the saved identity and reading position even if metadata changed upstream.
                if !details.cover.isEmpty { shelf[at].book.cover = details.cover }
                if !details.wordCount.isEmpty { shelf[at].book.wordCount = details.wordCount }
                persistShelf()
            }
        }
    }
    private func persistShelf() {
        let snapshot = shelf
        let directory = directory
        shelfWrites.async {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: directory.appendingPathComponent("shelf.json"), options: .atomic)
            }
        }
    }
    func flushShelf() { shelfWrites.sync {} }
    func recordSearch(_ keyword: String) {
        searchHistory.record(keyword)
        persistHistory()
    }
    func removeSearch(_ keyword: String) {
        searchHistory.remove(keyword)
        persistHistory()
    }
    func clearSearchHistory() {
        searchHistory.clear()
        persistHistory()
    }
    private func persistHistory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(searchHistory.entries) {
            try? data.write(to: directory.appendingPathComponent("search-history.json"), options: .atomic)
        }
    }
}

