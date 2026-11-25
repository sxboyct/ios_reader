import UIKit
import Testing
import TVCore

@MainActor @Suite(.serialized) struct ReaderSlideSurfaceTests {
    @Test func missingPreviewDoesNotExposeBlankSpaceAndPositionChangeCancelsDrag() async throws {
        let viewport = ReaderViewport(safeAreaSize: CGSize(width: 280, height: 360), safeAreaInsets: .zero)
        let layout = ReaderTextLayout(content: NovelContent(title: "位置变更",
            paragraphs: [String(repeating: "拖动时不能露出空白或覆盖目录跳转的位置。", count: 60)]),
            size: viewport.contentFrame.size, fontName: "", fontSize: 20, lineSpacing: 8, color: .black)
        let renderer = ReaderPageRenderer(layout: layout, viewport: viewport, color: .white,
            image: nil, opacity: 0, scale: 1)
        await renderer.preparePage(0)
        var commits: [Int] = []
        let controller = ReaderPageSurface.Controller()
        func surface(page: Int) -> ReaderPageSurface {
            ReaderPageSurface(layout: layout, renderer: renderer, viewport: viewport, style: .slide,
                offset: layout.offset(page: page), background: .white, backgroundImage: nil,
                backgroundOpacity: 0, animated: true, tapFraction: 0.3, tapsEnabled: true,
                slideForwardRight: true, moved: { _, page in commits.append(page) }, boundary: { _ in }, center: {})
        }
        controller.configure(surface(page: 0))
        let window = UIWindow(frame: CGRect(origin: .zero, size: viewport.size))
        window.rootViewController = controller; window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        defer { controller.invalidate(); window.isHidden = true }
        #expect(renderer.cachedImage(page: 1) == nil)
        let source = try #require(controller.view.subviews.compactMap { $0 as? ReaderPageSurface.PageCanvas }.last)
        controller.slideChanged(translation: 12, velocity: 0, state: .began)
        controller.slideChanged(translation: 150, velocity: 0, state: .changed)
        #expect(source.transform == .identity)
        #expect(source.frame == controller.view.bounds)
        #expect(controller.view.subviews.compactMap { $0 as? ReaderPageSurface.PageCanvas }.count == 1)
        await renderer.prepareAsync(around: 0)
        controller.slideChanged(translation: 65, velocity: 0, state: .changed)
        controller.slideChanged(translation: 65, velocity: 0, state: .ended)
        controller.configure(surface(page: 3))
        try await Task.sleep(for: .milliseconds(350))
        #expect(commits.isEmpty)
        let selected = try #require(controller.view.subviews.compactMap { $0 as? ReaderPageSurface.PageCanvas }.last)
        #expect(selected.accessibilityLabel == layout.text.attributedSubstring(from: layout.pageRanges[3]).string)
        #expect(selected.image != nil)
    }

