import Foundation

/// Short drags and deliberate flicks commit without requiring half a page of travel.
public enum ReaderSlideTurn {
    public static func committedForward(translation: Double, width: Double,
                                        forwardRight: Bool, velocity: Double = 0,
                                        cancelled: Bool = false) -> Bool? {
        guard !cancelled, width.isFinite, width > 0, translation.isFinite,
              velocity.isFinite else { return nil }
        let distance = abs(translation)
        let deliberateFlick = distance >= 8 && abs(velocity) >= 450 && (translation > 0) == (velocity > 0)
        guard distance >= min(40, width * 0.12) || deliberateFlick else { return nil }
        return (translation > 0) == forwardRight
    }
}
