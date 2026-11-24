import Testing
@testable import TVCore

struct ReaderSlideTurnTests {
    @Test func releaseMustPassHalfWidthInEitherDirection() {
        for delta in [-150.0, -149, 0, 149, 150] {
            #expect(ReaderSlideTurn.committedForward(translation: delta, width: 300, forwardRight: true) == nil)
        }
        #expect(ReaderSlideTurn.committedForward(translation: 151, width: 300, forwardRight: true) == true)
        #expect(ReaderSlideTurn.committedForward(translation: -151, width: 300, forwardRight: true) == false)
        #expect(ReaderSlideTurn.committedForward(translation: -151, width: 300, forwardRight: false) == true)
        #expect(ReaderSlideTurn.committedForward(translation: 151, width: 300, forwardRight: false) == false)
    }
    @Test func cancelledOrInvalidDragNeverTurns() {
        #expect(ReaderSlideTurn.committedForward(translation: 300, width: 300, forwardRight: true, cancelled: true) == nil)
        #expect(ReaderSlideTurn.committedForward(translation: 300, width: 0, forwardRight: true) == nil)
        #expect(ReaderSlideTurn.committedForward(translation: .infinity, width: 300, forwardRight: true) == nil)
        #expect(ReaderSlideTurn.committedForward(translation: 300, width: .nan, forwardRight: true) == nil)
    }
}