    @Test(arguments: [true, false])
    func dragsVisitEveryPageExactlyOnceInBothReadingDirections(forwardRight: Bool) async throws {
        let viewport = ReaderViewport(safeAreaSize: CGSize(width: 280, height: 360), safeAreaInsets: .zero)
        let layout = ReaderTextLayout(content: NovelContent(title: "连续平移测试", paragraphs:
            (0..<24).map { "段落\($0)：这一段的文字在前后翻页时都必须连续显示。" }),
            size: viewport.contentFrame.size, fontName: "", fontSize: 20, lineSpacing: 8, color: .black)
        let renderer = ReaderPageRenderer(layout: layout, viewport: viewport, color: .white,
            image: nil, opacity: 0, scale: 1)
        await renderer.prepareAsync(around: 0)
        var commits: [Int] = []
        var boundaries = 0
        let controller = ReaderPageSurface.Controller()
        var surface = ReaderPageSurface(layout: layout, renderer: renderer, viewport: viewport, style: .slide,
            offset: 0, background: .white, backgroundImage: nil, backgroundOpacity: 0, animated: true,
            tapFraction: 0.3, tapsEnabled: true, slideForwardRight: forwardRight,
            moved: { _, page in commits.append(page) }, boundary: { _ in boundaries += 1 }, center: {})
        controller.configure(surface)
        let window = UIWindow(frame: CGRect(origin: .zero, size: viewport.size))
        window.rootViewController = controller; window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        defer { controller.invalidate(); window.isHidden = true }
        func visible() throws -> ReaderPageSurface.PageCanvas {
            try #require(controller.view.subviews.compactMap { $0 as? ReaderPageSurface.PageCanvas }.last)
        }
        let firstCanvas = try visible()
        var reconstructed = try #require(firstCanvas.accessibilityLabel)
        let sequence = Array(1..<layout.count) + Array((0..<(layout.count - 1)).reversed())
        for target in sequence {
            let source = commits.last ?? 0
            let sign: CGFloat = ((target > source) == forwardRight) ? 1 : -1
            controller.slideChanged(translation: sign * 12, velocity: 0, state: .began)
            controller.slideChanged(translation: -sign * 25, velocity: 0, state: .changed)
            controller.slideChanged(translation: sign * 65, velocity: sign * 500, state: .changed)
            let count = commits.count
            controller.slideChanged(translation: sign * 65, velocity: sign * 500, state: .ended)
            controller.slideChanged(translation: sign * 65, velocity: sign * 500, state: .ended)
            for _ in 0..<150 {
                if commits.count > count { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(commits.count == count + 1)
            #expect(commits.last == target)
            let page = try visible()
            let expected = layout.text.attributedSubstring(from: layout.pageRanges[target]).string
            #expect(page.accessibilityLabel == expected)
            #expect(page.image != nil)
            #expect(page.transform == .identity)
            #expect(page.frame == controller.view.bounds)
            if target > source { reconstructed += try #require(page.accessibilityLabel) }
            surface = ReaderPageSurface(layout: layout, renderer: renderer, viewport: viewport, style: .slide,
                offset: layout.offset(page: target), background: .white, backgroundImage: nil,
                backgroundOpacity: 0, animated: true, tapFraction: 0.3, tapsEnabled: true,
                slideForwardRight: forwardRight, moved: { _, page in commits.append(page) },
                boundary: { _ in boundaries += 1 }, center: {})
            controller.configure(surface)
        }
        #expect(commits == sequence)
        #expect(boundaries == 0)
        #expect(reconstructed == layout.text.string)
    }

    @Test func interruptedSettleRetainsSourceAndEvictedPreviewKeepsItsImage() async throws {
        let viewport = ReaderViewport(safeAreaSize: CGSize(width: 280, height: 360), safeAreaInsets: .zero)
        let layout = ReaderTextLayout(content: NovelContent(title: "中断与缓存测试",
            paragraphs: [String(repeating: "任何翻页都不能提交空白页面。", count: 80)]),
            size: viewport.contentFrame.size, fontName: "", fontSize: 20, lineSpacing: 8, color: .black)
        let renderer = ReaderPageRenderer(layout: layout, viewport: viewport, color: .white,
            image: nil, opacity: 0, scale: 1)
        await renderer.prepareAsync(around: 0)
        var commits: [Int] = []
        let controller = ReaderPageSurface.Controller()
        controller.configure(ReaderPageSurface(layout: layout, renderer: renderer, viewport: viewport, style: .slide,
            offset: 0, background: .white, backgroundImage: nil, backgroundOpacity: 0, animated: true,
            tapFraction: 0.3, tapsEnabled: true, slideForwardRight: true,
            moved: { _, page in commits.append(page) }, boundary: { _ in }, center: {}))
        let window = UIWindow(frame: CGRect(origin: .zero, size: viewport.size))
        window.rootViewController = controller; window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        defer { controller.invalidate(); window.isHidden = true }
        let source = try #require(controller.view.subviews.compactMap { $0 as? ReaderPageSurface.PageCanvas }.last)
        controller.slideChanged(translation: 12, velocity: 0, state: .began)
        controller.slideChanged(translation: 65, velocity: 0, state: .changed)
        controller.slideChanged(translation: 65, velocity: 0, state: .ended)
        for page in controller.view.subviews.compactMap({ $0 as? ReaderPageSurface.PageCanvas }) {
            page.layer.removeAllAnimations()
        }
        try await Task.sleep(for: .milliseconds(300))
        #expect(commits.isEmpty)
        #expect(source.superview === controller.view)
        #expect(source.transform == .identity)
        await renderer.prepareAsync(around: layout.count - 1)
        #expect(renderer.cachedImage(page: 1) == nil)
        controller.tap(at: 0.9)
        for _ in 0..<200 {
            if controller.view.subviews.compactMap({ $0 as? ReaderPageSurface.PageCanvas }).count == 2 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(controller.view.subviews.compactMap({ $0 as? ReaderPageSurface.PageCanvas }).count == 2)
        for page in controller.view.subviews.compactMap({ $0 as? ReaderPageSurface.PageCanvas }) {
            page.layer.removeAllAnimations()
        }
        try await Task.sleep(for: .milliseconds(300))
        #expect(commits.isEmpty)
        #expect(source.superview === controller.view)
        await renderer.prepareAsync(around: 0)
        controller.slideChanged(translation: 12, velocity: 0, state: .began)
        controller.slideChanged(translation: 65, velocity: 0, state: .changed)
        let preview = try #require(controller.view.subviews.compactMap { $0 as? ReaderPageSurface.PageCanvas }.last)
        let retained = try #require(preview.image)
        await renderer.prepareAsync(around: layout.count - 1)
        #expect(renderer.cachedImage(page: 1) == nil)
        controller.slideChanged(translation: 65, velocity: 0, state: .ended)
        for _ in 0..<150 {
            if !commits.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(commits == [1])
        #expect(preview.image === retained)
        #expect(preview.accessibilityLabel == layout.text.attributedSubstring(from: layout.pageRanges[1]).string)
        #expect(preview.superview === controller.view)
    }
}
