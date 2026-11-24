import Foundation

/// A drag commits only past half the reading surface; flick velocity never skips this threshold.
public enum ReaderSlideTurn {
    public static func committedForward(translation: Double, width: Double,
                                        forwardRight: Bool, cancelled: Bool = false) -> Bool? {
        guard !cancelled, width.isFinite, width > 0, translation.isFinite,
              abs(translation) > width / 2 else { return nil }
        return (translation > 0) == forwardRight
    }
}
