import SwiftUI

/// Only this panel changes height while dragging; the page viewport and TextKit layout stay fixed.
struct ReaderSettingsPanel<Content: View>: View {
    let background: Color
    let close: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var expanded = false
    @GestureState private var translation: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height * 0.58
            let large = geometry.size.height * 0.96
            let height = min(large, max(compact, (expanded ? large : compact) - translation))
            ZStack(alignment: .bottom) {
                // Capture outside taps without dimming or recoloring the reading page.
                Color.clear.contentShape(Rectangle()).onTapGesture(perform: close)
                VStack(spacing: 0) {
                    Capsule().fill(.secondary).frame(width: 36, height: 5)
                        .frame(maxWidth: .infinity).frame(height: 30)
                        .background(background).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 3)
                            .updating($translation) { value, state, _ in state = value.translation.height }
                            .onEnded { value in
                                let proposed = (expanded ? large : compact) - value.predictedEndTranslation.height
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                                    expanded = proposed > (compact + large) / 2
                                }
                            })
                        .accessibilityLabel("设置面板高度")
                        .accessibilityValue(expanded ? "展开" : "半屏")
                        .accessibilityAdjustableAction { direction in
                            if direction == .increment { expanded = true }
                            if direction == .decrement { expanded = false }
                        }
                    content()
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
