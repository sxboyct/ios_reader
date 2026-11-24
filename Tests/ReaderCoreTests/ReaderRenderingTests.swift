import UIKit
import CoreText
import Testing
@testable import TVCore

@MainActor struct ReaderRenderingTests {
    @Test func fullScreenSurfaceKeepsTextInsideSafeArea() {
        let viewport = ReaderViewport(safeAreaSize: CGSize(width: 393, height: 759),
            safeAreaInsets: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0))
        #expect(viewport.size == CGSize(width: 393, height: 852))
        #expect(viewport.origin == CGPoint(x: 0, y: -59))
        #expect(viewport.contentFrame == CGRect(x: 24, y: 73, width: 345, height: 731))
        let landscape = ReaderViewport(safeAreaSize: CGSize(width: 734, height: 372),
            safeAreaInsets: UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 59))
        #expect(landscape.size == CGSize(width: 852, height: 393))
        #expect(landscape.contentFrame.minX == 83)
        #expect(landscape.contentFrame.maxX == 769)
    }

    @Test func fullScreenPagesReusePreparedImagesAndBoundMemory() throws {
        let viewport = ReaderViewport(safeAreaSize: CGSize(width: 320, height: 500),
            safeAreaInsets: UIEdgeInsets(top: 20, left: 0, bottom: 20, right: 0))
        let content = NovelContent(title: "缓存测试", paragraphs: [String(repeating: "每一页都有完整背景和正文。", count: 600)])
        let layout = ReaderTextLayout(content: content, size: viewport.contentFrame.size,
            fontName: "", fontSize: 20, lineSpacing: 8, color: .black)
        let renderer = ReaderPageRenderer(layout: layout, viewport: viewport, color: .white,
            image: nil, opacity: 0.3, scale: 1)
        renderer.prepare(around: 0)
        #expect(renderer.cachedPages == [0, 1])
        let next = try #require(renderer.image(page: 1))
        #expect(next.size == viewport.size)
        #expect(next === renderer.image(page: 1))
        for page in 1..<layout.count {
            renderer.prepare(around: page)
            #expect(renderer.cachedPages.count <= 3)
            #expect(renderer.cachedPages.contains(page))
            #expect(renderer.cachedPages.allSatisfy { abs($0 - page) <= 1 })
        }
        #expect(renderer.image(page: -1) == nil)
        #expect(renderer.image(page: layout.count) == nil)
        #expect(renderer.background.size == viewport.size)
    }

    @Test func imageBackgroundCoversSafeAreasAndPageMargins() throws {
        let viewport = ReaderViewport(safeAreaSize: CGSize(width: 160, height: 260),
            safeAreaInsets: UIEdgeInsets(top: 20, left: 0, bottom: 20, right: 0))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
        }
        let layout = ReaderTextLayout(content: NovelContent(title: "测试", paragraphs: ["正文"]),
            size: viewport.contentFrame.size, fontName: "", fontSize: 20, lineSpacing: 8, color: .black)
        let renderer = ReaderPageRenderer(layout: layout, viewport: viewport, color: .white,
            image: photo, opacity: 1, scale: 1)
        let image = try #require(renderer.image(page: 0)?.cgImage)
        for point in [CGPoint(x: 0, y: 0), CGPoint(x: 159, y: 0), CGPoint(x: 0, y: 299), CGPoint(x: 159, y: 299)] {
            var pixel: [UInt8] = [0, 0, 0, 0]
            pixel.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                    bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
                context.translateBy(x: -point.x, y: -point.y)
                context.draw(image, in: CGRect(origin: .zero, size: viewport.size))
            }
            #expect(pixel == [255, 0, 0, 255])
        }
    }

    @Test func asynchronousPreparationUsesAWorkerAndKeepsPageImagesComplete() async throws {
        let viewport = ReaderViewport(safeAreaSize: CGSize(width: 272.5, height: 401.5),
            safeAreaInsets: UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0))
        let content = NovelContent(title: "新章节第一页", paragraphs: [
            String(repeating: "一段文字跨页后应当连续显示，不能在第二页截断。😀 e\u{301} ", count: 55),
            "", "章节最后一句也必须完整显示。"
        ])
        let (layout, renderer) = await Task.detached {
            let layout = ReaderTextLayout(content: content, size: viewport.contentFrame.size,
                fontName: "", fontSize: 20, lineSpacing: 8, color: .black)
            let renderer = ReaderPageRenderer(layout: layout, viewport: viewport, color: .white,
                image: nil, opacity: 0, scale: 1)
            renderer.prepare(around: 0)
            return (layout, renderer)
        }.value
        let onMainThread = await layout.executor.perform { Thread.isMainThread }
        #expect(!onMainThread)
        #expect(layout.isComplete)
        let ranges = layout.pageRanges
        for page in Array(0..<layout.count) + [0, layout.count - 1, 1] {
            await renderer.prepareAsync(around: page)
            let actual = try #require(renderer.cachedImage(page: page)?.cgImage)
            let expected = try #require(referencePage(layout: layout, viewport: viewport, page: page).cgImage)
            #expect(pixels(actual) == pixels(expected))
            #expect(renderer.cachedPages.count <= 3)
            #expect(renderer.cachedPages.contains(page))
            #expect(layout.pageRanges == ranges)
        }
        let prepared = await renderer.preparePage(0)
        let retained = try #require(prepared)
        await renderer.prepareAsync(around: layout.count - 1)
        #expect(renderer.cachedImage(page: 0) == nil)
        #expect(retained.image.size == viewport.size)
        let firstRenderer = renderer
        let secondLayout = ReaderTextLayout(content: NovelContent(title: "下一章", paragraphs: ["独立的新章节内容"]),
            size: viewport.contentFrame.size, fontName: "", fontSize: 20, lineSpacing: 8, color: .black)
        let secondRenderer = ReaderPageRenderer(layout: secondLayout, viewport: viewport, color: .white,
            image: nil, opacity: 0, scale: 1)
        await secondRenderer.prepareAsync(around: 0)
        await firstRenderer.preparePage(0)
        let first = try #require(firstRenderer.cachedImage(page: 0)?.cgImage)
        let second = try #require(secondRenderer.cachedImage(page: 0)?.cgImage)
        #expect(pixels(first) != pixels(second))
    }

    private func referencePage(layout: ReaderTextLayout, viewport: ReaderViewport, page: Int) -> UIImage {
        layout.executor.sync {
            let framesetter = CTFramesetterCreateWithAttributedString(layout.text as CFAttributedString)
            let path = CGPath(rect: CGRect(origin: .zero, size: layout.size), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter,
                CFRange(location: layout.pageRanges[page].location, length: 0), path, nil)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1; format.opaque = true
            return UIGraphicsImageRenderer(size: viewport.size, format: format).image { context in
                UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: viewport.size))
                context.cgContext.clip(to: viewport.contentFrame)
                context.cgContext.textMatrix = .identity
                context.cgContext.translateBy(x: viewport.contentFrame.minX,
                    y: viewport.contentFrame.minY + layout.size.height)
                context.cgContext.scaleBy(x: 1, y: -1)
                CTFrameDraw(frame, context.cgContext)
            }
        }
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}
