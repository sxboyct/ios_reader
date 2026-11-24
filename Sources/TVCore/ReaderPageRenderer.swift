import UIKit

public final class ReaderPageRenderer: @unchecked Sendable {
    public struct RenderedPage: @unchecked Sendable {
        public let image: UIImage
    }

    public let background: UIImage
    private let layout: ReaderTextLayout
    public let viewport: ReaderViewport
    private let scale: CGFloat
    private let cacheLock = NSLock()
    private var pages: [Int: UIImage] = [:]
    public var cachedPages: Set<Int> { cacheLock.withLock { Set(pages.keys) } }

    public init(layout: ReaderTextLayout, viewport: ReaderViewport, color: UIColor,
                image: UIImage?, opacity: Double, scale: CGFloat = 0) {
        self.layout = layout; self.viewport = viewport
        self.scale = scale
        background = layout.executor.sync {
            let format = UIGraphicsImageRendererFormat()
            format.opaque = true
            if scale > 0 { format.scale = scale }
            return UIGraphicsImageRenderer(size: viewport.size, format: format).image { context in
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
    }

    public func image(page: Int) -> UIImage? {
        layout.executor.sync { render(page: page) }
    }

    public func cachedImage(page: Int) -> UIImage? {
        cacheLock.withLock { pages[page] }
    }

    private func render(page: Int) -> UIImage? {
        guard layout.pageRanges.indices.contains(page) else { return nil }
        if let image = cachedImage(page: page) { return image }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        if scale > 0 { format.scale = scale }
        let image = UIGraphicsImageRenderer(size: viewport.size, format: format).image { context in
            background.draw(at: .zero)
            context.cgContext.clip(to: viewport.contentFrame)
            layout.draw(page: page, at: viewport.contentFrame.origin)
        }
        cacheLock.withLock {
            if pages.count >= 3, let farthest = pages.keys.max(by: { abs($0 - page) < abs($1 - page) }) {
                pages.removeValue(forKey: farthest)
            }
            pages[page] = image
        }
        return image
    }

    public func prepare(around page: Int) {
        layout.executor.sync {
            cacheLock.withLock { pages = pages.filter { abs($0.key - page) <= 1 } }
            _ = render(page: page)
            for index in [page + 1, page - 1] { _ = render(page: index) }
        }
    }

    public func prepareAsync(around page: Int) async {
        await layout.executor.perform { self.prepare(around: page) }
    }

    @discardableResult public func preparePage(_ page: Int) async -> RenderedPage? {
        await layout.executor.perform { self.render(page: page).map { RenderedPage(image: $0) } }
    }
}
