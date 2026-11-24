import Testing
@testable import TVCore

struct ReaderPanelDragTests {
    @Test func compactPanelFollowsEitherDirection() {
        var drag = ReaderPanelDrag()
        #expect(drag.update(translation: -30, expanded: false, scrollDistance: 0) == -30)
        #expect(drag.update(translation: 30, expanded: false, scrollDistance: 0) == 30)
    }
    @Test func expandedPanelPullsDownFromAnyRegionAtTop() {
        var drag = ReaderPanelDrag()
        #expect(drag.update(translation: -30, expanded: true, scrollDistance: 0) == nil)
        #expect(drag.update(translation: 30, expanded: true, scrollDistance: 0) == 30)
        #expect(drag.update(translation: 50, expanded: true, scrollDistance: 0) == 50)
    }
    @Test func sameDragScrollsToTopThenResizesPanel() {
        var drag = ReaderPanelDrag()
        #expect(drag.update(translation: 20, expanded: true, scrollDistance: 80) == nil)
        #expect(drag.update(translation: 90, expanded: true, scrollDistance: 10) == nil)
        #expect(drag.update(translation: 100, expanded: true, scrollDistance: 0) == 10)
        #expect(drag.update(translation: 130, expanded: true, scrollDistance: -5) == 40)
        #expect(drag.update(translation: 80, expanded: true, scrollDistance: 0) == 0)
    }
}
