import Foundation
import UIKit

public enum ReaderTurnStyle: String, CaseIterable, Identifiable, Sendable {
    case slide, curl, cover, fade, vertical, scroll
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .slide: "平移"
        case .curl: "仿真"
        case .cover: "覆盖"
        case .fade: "渐隐"
        case .vertical: "上下"
        case .scroll: "滚动"
        }
    }
}

/// TextKit uses the same glyph layout to measure and draw, including a paragraph longer than a screen.
@MainActor public final class ReaderTextLayout {
    public let text: NSAttributedString
    public let size: CGSize
    public let paragraphStarts: [Int]
    public let pageStarts: [Int]
    public let pageRanges: [NSRange]
    public var isComplete: Bool { pageRanges.last.map { NSMaxRange($0) == text.length } ?? (text.length == 0) }
    private let storage: NSTextStorage
    private let manager: NSLayoutManager
    private let containers: [NSTextContainer]

    public init(content: NovelContent, size: CGSize, fontName: String, fontSize: Double, lineSpacing: Double, color: UIColor) {
        let pageSize = CGSize(width: max(80, size.width), height: max(100, size.height))
        self.size = pageSize
        let font = UIFont(name: fontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.paragraphSpacing = fontSize * 0.7
        paragraph.firstLineHeadIndent = fontSize * 2
        paragraph.alignment = .justified
        paragraph.lineBreakMode = .byWordWrapping
        let heading = NSMutableParagraphStyle()
        heading.paragraphSpacing = fontSize
        let output = NSMutableAttributedString(string: content.title + "\n", attributes: [
            .font: UIFont(name: fontName, size: fontSize * 1.2) ?? UIFont.systemFont(ofSize: fontSize * 1.2, weight: .semibold),
            .foregroundColor: color, .paragraphStyle: heading
        ])
        var starts: [Int] = []
        for (index, line) in content.paragraphs.enumerated() {
            starts.append(output.length)
            let suffix = index == content.paragraphs.count - 1 ? "" : "\n"
            output.append(NSAttributedString(string: line.trimmingCharacters(in: .whitespacesAndNewlines) + suffix,
                attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]))
        }
        text = output; paragraphStarts = starts
        let textStorage = NSTextStorage(attributedString: output)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        var boxes: [NSTextContainer] = [], ranges: [NSRange] = [], pageStarts: [Int] = []
        var end = 0
        while end < layoutManager.numberOfGlyphs {
            let box = NSTextContainer(size: pageSize)
            box.lineFragmentPadding = 0
            layoutManager.addTextContainer(box)
            let glyphs = layoutManager.glyphRange(for: box)
            guard glyphs.length > 0 else { layoutManager.removeTextContainer(at: boxes.count); break }
            let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            boxes.append(box); ranges.append(characters); pageStarts.append(characters.location)
            end = NSMaxRange(glyphs)
        }
        storage = textStorage; manager = layoutManager
        containers = boxes; pageRanges = ranges; self.pageStarts = pageStarts
    }
    public var count: Int { containers.count }
    public func page(containing offset: Int) -> Int { pageStarts.lastIndex { $0 <= offset } ?? 0 }
    public func offset(page: Int) -> Int { pageStarts.indices.contains(page) ? pageStarts[page] : 0 }
    public func offset(paragraph: Int) -> Int { paragraphStarts.indices.contains(paragraph) ? paragraphStarts[paragraph] : 0 }
    public func paragraph(at offset: Int) -> Int { paragraphStarts.lastIndex { $0 <= offset } ?? 0 }
    public func draw(page: Int, at origin: CGPoint = .zero) {
        guard containers.indices.contains(page) else { return }
        let range = manager.glyphRange(for: containers[page])
        manager.drawBackground(forGlyphRange: range, at: origin)
        manager.drawGlyphs(forGlyphRange: range, at: origin)
    }
}
