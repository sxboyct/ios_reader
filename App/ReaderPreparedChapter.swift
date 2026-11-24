import UIKit
import TVCore

struct ReaderRenderConfiguration: Equatable, @unchecked Sendable {
    let viewport: ReaderViewport
    let script: String
    let fontName: String
    let fontSize: Double
    let lineSpacing: Double
    let ink: UIColor
    let background: UIColor
    let image: UIImage?
    let opacity: Double
    let scale: CGFloat

    static func == (left: Self, right: Self) -> Bool {
        left.viewport == right.viewport && left.script == right.script && left.fontName == right.fontName
            && left.fontSize == right.fontSize && left.lineSpacing == right.lineSpacing
            && left.ink.isEqual(right.ink) && left.background.isEqual(right.background)
            && left.image === right.image && left.opacity == right.opacity && left.scale == right.scale
    }
}

struct ReaderPreparedChapter: Sendable {
    let index: Int
    let content: NovelContent
    let configuration: ReaderRenderConfiguration
    let layout: ReaderTextLayout
    let renderer: ReaderPageRenderer

    func offset(position: Double, character: Int?) -> Int {
        let requested = character ?? layout.offset(paragraph: Int(position * Double(max(0, content.paragraphs.count - 1))))
        return min(max(0, requested), max(0, layout.text.length - 1))
    }

    static func build(index: Int, content: NovelContent, configuration: ReaderRenderConfiguration,
                      position: Double = 0, character: Int? = nil, priority: TaskPriority = .userInitiated) async throws -> Self {
        let task = Task.detached(priority: priority) {
            try Task.checkCancellation()
            let converted = (NovelScript(rawValue: configuration.script) ?? .original).convert(content)
            let layout = ReaderTextLayout(content: converted, size: configuration.viewport.contentFrame.size,
                fontName: configuration.fontName, fontSize: configuration.fontSize,
                lineSpacing: configuration.lineSpacing, color: configuration.ink)
            guard layout.count > 0, layout.isComplete else { throw PreparationError.incomplete }
            try Task.checkCancellation()
            let renderer = ReaderPageRenderer(layout: layout, viewport: configuration.viewport,
                color: configuration.background, image: configuration.image, opacity: configuration.opacity,
                scale: configuration.scale)
            let prepared = Self(index: index, content: content, configuration: configuration, layout: layout, renderer: renderer)
            renderer.prepare(around: layout.page(containing: prepared.offset(position: position, character: character)))
            try Task.checkCancellation()
            return prepared
        }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }

    private enum PreparationError: LocalizedError {
        case incomplete
        var errorDescription: String? { "当前章节未能完整分页，请调整字号后重试。" }
    }
}
