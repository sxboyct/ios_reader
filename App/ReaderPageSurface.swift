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
        let index: Int
        init(layout: ReaderTextLayout, index: Int, image: UIImage?) {
            self.index = index
            super.init(nibName: nil, bundle: nil)
            view = PageCanvas(layout: layout, page: index, image: image)
        }
        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    }

    @MainActor final class Controller: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UITextViewDelegate, UIGestureRecognizerDelegate {
        private var parentValue: ReaderPageSurface?
        private let backdrop = UIImageView(frame: .zero)
        private var renderer: ReaderPageRenderer?
        private var currentViewport: ReaderViewport?
        private var warmTask: Task<Void, Never>?
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
            parentValue = parent; view.backgroundColor = parent.background
            let renderingChanged = currentLayout !== parent.layout || currentViewport != parent.viewport
                || renderer !== parent.renderer
            if renderingChanged {
                currentViewport = parent.viewport; renderer = parent.renderer
                backdrop.image = renderer?.background
            }
            if renderingChanged || currentStyle != parent.style || currentAnimation != parent.animated {
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
            if !animating { canvas?.frame = view.bounds }
            curl?.view.frame = view.bounds
            if let frame = parentValue?.viewport.contentFrame { textView?.frame = frame }
            if pendingScrollRestore, let textView, view.bounds.width > 0, view.bounds.height > 0 {
                pendingScrollRestore = false; restoreScroll(textView)
            }
        }
        private func rebuild() {
            warmTask?.cancel()
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
                let text = UITextView(frame: parent.viewport.contentFrame)
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
        }
        private func host(_ page: Int) -> PageHost {
            let host = PageHost(layout: parentValue!.layout, index: page, image: renderer?.cachedImage(page: page))
            if let canvas = host.view as? PageCanvas { finishRendering(canvas, page: page) }
            return host
        }
        private func makeCanvas(_ page: Int) -> PageCanvas {
            let canvas = PageCanvas(layout: parentValue!.layout, page: page, image: renderer?.cachedImage(page: page))
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
            next.frame = view.bounds; view.addSubview(next); canvas = next
        }
        private func commit(_ page: Int) {
            guard let parent = parentValue else { return }
            currentPage = page; currentOffset = parent.layout.offset(page: page)
            parent.moved(currentOffset, page)
            scheduleWarm()
        }
        private func scheduleWarm() {
            warmTask?.cancel()
            let token = generation
            warmTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
                guard let self, self.generation == token, !self.animating, self.textView == nil else { return }
                await self.renderer?.prepareAsync(around: self.currentPage)
            }
        }
        func invalidate() {
            generation += 1; warmTask?.cancel(); parentValue = nil
        }
        private func prepareTurn(_ forward: Bool, target: Int) {
            guard let renderer else { return }
            let token = generation
            animating = true
            warmTask = Task { @MainActor [weak self] in
                await renderer.prepareAsync(around: target)
                guard let self, !Task.isCancelled, self.generation == token else { return }
                self.animating = false; self.warmTask = nil; self.turn(forward)
            }
        }
        private func restoreScroll(_ text: UITextView) {
            restoringScroll = true
            text.layoutIfNeeded()
            let at = min(currentOffset, max(0, text.textStorage.length - 1))
            let glyph = text.layoutManager.glyphRange(forCharacterRange: NSRange(location: at, length: 1), actualCharacterRange: nil)
            let rect = text.layoutManager.boundingRect(forGlyphRange: glyph, in: text.textContainer)
            text.setContentOffset(CGPoint(x: 0, y: min(rect.minY, max(0, text.contentSize.height - text.bounds.height))), animated: false)
            restoringScroll = false
        }
        private func turn(_ forward: Bool) {
            guard let parent = parentValue, !animating else { return }
            warmTask?.cancel()
            if let textView {
                let maxY = max(0, textView.contentSize.height - textView.bounds.height)
                let y = textView.contentOffset.y
                if (forward && y >= maxY - 2) || (!forward && y <= 2) { parent.boundary(forward); return }
                textView.setContentOffset(CGPoint(x: 0, y: min(maxY, max(0, y + (forward ? 1 : -1) * textView.bounds.height * 0.9))), animated: parent.animated)
                return
            }
            let target = currentPage + (forward ? 1 : -1)
            guard target >= 0 && target < parent.layout.count else { parent.boundary(forward); return }
            guard renderer?.cachedImage(page: target) != nil else { prepareTurn(forward, target: target); return }
            let token = generation
            if let curl {
                animating = true
                curl.setViewControllers([host(target)], direction: forward ? .forward : .reverse, animated: parent.animated) { [weak self] finished in
                    guard let self, self.generation == token else { return }
                    self.animating = false
                    if finished { self.commit(target) }
                }
                return
            }
            guard parent.animated, let old = canvas else { commit(target); showCanvas(); return }
            let next = makeCanvas(target)
            next.frame = view.bounds
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
            guard let parent = parentValue, parent.style == .slide, let old = canvas else { return }
            let width = max(1, view.bounds.width)
            let delta = max(-width, min(width, gesture.translation(in: view).x))
            switch gesture.state {
            case .began:
                guard !animating else { return }
                warmTask?.cancel()
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
                    forwardRight: parent.slideForwardRight, velocity: Double(gesture.velocity(in: view).x),
                    cancelled: gesture.state != .ended)
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
                        old.transform = .identity; preview?.removeFromSuperview()
                        self.scheduleWarm()
                        if let forward {
                            if let target, target >= 0, target < parent.layout.count { self.turn(forward) }
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
            if slideTarget != target || slidePreview == nil {
                slidePreview?.removeFromSuperview(); slidePreview = nil; slideTarget = target
                if target >= 0 && target < parent.layout.count, renderer?.cachedImage(page: target) != nil {
                    let preview = makeCanvas(target)
                    preview.frame = view.bounds; view.addSubview(preview); slidePreview = preview
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
                if swipeStartPage == parent.layout.count - 1 && delta.x < 0 { parent.boundary(true) }
                if swipeStartPage == 0 && delta.x > 0 { parent.boundary(false) }
            }
        }
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
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
            guard let page = (controller as? PageHost)?.index, page > 0 else { return nil }
            return host(page - 1)
        }
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter controller: UIViewController) -> UIViewController? {
            guard let parent = parentValue, let page = (controller as? PageHost)?.index, page + 1 < parent.layout.count else { return nil }
            return host(page + 1)
        }
        func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            warmTask?.cancel(); animating = true
        }
        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard pageViewController === curl else { return }
            animating = false
            if completed, let page = (pageViewController.viewControllers?.first as? PageHost)?.index { commit(page) }
            else { scheduleWarm() }
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
