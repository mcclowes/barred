@testable import Barred
import Testing

@MainActor
struct SectionDividerTests {
    @Test("initially not hidden")
    func initialState() {
        let divider = SectionDivider()
        #expect(divider.isSectionHidden == false)
    }

    @Test("expand without setUp is a no-op")
    func expandBeforeSetUp() {
        let divider = SectionDivider()
        divider.expand()
        #expect(divider.isSectionHidden == false)
    }

    @Test("collapse without setUp is a no-op")
    func collapseBeforeSetUp() {
        let divider = SectionDivider()
        divider.collapse()
        #expect(divider.isSectionHidden == false)
    }
}
