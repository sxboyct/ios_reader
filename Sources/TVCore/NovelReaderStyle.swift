import Foundation

/// Simplified and Traditional Chinese in the novel reader (#1007): a chapter is shown in the script the reader picks,
/// converted once when it arrives, never while pages turn. ICU's transforms convert phrases (头发 → 頭髮, 乾杯 → 干杯),
/// about 2 ms for a 10,000-character chapter.
public enum NovelScript: String, CaseIterable, Sendable {
    case original = "", traditional, simplified

    private var transform: StringTransform? {
        switch self {
        case .original: nil
        case .traditional: StringTransform("Hans-Hant")
        case .simplified: StringTransform("Hant-Hans")
        }
    }

    public func convert(_ text: String) -> String {
        guard let transform else { return text }
        return text.applyingTransform(transform, reverse: false) ?? text
    }

    /// Many short texts in one pass (a chapter's paragraphs, a book's chapter titles): one transform call is far cheaper
    /// than thousands. A text holding the separator is converted on its own.
    public func convert(_ texts: [String]) -> [String] {
        guard transform != nil, !texts.isEmpty else { return texts }
        let separator: Character = "\u{1E}"
        guard !texts.contains(where: { $0.contains(separator) }) else { return texts.map(convert) }
        let parts = convert(texts.joined(separator: String(separator))).split(separator: separator, omittingEmptySubsequences: false)
        return parts.count == texts.count ? parts.map(String.init) : texts.map(convert)
    }

    public func convert(_ content: NovelContent) -> NovelContent {
        guard transform != nil else { return content }
        let converted = convert([content.title] + content.paragraphs)
        return NovelContent(title: converted[0], paragraphs: Array(converted.dropFirst()))
    }
}

