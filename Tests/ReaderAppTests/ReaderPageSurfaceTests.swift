import UIKit
import Testing
import TVCore

@MainActor @Suite(.serialized) struct ReaderPageSurfaceTests {
    @Test func scrollingRestoresTheEndOfALongChapter() async throws {
        let viewport = ReaderViewport(safeAreaSize: CGSize(width: 320, height: 500), safeAreaInsets: .zero)
        let layout = ReaderTextLayout(content: NovelContent(title: "滚动测试", paragraphs: [
            String(repeating: "长段落在滚动模式中也需要完整显示。", count: 250), "章节结尾标记"
        ]), size: viewport.contentFrame.size, fontName: "", fontSize: 20, lineSpacing: 8, color: .black)
        let renderer = ReaderPageRenderer(layout: layout, viewport: viewport, color: .white,
            image: nil, opacity: 0, scale: 1)
        let controller = ReaderPageSurface.Controller()
        controller.configure(ReaderPageSurface(layout: layout, renderer: renderer, viewport: viewport,
            style: .scroll, offset: layout.text.length - 1, background: .white, backgroundImage: nil,
            backgroundOpacity: 0, animated: true, tapFraction: 0.3, tapsEnabled: true,
            slideForwardRight: true, moved: { _, _ in }, boundary: { _ in }, center: {}))
        controller.view.frame = CGRect(origin: .zero, size: viewport.size)
        controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        defer { controller.invalidate() }
        let text = try #require(controller.view.subviews.compactMap { $0 as? UITextView }.first)
        #expect(text.attributedText.string == layout.text.string)
        #expect(text.contentSize.height > text.bounds.height)
        let bottom = text.contentSize.height - text.bounds.height
        #expect(abs(text.contentOffset.y - bottom) <= 1)
    }

    @Test(arguments: [ReaderTurnStyle.slide, .cover, .vertical, .fade, .curl])
    func animatedTurnsKeepCompletePagesAndCommitOnce(style: ReaderTurnStyle) async throws {
        let viewport = ReaderViewport(safeAreaSize: CGSize(width: 320, height: 500),
            safeAreaInsets: UIEdgeInsets(top: 20, left: 0, bottom: 20, right: 0))
        let layout = ReaderTextLayout(content: NovelContent(title: "翻页测试", paragraphs: [
            String(repeating: "每一页必须连续显示，前进和后退都不能跳页。", count: 180)
        ]), size: viewport.contentFrame.size, fontName: "", fontSize: 20, lineSpacing: 8, color: .black)
        let renderer = ReaderPageRenderer(layout: layout, viewport: viewport, color: .white,
            image: nil, opacity: 0, scale: 1)
        await renderer.prepareAsync(around: 0)
        var moves: [Int] = []
        var boundaries: [Bool] = []
        let controller = ReaderPageSurface.Controller()
        let surface = ReaderPageSurface(layout: layout, renderer: renderer, viewport: viewport,
            style: style, offset: 0, background: .white, backgroundImage: nil, backgroundOpacity: 0,
            animated: true, tapFraction: 0.3, tapsEnabled: true, slideForwardRight: true,
            moved: { _, page in moves.append(page) }, boundary: { boundaries.append($0) }, center: {})
        controller.configure(surface)
        let window = UIWindow(frame: CGRect(origin: .zero, size: viewport.size))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        defer { controller.invalidate(); window.isHidden = true }
        for expected in [1, 2, 3, 2, 1, 0] {
            let previous = moves.last ?? 0
            _ = controller.accessibilityScroll(expected > previous ? .next : .previous)
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            for _ in 0..<100 {
                if moves.last == expected { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(moves.last == expected)
            let visible: ReaderPageSurface.PageCanvas?
            if let pager = controller.children.first as? UIPageViewController {
                visible = pager.viewControllers?.first?.view as? ReaderPageSurface.PageCanvas
            } else {
                visible = controller.view.subviews.compactMap { $0 as? ReaderPageSurface.PageCanvas }.last
            }
            let canvas = try #require(visible)
            #expect(canvas.image != nil)
            #expect(canvas.transform == .identity)
            #expect(canvas.accessibilityLabel == layout.text.attributedSubstring(from: layout.pageRanges[expected]).string)
            if style != .curl { #expect(canvas.frame == controller.view.bounds) }
        }
        #expect(moves == [1, 2, 3, 2, 1, 0])
        #expect(boundaries.isEmpty)
    }
}
