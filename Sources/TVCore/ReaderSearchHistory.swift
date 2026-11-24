import Foundation

public struct ReaderSearchHistory: Sendable {
    public static let limit = 30
    public private(set) var entries: [String] = []

    public init(_ saved: [String] = []) {
        for keyword in saved.reversed() { record(keyword) }
    }

    public mutating func record(_ keyword: String) {
        let cleaned = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        remove(cleaned)
        entries.insert(cleaned, at: 0)
        entries = Array(entries.prefix(Self.limit))
    }

    public mutating func remove(_ keyword: String) {
        entries.removeAll { $0.caseInsensitiveCompare(keyword) == .orderedSame }
    }

    public mutating func clear() { entries.removeAll() }
}
