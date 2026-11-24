import SwiftUI
import UIKit
import TVCore

/// Only this panel changes height while dragging; the page viewport and TextKit layout stay fixed.
struct ReaderSettingsPanel<Content: View>: View {
    let background: Color
    let close: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var expanded = false
    @State private var translation: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height * 0.58
            let large = geometry.size.height * 0.96
            let height = min(large, max(compact, (expanded ? large : compact) - translation))
            ZStack(alignment: .bottom) {
                // Capture outside taps without dimming or recoloring the reading page.
                Color.clear.contentShape(Rectangle()).onTapGesture(perform: close)
                ReaderPanelGestureHost(expanded: expanded, changed: { translation = $0 }, ended: { distance, velocity in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        translation = 0
                        let projected = distance + velocity * 0.15
                        if distance < -24 || projected < -60 { expanded = true }
                        else if distance > 24 || projected > 60 { expanded = false }
                    }
                }) {
                    VStack(spacing: 0) {
                        Capsule().fill(.secondary).frame(width: 36, height: 5)
                            .frame(maxWidth: .infinity).frame(height: 30)
                            .background(background).contentShape(Rectangle())
                            .accessibilityLabel("设置面板高度")
                            .accessibilityValue(expanded ? "展开" : "半屏")
                            .accessibilityAdjustableAction { direction in
                                if direction == .increment { expanded = true }
                                if direction == .decrement { expanded = false }
                            }
                        content()
                            .scrollDisabled(!expanded)
                    }
                }
                .frame(height: height)
                .background(background)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
                .overlay(alignment: .top) { Color.secondary.opacity(0.15).frame(height: 0.5).padding(.horizontal, 18) }
            }
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
    }
}

private struct ReaderPanelGestureHost<Content: View>: UIViewControllerRepresentable {
    let expanded: Bool
    let changed: (CGFloat) -> Void
    let ended: (CGFloat, CGFloat) -> Void
    @ViewBuilder var content: () -> Content

    func makeUIViewController(context: Context) -> Controller { Controller(self) }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.value = self
        controller.host.rootView = content()
    }

    @MainActor final class Controller: UIViewController, UIGestureRecognizerDelegate {
        var value: ReaderPanelGestureHost
        let host: UIHostingController<Content>
        private var drag = ReaderPanelDrag()
        private weak var scrolling: UIScrollView?
        private var suspendedScrolling = false
        private var resizing = false
        private var distance: CGFloat = 0

        init(_ value: ReaderPanelGestureHost) {
            self.value = value
            host = UIHostingController(rootView: value.content())
            super.init(nibName: nil, bundle: nil)
        }
        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear; host.view.backgroundColor = .clear
            addChild(host); view.addSubview(host.view); host.didMove(toParent: self)
            let pan = UIPanGestureRecognizer(target: self, action: #selector(dragged(_:)))
            pan.maximumNumberOfTouches = 1; pan.delegate = self
            view.addGestureRecognizer(pan)
        }
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            host.view.frame = view.bounds
        }
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: view)
            return abs(velocity.y) > abs(velocity.x) && (!value.expanded || velocity.y > 0)
        }
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
        @objc private func dragged(_ pan: UIPanGestureRecognizer) {
            switch pan.state {
            case .began:
                drag = ReaderPanelDrag(); resizing = false; distance = 0
                scrolling = scrollView(at: pan.location(in: view))
                updateDrag(pan)
            case .changed: updateDrag(pan)
            case .ended:
                updateDrag(pan)
                restoreScrolling()
                value.ended(distance, resizing ? pan.velocity(in: view.window).y : 0)
            case .cancelled, .failed:
                restoreScrolling(); value.ended(0, 0)
            default: break
            }
        }
        private func updateDrag(_ pan: UIPanGestureRecognizer) {
            let scrollDistance = scrolling.map { max(0, $0.contentOffset.y + $0.adjustedContentInset.top) } ?? 0
            guard let delta = drag.update(translation: Double(pan.translation(in: view.window).y),
                expanded: value.expanded, scrollDistance: Double(scrollDistance)) else { return }
            resizing = true; distance = CGFloat(delta)
            if value.expanded, let scrolling {
                if scrolling.isScrollEnabled {
                    suspendedScrolling = true; scrolling.isScrollEnabled = false
                }
                scrolling.setContentOffset(CGPoint(x: scrolling.contentOffset.x, y: -scrolling.adjustedContentInset.top), animated: false)
            }
            value.changed(distance)
        }
        private func scrollView(at point: CGPoint) -> UIScrollView? {
            var target = view.hitTest(point, with: nil)
            while let current = target {
                if let scroll = current as? UIScrollView { return scroll }
                target = current.superview
            }
            return nil
        }
        private func restoreScrolling() {
            if suspendedScrolling { scrolling?.isScrollEnabled = true }
            suspendedScrolling = false; scrolling = nil
        }
    }
}
