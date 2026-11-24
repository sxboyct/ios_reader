import Foundation
import UIKit
import CoreText

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

public final class ReaderTextLayout: @unchecked Sendable {
    public let text: NSAttributedString
    public let size: CGSize
    public let paragraphStarts: [Int]
    public let pageStarts: [Int]
    public let pageRanges: [NSRange]
    public var isComplete: Bool {
        var end = 0
        for range in pageRanges {
            guard range.location == end, range.length > 0 else { return false }
            end = NSMaxRange(range)
        }
        return end == text.length
    }
    let executor: ReaderRenderExecutor
    private let frames: [CTFrame]

    public init(content: NovelContent, size: CGSize, fontName: String, fontSize: Double, lineSpacing: Double, color: UIColor) {
        let executor = ReaderRenderExecutor()
        self.executor = executor
        let pageSize = CGSize(width: max(80, floor(size.width)), height: max(100, floor(size.height)))
        self.size = pageSize
        let prepared = executor.sync {
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
            let immutable = NSAttributedString(attributedString: output)
            let framesetter = CTFramesetterCreateWithAttributedString(immutable as CFAttributedString)
            let path = CGPath(rect: CGRect(origin: .zero, size: pageSize), transform: nil)
            var frames: [CTFrame] = [], ranges: [NSRange] = []
            var end = 0
            while end < immutable.length {
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: end, length: 0), path, nil)
                let visible = CTFrameGetVisibleStringRange(frame)
                guard visible.location == end, visible.length > 0 else { break }
                frames.append(frame)
                ranges.append(NSRange(location: visible.location, length: visible.length))
                end += visible.length
            }
            return (immutable, starts, frames, ranges)
        }
        text = prepared.0; paragraphStarts = prepared.1
        frames = prepared.2; pageRanges = prepared.3
        pageStarts = prepared.3.map(\.location)
    }
    public var count: Int { pageRanges.count }
    public func page(containing offset: Int) -> Int { pageStarts.lastIndex { $0 <= offset } ?? 0 }
    public func offset(page: Int) -> Int { pageStarts.indices.contains(page) ? pageStarts[page] : 0 }
    public func offset(paragraph: Int) -> Int { paragraphStarts.indices.contains(paragraph) ? paragraphStarts[paragraph] : 0 }
    public func paragraph(at offset: Int) -> Int { paragraphStarts.lastIndex { $0 <= offset } ?? 0 }
    public func draw(page: Int, at origin: CGPoint = .zero) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        executor.sync {
            guard frames.indices.contains(page) else { return }
            context.saveGState()
            context.textMatrix = .identity
            context.translateBy(x: origin.x, y: origin.y + size.height)
            context.scaleBy(x: 1, y: -1)
            CTFrameDraw(frames[page], context)
            context.restoreGState()
        }
    }
}
