import Testing
@testable import TVCore

struct ReaderSlideTurnTests {
    @Test func shortDragsTurnInEitherDirection() {
        for delta in [-35.0, -8, 0, 8, 35] {
            #expect(ReaderSlideTurn.committedForward(translation: delta, width: 300, forwardRight: true) == nil)
        }
        #expect(ReaderSlideTurn.committedForward(translation: 36, width: 300, forwardRight: true) == true)
        #expect(ReaderSlideTurn.committedForward(translation: -36, width: 300, forwardRight: true) == false)
        #expect(ReaderSlideTurn.committedForward(translation: -36, width: 300, forwardRight: false) == true)
        #expect(ReaderSlideTurn.committedForward(translation: 36, width: 300, forwardRight: false) == false)
        #expect(ReaderSlideTurn.committedForward(translation: 40, width: 1024, forwardRight: true) == true)
    }
    @Test func flicksRequireTravelAndMatchingDirection() {
        #expect(ReaderSlideTurn.committedForward(translation: 10, width: 300, forwardRight: true, velocity: 500) == true)
        #expect(ReaderSlideTurn.committedForward(translation: -10, width: 300, forwardRight: false, velocity: -500) == true)
        #expect(ReaderSlideTurn.committedForward(translation: 7, width: 300, forwardRight: true, velocity: 900) == nil)
        #expect(ReaderSlideTurn.committedForward(translation: 10, width: 300, forwardRight: true, velocity: -500) == nil)
        #expect(ReaderSlideTurn.committedForward(translation: 10, width: 300, forwardRight: true, velocity: 449) == nil)
    }
    @Test func cancelledOrInvalidDragNeverTurns() {
        #expect(ReaderSlideTurn.committedForward(translation: 300, width: 300, forwardRight: true, cancelled: true) == nil)
        #expect(ReaderSlideTurn.committedForward(translation: 300, width: 0, forwardRight: true) == nil)
        #expect(ReaderSlideTurn.committedForward(translation: .infinity, width: 300, forwardRight: true) == nil)
        #expect(ReaderSlideTurn.committedForward(translation: 300, width: .nan, forwardRight: true) == nil)
        #expect(ReaderSlideTurn.committedForward(translation: 40, width: 300, forwardRight: true, velocity: .nan) == nil)
    }
}
