import UIKit

public struct ReaderViewport: Equatable, Sendable {
    public let size: CGSize
    public let contentFrame: CGRect
    public let origin: CGPoint

    public init(safeAreaSize: CGSize, safeAreaInsets: UIEdgeInsets) {
        size = CGSize(width: max(1, safeAreaSize.width + safeAreaInsets.left + safeAreaInsets.right),
            height: max(1, safeAreaSize.height + safeAreaInsets.top + safeAreaInsets.bottom))
        origin = CGPoint(x: -safeAreaInsets.left, y: -safeAreaInsets.top)
        contentFrame = CGRect(x: safeAreaInsets.left + 24, y: safeAreaInsets.top + 14,
            width: max(80, safeAreaSize.width - 48), height: max(100, safeAreaSize.height - 28))
    }
}
