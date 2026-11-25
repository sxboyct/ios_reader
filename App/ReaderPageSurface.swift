import SwiftUI
import UIKit
import TVCore

/// Native page rendering and gestures. Only a completed turn commits a new reading position.
struct ReaderPageSurface: UIViewControllerRepresentable {
    let layout: ReaderTextLayout
    let renderer: ReaderPageRenderer
    let viewport: ReaderViewport
    let style: ReaderTurnStyle
    let offset: Int
    let background: UIColor
    let backgroundImage: UIImage?
    let backgroundOpacity: Double
    let animated: Bool
    let tapFraction: Double
    let tapsEnabled: Bool
    let slideForwardRight: Bool
    var moved: (Int, Int) -> Void
    var boundary: (Bool) -> Void
    var center: () -> Void
    var nextLayout: ReaderTextLayout? = nil
    var nextRenderer: ReaderPageRenderer? = nil
    var crossedChapter: () -> Void = {}
    var loadNext: (@MainActor () async -> ReaderPreparedChapter?)? = nil
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.configure(self) }
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.invalidate() }

    @MainActor final class PageCanvas: UIImageView {
        init(layout: ReaderTextLayout, page: Int, image: UIImage?) {
            super.init(image: image)
            isOpaque = true; isUserInteractionEnabled = true; contentMode = .scaleToFill
            isAccessibilityElement = true
            if layout.pageRanges.indices.contains(page) {
                accessibilityLabel = layout.text.attributedSubstring(from: layout.pageRanges[page]).string
            }
        }
        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    }

    @MainActor final class PageHost: UIViewController {
        var index: Int
        let layout: ReaderTextLayout
        init(layout: ReaderTextLayout, index: Int, image: UIImage?, displayPage: Int? = nil) {
            self.index = index
            self.layout = layout
            super.init(nibName: nil, bundle: nil)
            view = PageCanvas(layout: layout, page: displayPage ?? index, image: image)
        }
        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    }

    @MainActor final class Controller: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UITextViewDelegate, UIGestureRecognizerDelegate {
        private var parentValue: ReaderPageSurface?
        private let backdrop = UIImageView(frame: .zero)
        private var renderer: ReaderPageRenderer?
        private var currentViewport: ReaderViewport?
        private var warmTask: Task<Void, Never>?
        private var turnTask: Task<Void, Never>?
        private var currentLayout: ReaderTextLayout?
        private var currentStyle: ReaderTurnStyle?
        private var currentAnimation = true
        private var currentPage = 0
        private var currentOffset = 0
        private var animating = false
        private var generation = 0
        private var canvas: PageCanvas?
        private var curl: UIPageViewController?
        private var textView: UITextView?
        private var swipeStartPage = 0
        private var restoringScroll = false
        private var pendingScrollRestore = false
        private var slidePan: UIPanGestureRecognizer?
        private var slidePreview: PageCanvas?
        private var slideTarget: Int?
        private var slideSign: CGFloat = 1
        private var draggingSlide = false
        private var awaitingChapter = false
        private var crossingLayout: ReaderTextLayout?
        private var loadingChapter = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.clipsToBounds = true
            backdrop.contentMode = .scaleToFill; backdrop.isUserInteractionEnabled = false
            view.addSubview(backdrop)
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            tap.delegate = self; view.addGestureRecognizer(tap)
            let pan = UIPanGestureRecognizer(target: self, action: #selector(draggedSlide(_:)))
            pan.maximumNumberOfTouches = 1; pan.delegate = self
            view.addGestureRecognizer(pan); slidePan = pan
            tap.require(toFail: pan)
            for direction: UISwipeGestureRecognizer.Direction in [.left, .right, .up, .down] {
                let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
                swipe.direction = direction; swipe.delegate = self; view.addGestureRecognizer(swipe)
            }
            let edgeObserver = UIPanGestureRecognizer(target: self, action: #selector(observedCurl(_:)))
            edgeObserver.cancelsTouchesInView = false; edgeObserver.delegate = self; view.addGestureRecognizer(edgeObserver)
        }
        func configure(_ parent: ReaderPageSurface) {
            loadViewIfNeeded()
            let nextChanged = parentValue?.nextLayout !== parent.nextLayout || parentValue?.nextRenderer !== parent.nextRenderer
            parentValue = parent; view.backgroundColor = parent.background
            if awaitingChapter, currentLayout === parent.layout {
                awaitingChapter = false
                if let curl, let visible = curl.viewControllers?.first {
                    curl.dataSource = nil
                    curl.setViewControllers([visible], direction: .forward, animated: false)
                    curl.dataSource = self
                }
                scheduleWarm()
            }
            let renderingChanged = currentLayout !== parent.layout || currentViewport != parent.viewport
                || renderer !== parent.renderer
            if renderingChanged {
                currentViewport = parent.viewport; renderer = parent.renderer
                backdrop.image = renderer?.background
            }
            if renderingChanged || currentStyle != parent.style || currentAnimation != parent.animated
                || (animating && crossingLayout != nil && nextChanged) {
                generation += 1; animating = false
                currentLayout = parent.layout; currentStyle = parent.style; currentAnimation = parent.animated
                currentOffset = min(max(0, parent.offset), max(0, parent.layout.text.length - 1))
                currentPage = parent.layout.page(containing: currentOffset)
                rebuild()
            } else if !animating && parent.offset != currentOffset {
                currentOffset = min(max(0, parent.offset), max(0, parent.layout.text.length - 1))
                currentPage = parent.layout.page(containing: currentOffset)
                if let textView { restoreScroll(textView) }
                else if let curl { curl.setViewControllers([host(currentPage)], direction: .forward, animated: false) }
                else { showCanvas() }
                scheduleWarm()
            }
        }
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            backdrop.frame = view.bounds
            if !animating, let canvas { place(canvas) }
            if !animating { curl?.view.frame = view.bounds }
            if let frame = parentValue?.viewport.contentFrame { textView?.frame = frame }
            if pendingScrollRestore, let textView, view.bounds.width > 0, view.bounds.height > 0 {
                pendingScrollRestore = false; restoreScroll(textView)
            }
        }
        private func rebuild() {
            warmTask?.cancel(); turnTask?.cancel()
            awaitingChapter = false
            crossingLayout = nil
            loadingChapter = false
            draggingSlide = false; slideTarget = nil
            slidePreview?.removeFromSuperview(); slidePreview = nil
            canvas?.removeFromSuperview(); canvas = nil
            textView?.removeFromSuperview(); textView = nil
            if let curl {
                curl.delegate = nil; curl.dataSource = nil
                curl.willMove(toParent: nil); curl.view.removeFromSuperview(); curl.removeFromParent()
            }
            curl = nil
            guard let parent = parentValue else { return }
            if parent.style == .scroll {
                let text = UITextView(usingTextLayoutManager: false)
                text.frame = parent.viewport.contentFrame
                text.isEditable = false; text.isSelectable = false
                text.backgroundColor = .clear; text.attributedText = parent.layout.text
                text.textContainerInset = .zero; text.textContainer.lineFragmentPadding = 0
                text.contentInsetAdjustmentBehavior = .never; text.showsVerticalScrollIndicator = false
                text.alwaysBounceVertical = true
                view.addSubview(text); textView = text
                pendingScrollRestore = true; text.delegate = self; view.setNeedsLayout()
            } else if parent.style == .curl && parent.animated {
                let pager = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal)
                pager.isDoubleSided = false; pager.dataSource = self; pager.delegate = self
                addChild(pager); pager.view.frame = view.bounds; view.addSubview(pager.view); pager.didMove(toParent: self)
                pager.setViewControllers([host(currentPage)], direction: .forward, animated: false)
                for recognizer in pager.gestureRecognizers where recognizer is UITapGestureRecognizer { recognizer.isEnabled = false }
                curl = pager
            } else { showCanvas() }
            scheduleWarm()
        }
        private func place(_ page: UIView) {
            page.bounds = CGRect(origin: .zero, size: view.bounds.size)
            page.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        }
        private func host(_ page: Int) -> PageHost {
            if let parent = parentValue, page == parent.layout.count,
               let layout = parent.nextLayout, let image = parent.nextRenderer?.cachedImage(page: 0) {
                return PageHost(layout: layout, index: page, image: image, displayPage: 0)
            }
            let host = PageHost(layout: parentValue!.layout, index: page, image: renderer?.cachedImage(page: page))
            if let canvas = host.view as? PageCanvas { finishRendering(canvas, page: page) }
            return host
        }
        private func makeCanvas(_ page: Int, image: UIImage? = nil) -> PageCanvas {
            if let parent = parentValue, page == parent.layout.count, let layout = parent.nextLayout {
                return PageCanvas(layout: layout, page: 0, image: image ?? parent.nextRenderer?.cachedImage(page: 0))
            }
            let canvas = PageCanvas(layout: parentValue!.layout, page: page, image: image ?? renderer?.cachedImage(page: page))
            finishRendering(canvas, page: page)
            return canvas
        }
        private func finishRendering(_ canvas: PageCanvas, page: Int) {
            guard canvas.image == nil, let renderer else { return }
            let token = generation
            Task { @MainActor [weak self, weak canvas] in
                let rendered = await renderer.preparePage(page)
                guard let self, self.generation == token else { return }
                canvas?.image = rendered?.image
            }
        }
        private func showCanvas() {
            guard parentValue != nil else { return }
            canvas?.removeFromSuperview()
            let next = makeCanvas(currentPage)
            place(next); view.addSubview(next); canvas = next
        }
        private func commit(_ page: Int) {
            guard let parent = parentValue else { return }
            crossingLayout = nil
            if page == parent.layout.count, let nextLayout = parent.nextLayout, let nextRenderer = parent.nextRenderer {
                generation += 1; warmTask?.cancel()
                currentLayout = nextLayout; renderer = nextRenderer; currentViewport = nextRenderer.viewport
                backdrop.image = nextRenderer.background
                currentPage = 0; currentOffset = 0; awaitingChapter = true
                (curl?.viewControllers?.first as? PageHost)?.index = 0
                parent.crossedChapter()
                return
            }
            guard parent.layout.pageRanges.indices.contains(page) else { rebuild(); return }
            currentPage = page; currentOffset = parent.layout.offset(page: page)
            parent.moved(currentOffset, page)
            scheduleWarm()
        }
        private func scheduleWarm() {
            warmTask?.cancel()
            let token = generation
            let page = currentPage
            guard let renderer, textView == nil else { return }
            let neighborsReady = [page - 1, page + 1].filter { currentLayout?.pageRanges.indices.contains($0) == true }
                .allSatisfy { renderer.cachedImage(page: $0) != nil }
            curl?.view.isUserInteractionEnabled = neighborsReady && !loadingChapter
            warmTask = Task { @MainActor [weak self] in
                guard !Task.isCancelled else { return }
                await renderer.prepareAsync(around: page)
                guard let self, !Task.isCancelled, self.generation == token, self.currentPage == page else { return }
                self.curl?.view.isUserInteractionEnabled = !self.loadingChapter
            }
        }
        func invalidate() {
            generation += 1; warmTask?.cancel(); turnTask?.cancel(); parentValue = nil
        }
        private func prepareTurn(_ forward: Bool, target: Int) {
            guard let renderer else { return }
            let token = generation
            let sourcePage = currentPage
            let sourceLayout = currentLayout
            animating = true
            loadingChapter = true; curl?.view.isUserInteractionEnabled = false
            turnTask = Task { @MainActor [weak self] in
                let rendered = await renderer.preparePage(target)
                guard let self, !Task.isCancelled, self.generation == token,
                      self.currentPage == sourcePage, self.currentLayout === sourceLayout else { return }
                self.animating = false; self.turnTask = nil; self.loadingChapter = false
                self.curl?.view.isUserInteractionEnabled = true
                if let rendered { self.turn(forward, preparedImage: rendered.image) }
            }
        }
        private func prepareChapter() {
            guard let parent = parentValue, let loadNext = parent.loadNext else {
                parentValue?.boundary(true); return
            }
            let token = generation
            let sourcePage = currentPage
            let sourceLayout = currentLayout
            animating = true
            loadingChapter = true; curl?.view.isUserInteractionEnabled = false
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            view.addSubview(indicator); indicator.startAnimating()
            turnTask = Task { @MainActor [weak self] in
                defer { indicator.removeFromSuperview() }
                let next = await loadNext()
                guard let self, !Task.isCancelled, self.generation == token,
                      self.currentPage == sourcePage, self.currentLayout === sourceLayout else { return }
                self.animating = false; self.turnTask = nil; self.loadingChapter = false
                self.curl?.view.isUserInteractionEnabled = true
                guard let next else { self.parentValue?.boundary(true); return }
                var updated = self.parentValue ?? parent
                updated.nextLayout = next.layout; updated.nextRenderer = next.renderer
                self.configure(updated)
                self.turn(true)
            }
        }
        private func restoreScroll(_ text: UITextView) {
            restoringScroll = true
            text.layoutManager.ensureLayout(for: text.textContainer)
            text.layoutIfNeeded()
            let at = min(currentOffset, max(0, text.textStorage.length - 1))
            let glyph = text.layoutManager.glyphRange(forCharacterRange: NSRange(location: at, length: 1), actualCharacterRange: nil)
            let rect = text.layoutManager.boundingRect(forGlyphRange: glyph, in: text.textContainer)
            text.setContentOffset(CGPoint(x: 0, y: min(rect.minY, max(0, text.contentSize.height - text.bounds.height))), animated: false)
            restoringScroll = false
        }
        private func turn(_ forward: Bool, preparedImage: UIImage? = nil) {
            guard let parent = parentValue, !animating, !awaitingChapter else { return }
            if let textView {
                let maxY = max(0, textView.contentSize.height - textView.bounds.height)
                let y = textView.contentOffset.y
                if (forward && y >= maxY - 2) || (!forward && y <= 2) { parent.boundary(forward); return }
                textView.setContentOffset(CGPoint(x: 0, y: min(maxY, max(0, y + (forward ? 1 : -1) * textView.bounds.height * 0.9))), animated: parent.animated)
                return
            }
            let target = currentPage + (forward ? 1 : -1)
            if forward, target == parent.layout.count, !nextChapterReady(target), parent.loadNext != nil {
                prepareChapter(); return
            }
            guard target >= 0 && (target < parent.layout.count || nextChapterReady(target)) else { parent.boundary(forward); return }
            guard let targetImage = preparedImage ?? pageImage(target) else {
                prepareTurn(forward, target: target); return
            }
            let token = generation
            crossingLayout = target == parent.layout.count ? parent.nextLayout : nil
            if let curl {
                animating = true
                let targetHost = PageHost(layout: target == parent.layout.count ? parent.nextLayout! : parent.layout,
                    index: target, image: targetImage, displayPage: target == parent.layout.count ? 0 : target)
                curl.setViewControllers([targetHost], direction: forward ? .forward : .reverse, animated: parent.animated) { [weak self] finished in
                    guard let self, self.generation == token else { return }
                    self.animating = false
                    if finished { self.commit(target) }
                }
                return
            }
            let next = makeCanvas(target, image: targetImage)
            place(next)
            guard parent.animated, let old = canvas else {
                canvas?.removeFromSuperview(); view.addSubview(next); canvas = next; commit(target); return
            }
            let distance = parent.style == .vertical ? view.bounds.height : view.bounds.width
            let forwardSign = parent.style == .slide && parent.slideForwardRight ? -1.0 : 1.0
            let translation = (forward ? forwardSign : -forwardSign) * distance
            let vector = parent.style == .vertical ? CGAffineTransform(translationX: 0, y: translation) : CGAffineTransform(translationX: translation, y: 0)
            if parent.style == .fade { next.alpha = 0; view.addSubview(next) }
            else if parent.style == .cover && !forward { view.insertSubview(next, belowSubview: old) }
            else { next.transform = vector; view.addSubview(next) }
            animating = true
            UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseOut]) {
                next.transform = .identity; next.alpha = 1
                if parent.style == .fade { old.alpha = 0 }
                else if parent.style != .cover || !forward { old.transform = vector.inverted() }
            } completion: { [weak self] _ in
                old.removeFromSuperview()
                guard let self, self.generation == token else { next.removeFromSuperview(); return }
                self.canvas = next; self.animating = false; self.commit(target)
            }
        }
        @objc private func draggedSlide(_ gesture: UIPanGestureRecognizer) {
            slideChanged(translation: gesture.translation(in: view).x, velocity: gesture.velocity(in: view).x, state: gesture.state)
        }
        func slideChanged(translation: CGFloat, velocity: CGFloat, state: UIGestureRecognizer.State) {
            guard let parent = parentValue, parent.style == .slide, !awaitingChapter, let old = canvas else { return }
            let width = max(1, view.bounds.width)
            let delta = max(-width, min(width, translation))
            switch state {
            case .began:
                guard !animating else { return }
                draggingSlide = true; animating = true
                updateSlide(delta: delta, width: width, old: old, parent: parent)
            case .changed:
                guard draggingSlide else { return }
                updateSlide(delta: delta, width: width, old: old, parent: parent)
            case .ended, .cancelled, .failed:
                guard draggingSlide else { return }
                draggingSlide = false
                updateSlide(delta: delta, width: width, old: old, parent: parent)
                let forward = ReaderSlideTurn.committedForward(translation: Double(delta), width: Double(width),
                    forwardRight: parent.slideForwardRight, velocity: Double(velocity),
                    cancelled: state != .ended)
                let preview = slidePreview
                let target = slideTarget
                let token = generation
                let commitPage = forward != nil && preview != nil
                let endX: CGFloat = commitPage ? slideSign * width : 0
                let duration = parent.animated ? (forward == nil ? 0.18 : 0.22) : 0
                UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                    old.transform = CGAffineTransform(translationX: endX, y: 0)
                    preview?.transform = CGAffineTransform(translationX: endX - self.slideSign * width, y: 0)
                } completion: { [weak self] _ in
                    guard let self, self.generation == token else { preview?.removeFromSuperview(); return }
                    self.slidePreview = nil; self.slideTarget = nil; self.animating = false
                    if commitPage, let preview, let target {
                        old.removeFromSuperview(); preview.transform = .identity
                        self.canvas = preview; self.commit(target)
                    } else {
                        self.crossingLayout = nil
                        old.transform = .identity; preview?.removeFromSuperview()
                        self.scheduleWarm()
                        if let forward {
                            if let target, target >= 0, target <= parent.layout.count { self.turn(forward) }
                            else { self.parentValue?.boundary(forward) }
                        }
                    }
                }
            default: break
            }
        }
        private func updateSlide(delta: CGFloat, width: CGFloat, old: PageCanvas, parent: ReaderPageSurface) {
            slideSign = delta < 0 ? -1 : 1
            let forward = (slideSign > 0) == parent.slideForwardRight
            let target = currentPage + (forward ? 1 : -1)
            crossingLayout = target == parent.layout.count ? parent.nextLayout : nil
            if slideTarget != target || slidePreview == nil {
                slidePreview?.removeFromSuperview(); slidePreview = nil; slideTarget = target
                if target >= 0 && (target < parent.layout.count || nextChapterReady(target)), pageImage(target) != nil {
                    let preview = makeCanvas(target)
                    place(preview); view.addSubview(preview); slidePreview = preview
                }
            }
            // At chapter boundaries, resist the drag instead of showing an empty page.
            let x: CGFloat = parent.animated ? (slidePreview == nil ? delta * 0.18 : delta) : 0
            old.transform = CGAffineTransform(translationX: x, y: 0)
            slidePreview?.transform = CGAffineTransform(translationX: x - slideSign * width, y: 0)
        }
        @objc private func tapped(_ gesture: UITapGestureRecognizer) {
            guard let parent = parentValue else { return }
            let x = gesture.location(in: view).x / max(1, view.bounds.width)
            if !parent.tapsEnabled { parent.center() }
            else if x < parent.tapFraction { turn(false) }
            else if x > 1 - parent.tapFraction { turn(true) }
            else { parent.center() }
        }
        @objc private func swiped(_ gesture: UISwipeGestureRecognizer) {
            guard textView == nil, curl == nil, let parent = parentValue else { return }
            if parent.style == .vertical {
                if gesture.direction == .up { turn(true) }
                if gesture.direction == .down { turn(false) }
            } else {
                if gesture.direction == .left { turn(true) }
                if gesture.direction == .right { turn(false) }
            }
        }
        @objc private func observedCurl(_ gesture: UIPanGestureRecognizer) {
            guard curl != nil, let parent = parentValue else { return }
            if gesture.state == .began { swipeStartPage = currentPage }
            if gesture.state == .ended {
                let delta = gesture.translation(in: view)
                guard abs(delta.x) > 50, abs(delta.x) > abs(delta.y) else { return }
                if swipeStartPage == parent.layout.count - 1 && delta.x < 0,
                   !nextChapterReady(parent.layout.count), !awaitingChapter { turn(true) }
                if swipeStartPage == 0 && delta.x > 0 { parent.boundary(false) }
            }
        }
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            if awaitingChapter || loadingChapter { return false }
            if gesture === slidePan {
                guard currentStyle == .slide, !animating, let pan = gesture as? UIPanGestureRecognizer else { return false }
                let velocity = pan.velocity(in: view)
                return abs(velocity.x) > abs(velocity.y)
            }
            if gesture is UISwipeGestureRecognizer { return currentStyle != .slide && curl == nil && textView == nil }
            if gesture is UIPanGestureRecognizer { return curl != nil }
            return true
        }
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            if gesture === slidePan || other === slidePan { return false }
            return gesture is UIPanGestureRecognizer || other is UIPanGestureRecognizer
        }
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore controller: UIViewController) -> UIViewController? {
            guard !awaitingChapter, !loadingChapter, let host = controller as? PageHost else { return nil }
            if let parent = parentValue, host.layout === parent.nextLayout, host.index == parent.layout.count {
                return self.host(parent.layout.count - 1)
            }
            guard host.layout === currentLayout else { return nil }
            let page = host.index
            guard page > 0,
                  renderer?.cachedImage(page: page - 1) != nil else { return nil }
            return self.host(page - 1)
        }
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter controller: UIViewController) -> UIViewController? {
            guard let parent = parentValue, !awaitingChapter, !loadingChapter, let host = controller as? PageHost,
                  host.layout === currentLayout else { return nil }
            let page = host.index
            guard
                  page + 1 < parent.layout.count || nextChapterReady(page + 1),
                  pageImage(page + 1) != nil else { return nil }
            return self.host(page + 1)
        }
        private func nextChapterReady(_ page: Int) -> Bool {
            guard let parent = parentValue, page == parent.layout.count else { return false }
            return parent.nextLayout != nil && parent.nextRenderer?.cachedImage(page: 0) != nil
        }
        private func pageImage(_ page: Int) -> UIImage? {
            if let parent = parentValue, page == parent.layout.count { return parent.nextRenderer?.cachedImage(page: 0) }
            return renderer?.cachedImage(page: page)
        }
        func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            guard pageViewController === curl else { return }
            let pending = pendingViewControllers.first as? PageHost
            crossingLayout = pending?.layout !== currentLayout ? pending?.layout : nil
            animating = true
        }
        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard pageViewController === curl else { return }
            animating = false
            if completed, let page = (pageViewController.viewControllers?.first as? PageHost)?.index { commit(page) }
            else { crossingLayout = nil; scheduleWarm() }
        }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !restoringScroll, !pendingScrollRestore, let textView, let parent = parentValue, textView.textStorage.length > 0 else { return }
            let point = CGPoint(x: 1, y: max(0, textView.contentOffset.y) + 1)
            let glyph = textView.layoutManager.glyphIndex(for: point, in: textView.textContainer)
            guard glyph < textView.layoutManager.numberOfGlyphs else { return }
            currentOffset = textView.layoutManager.characterIndexForGlyph(at: glyph)
            currentPage = parent.layout.page(containing: currentOffset)
            parent.moved(currentOffset, currentPage)
        }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard let parent = parentValue else { return }
            let bottom = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            if scrollView.contentOffset.y > bottom + 65 { parent.boundary(true) }
            else if scrollView.contentOffset.y < -65 { parent.boundary(false) }
        }
        override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
            switch direction {
            case .left, .up, .next: turn(true)
            case .right, .down, .previous: turn(false)
            default: return false
            }
            return true
        }
    }
}
