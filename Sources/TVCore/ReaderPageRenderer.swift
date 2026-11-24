import UIKit

@MainActor public final class ReaderPageRenderer {
    public let background: UIImage
    private let layout: ReaderTextLayout
    private let viewport: ReaderViewport
    private let format: UIGraphicsImageRendererFormat
    private var pages: [Int: UIImage] = [:]
    public var cachedPages: Set<Int> { Set(pages.keys) }

    public init(layout: ReaderTextLayout, viewport: ReaderViewport, color: UIColor,
                image: UIImage?, opacity: Double, scale: CGFloat = 0) {
        self.layout = layout; self.viewport = viewport
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        if scale > 0 { format.scale = scale }
        self.format = format
        background = UIGraphicsImageRenderer(size: viewport.size, format: format).image { context in
            color.setFill(); context.fill(CGRect(origin: .zero, size: viewport.size))
            if let image, image.size.width > 0, image.size.height > 0 {
                let factor = max(viewport.size.width / image.size.width, viewport.size.height / image.size.height)
                let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
                let rect = CGRect(x: (viewport.size.width - size.width) / 2,
                    y: (viewport.size.height - size.height) / 2, width: size.width, height: size.height)
                image.draw(in: rect, blendMode: .normal, alpha: CGFloat(min(1, max(0, opacity))))
            }
        }
    }

    public func image(page: Int) -> UIImage? {
        guard layout.pageRanges.indices.contains(page) else { return nil }
        if let image = pages[page] { return image }
        let image = UIGraphicsImageRenderer(size: viewport.size, format: format).image { context in
            background.draw(at: .zero)
            context.cgContext.clip(to: viewport.contentFrame)
            layout.draw(page: page, at: viewport.contentFrame.origin)
        }
        if pages.count >= 3, let farthest = pages.keys.max(by: { abs($0 - page) < abs($1 - page) }) {
            pages.removeValue(forKey: farthest)
        }
        pages[page] = image
        return image
    }

    public func prepare(around page: Int) {
        pages = pages.filter { abs($0.key - page) <= 1 }
        for index in (page - 1)...(page + 1) { _ = image(page: index) }
    }
}
