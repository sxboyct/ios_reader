import Foundation

public struct ReaderPanelDrag {
    private var origin: Double?
    private var scrolledTranslation = 0.0

    public init() {}

    public mutating func update(translation: Double, expanded: Bool, scrollDistance: Double) -> Double? {
        guard translation.isFinite, scrollDistance.isFinite else { return nil }
        if !expanded { return translation }
        if let origin { return max(0, translation - origin) }
        guard translation > 0 else { return nil }
        if scrollDistance > 0.5 {
            scrolledTranslation = translation
            return nil
        }
        origin = scrolledTranslation
        return max(0, translation - scrolledTranslation)
    }
}
