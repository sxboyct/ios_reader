import UIKit
import Testing
import TVCore

@MainActor @Suite(.serialized) struct ReaderPageSurfaceTests {
    @Test(arguments: [ReaderTurnStyle.slide, .curl, .cover])
    func firstPageTurnsBackAndForwardWithoutReloading(style: ReaderTurnStyle) async throws {
        let viewport = ReaderViewport(safeAreaSize: CGSize(width: 320, height: 500), safeAreaInsets: .zero)
        let configuration = ReaderRenderConfiguration(viewport: viewport, script: "", fontName: "",
            fontSize: 20, lineSpacing: 8, appearance: "day", ink: .black, background: .white,
            image: nil, opacity: 0, scale: 1)
        let previous = try await ReaderPreparedChapter.build(index: 0,
            content: NovelContent(title: "上一章", paragraphs: [String(repeating: "上一章末页内容。", count: 130)]),
            configuration: configuration, character: Int.max)
        let current = try await ReaderPreparedChapter.build(index: 1,
            content: NovelContent(title: "当前章", paragraphs: [String(repeating: "本章的第一页和第二页。", count: 130)]),
            configuration: configuration)
        var backward = 0, forward = 0, fallback = 0
        var moves: [Int] = []
        let controller = ReaderPageSurface.Controller()
        func surface(_ chapter: ReaderPreparedChapter, page: Int) -> ReaderPageSurface {
            ReaderPageSurface(layout: chapter.layout, renderer: chapter.renderer, viewport: viewport,
                style: style, offset: chapter.layout.offset(page: page), background: .white,
                backgroundImage: nil, backgroundOpacity: 0, animated: true,
                tapFraction: 0.3, tapsEnabled: true, slideForwardRight: true,
                moved: { _, page in moves.append(page) }, boundary: { _ in fallback += 1 }, center: {},
                nextLayout: chapter.index == 0 ? current.layout : nil,
                nextRenderer: chapter.index == 0 ? current.renderer : nil,
                crossedChapter: { forward += 1 },
                previousLayout: chapter.index == 1 ? previous.layout : nil,
                previousRenderer: chapter.index == 1 ? previous.renderer : nil,
                crossedPreviousChapter: { backward += 1 })
        }
        controller.configure(surface(current, page: 0))
        let window = UIWindow(frame: CGRect(origin: .zero, size: viewport.size))
        window.rootViewController = controller; window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        defer { controller.invalidate(); window.isHidden = true }
        let pager = controller.children.first
        if let pager = pager as? UIPageViewController, let currentHost = pager.viewControllers?.first {
            let preview = try #require(controller.pageViewController(pager, viewControllerBefore: currentHost) as? ReaderPageSurface.PageHost)
            let canvas = try #require(preview.view as? ReaderPageSurface.PageCanvas)
            #expect(canvas.accessibilityLabel == previous.layout.text.attributedSubstring(from: previous.layout.pageRanges.last!).string)
            #expect(canvas.image != nil)
            let returnHost = try #require(controller.pageViewController(pager, viewControllerAfter: preview) as? ReaderPageSurface.PageHost)
            #expect(returnHost.layout === current.layout)
            #expect(returnHost.index == 0)
            controller.pageViewController(pager, willTransitionTo: [preview])
            controller.pageViewController(pager, didFinishAnimating: true,
                previousViewControllers: [currentHost], transitionCompleted: false)
            #expect(backward == 0)
        }
        if style == .slide {
            controller.slideChanged(translation: -16, velocity: 0, state: .began)
            controller.slideChanged(translation: -65, velocity: 0, state: .changed)
            controller.slideChanged(translation: -65, velocity: 0, state: .cancelled)
            try await Task.sleep(for: .milliseconds(300))
            #expect(backward == 0)
        }
        func turn(_ forward: Bool) {
            if style == .slide {
                let delta: CGFloat = forward ? 65 : -65
                controller.slideChanged(translation: delta / 4, velocity: 0, state: .began)
                controller.slideChanged(translation: delta, velocity: 0, state: .changed)
                controller.slideChanged(translation: delta, velocity: 0, state: .ended)
            } else { _ = controller.accessibilityScroll(forward ? .next : .previous) }
        }
        turn(false)
        for _ in 0..<100 {
            if backward == 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(backward == 1)
        #expect(fallback == 0)
        controller.configure(surface(previous, page: previous.layout.count - 1))
        turn(true)
        for _ in 0..<100 {
            if forward == 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(forward == 1)
        controller.configure(surface(current, page: 0))
        turn(true)
        for _ in 0..<100 {
            if moves.last == 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(moves == [1])
        #expect(fallback == 0)
        if style == .curl { #expect(controller.children.first === pager) }
        let visible = (controller.children.first as? UIPageViewController)?.viewControllers?.first?.view
            ?? controller.view.subviews.last
        let canvas = try #require(visible as? ReaderPageSurface.PageCanvas)
        #expect(canvas.accessibilityLabel == current.layout.text.attributedSubstring(from: current.layout.pageRanges[1]).string)
    }
    @Test func menuRemainsAvailableWhileNextChapterLoads() async throws {
        let viewport = ReaderViewport(safeAreaSize: CGSize(width: 320, height: 500), safeAreaInsets: .zero)
        let configuration = ReaderRenderConfiguration(viewport: viewport, script: "", fontName: "",
            fontSize: 20, lineSpacing: 8, appearance: "day", ink: .black, background: .white,
            image: nil, opacity: 0, scale: 1)
        let prepared = try await ReaderPreparedChapter.build(index: 0,
            content: NovelContent(title: "第一章", paragraphs: ["最后一页"]), configuration: configuration)
        var menuTaps = 0, loading = false
        let controller = ReaderPageSurface.Controller()
        let surface = ReaderPageSurface(layout: prepared.layout, renderer: prepared.renderer, viewport: viewport,
            style: .slide, offset: 0, background: .white, backgroundImage: nil, backgroundOpacity: 0,
            animated: true, tapFraction: 0.3, tapsEnabled: true, slideForwardRight: true,
            moved: { _, _ in }, boundary: { _ in }, center: { menuTaps += 1 }, loadNext: {
                loading = true
                try? await Task.sleep(for: .seconds(30))
                return nil
            })
        controller.configure(surface)
        defer { controller.invalidate() }
        _ = controller.accessibilityScroll(.next)
        for _ in 0..<50 {
            if loading { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(loading)
        #expect(controller.gestureRecognizerShouldBegin(UITapGestureRecognizer()))
        #expect(!controller.gestureRecognizerShouldBegin(UIPanGestureRecognizer()))
        controller.tap(at: 0.5)
        #expect(menuTaps == 1)
    }
    @Test(arguments: [ReaderTurnStyle.slide, .cover, .curl])
    func chapterBoundaryContinuesIntoTheSecondPageWithoutRebuilding(style: ReaderTurnStyle) async throws {
        let viewport = ReaderViewport(safeAreaSize: CGSize(width: 320, height: 500), safeAreaInsets: .zero)
        let configuration = ReaderRenderConfiguration(viewport: viewport, script: "", fontName: "",
            fontSize: 20, lineSpacing: 8, appearance: "day", ink: .black, background: .white,
            image: nil, opacity: 0, scale: 1)
        let first = try await ReaderPreparedChapter.build(index: 0,
            content: NovelContent(title: "第一章", paragraphs: ["上一章最后一句"]), configuration: configuration)
        let lengths = [28,43,18,79,36,51,57,44,16,15,120,64,18,58,7,35,47,13,65,46,53,18,
            54,70,43,83,48,55,39,17,61,75,40,43,37,70,71,56,61,52,61,62,39]
        let second = try await ReaderPreparedChapter.build(index: 1,
            content: NovelContent(title: "第187章 分页回归", paragraphs: lengths.map { String(repeating: "文", count: $0) }),
            configuration: configuration)
        var crossed = 0
        var moved: [Int] = []
        var fallback = 0
        let controller = ReaderPageSurface.Controller()
        var surface = ReaderPageSurface(layout: first.layout, renderer: first.renderer, viewport: viewport,
            style: style, offset: 0, background: .white, backgroundImage: nil, backgroundOpacity: 0,
            animated: true, tapFraction: 0.3, tapsEnabled: true, slideForwardRight: true,
            moved: { _, page in moved.append(page) }, boundary: { _ in fallback += 1 }, center: {},
            nextLayout: second.layout, nextRenderer: second.renderer, crossedChapter: { crossed += 1 })
        controller.configure(surface)
        let window = UIWindow(frame: CGRect(origin: .zero, size: viewport.size))
        window.rootViewController = controller; window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        defer { controller.invalidate(); window.isHidden = true }
        let originalPager = controller.children.first
        if style == .slide {
            controller.slideChanged(translation: 12, velocity: 80, state: .began)
            controller.slideChanged(translation: 70, velocity: 80, state: .changed)
            controller.slideChanged(translation: 70, velocity: 80, state: .cancelled)
            try await Task.sleep(for: .milliseconds(300))
            #expect(crossed == 0)
        }
        if style == .slide {
            controller.slideChanged(translation: 12, velocity: 100, state: .began)
            controller.slideChanged(translation: 65, velocity: 100, state: .changed)
            controller.slideChanged(translation: 65, velocity: 100, state: .ended)
        } else { _ = controller.accessibilityScroll(.next) }
        for _ in 0..<100 {
            if crossed == 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(crossed == 1)
        #expect(fallback == 0)
        surface = ReaderPageSurface(layout: second.layout, renderer: second.renderer, viewport: viewport,
            style: style, offset: 0, background: .white, backgroundImage: nil, backgroundOpacity: 0,
            animated: true, tapFraction: 0.3, tapsEnabled: true, slideForwardRight: true,
            moved: { _, page in moved.append(page) }, boundary: { _ in fallback += 1 }, center: {})
        controller.configure(surface)
        if style == .curl { #expect(controller.children.first === originalPager) }
        if style == .slide {
            controller.slideChanged(translation: 12, velocity: 100, state: .began)
            controller.slideChanged(translation: 65, velocity: 100, state: .changed)
            surface.nextLayout = first.layout; surface.nextRenderer = first.renderer
            controller.configure(surface)
            controller.slideChanged(translation: 65, velocity: 100, state: .ended)
        } else { _ = controller.accessibilityScroll(.next) }
        for _ in 0..<100 {
            if moved.last == 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(moved == [1])
        let visible = (controller.children.first as? UIPageViewController)?.viewControllers?.first?.view
            ?? controller.view.subviews.last
        let canvas = try #require(visible as? ReaderPageSurface.PageCanvas)
        #expect(canvas.accessibilityLabel == second.layout.text.attributedSubstring(from: second.layout.pageRanges[1]).string)
        #expect(canvas.image != nil)
        #expect(second.layout.isComplete)
        let reconstructed = second.layout.pageRanges.map { second.layout.text.attributedSubstring(from: $0).string }.joined()
        #expect(reconstructed == second.layout.text.string)
    }

    @Test func unavailableChapterIsPreparedBeforeTheCoverAnimation() async throws {
        let viewport = ReaderViewport(safeAreaSize: CGSize(width: 320, height: 500), safeAreaInsets: .zero)
        let configuration = ReaderRenderConfiguration(viewport: viewport, script: "", fontName: "",
            fontSize: 20, lineSpacing: 8, appearance: "day", ink: .black, background: .white,
            image: nil, opacity: 0, scale: 1)
        let first = try await ReaderPreparedChapter.build(index: 0,
            content: NovelContent(title: "第一章", paragraphs: ["上一章结尾"]), configuration: configuration)
        let second = try await ReaderPreparedChapter.build(index: 1,
            content: NovelContent(title: "第二章", paragraphs: ["下一章开头"]), configuration: configuration)
        var crossed = 0
        var fallback = 0
        let controller = ReaderPageSurface.Controller()
        controller.configure(ReaderPageSurface(layout: first.layout, renderer: first.renderer, viewport: viewport,
            style: .cover, offset: 0, background: .white, backgroundImage: nil, backgroundOpacity: 0,
            animated: true, tapFraction: 0.3, tapsEnabled: true, slideForwardRight: true,
            moved: { _, _ in }, boundary: { _ in fallback += 1 }, center: {},
            crossedChapter: { crossed += 1 }, loadNext: {
                try? await Task.sleep(for: .milliseconds(80))
                return second
            }))
        let window = UIWindow(frame: CGRect(origin: .zero, size: viewport.size))
        window.rootViewController = controller; window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        defer { controller.invalidate(); window.isHidden = true }
        _ = controller.accessibilityScroll(.next)
        #expect(crossed == 0)
        for _ in 0..<100 {
            if crossed == 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(crossed == 1)
        #expect(fallback == 0)
        let canvas = try #require(controller.view.subviews.compactMap { $0 as? ReaderPageSurface.PageCanvas }.last)
        #expect(canvas.accessibilityLabel == second.layout.text.string)
    }

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
