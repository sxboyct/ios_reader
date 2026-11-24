import SwiftUI
import UIKit

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
            return abs(velocity.y) > abs(velocity.x) && (!value.expanded || pan.location(in: view).y <= 30)
        }
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
        @objc private func dragged(_ pan: UIPanGestureRecognizer) {
            switch pan.state {
            case .began, .changed: value.changed(pan.translation(in: view.window).y)
            case .ended: value.ended(pan.translation(in: view.window).y, pan.velocity(in: view.window).y)
            case .cancelled, .failed: value.ended(0, 0)
            default: break
            }
        }
    }
}
