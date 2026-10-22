import AppKit
@testable import Barred
import Testing

@MainActor
struct SectionDividerTests {
    @Test("divider renders a visible vertical line", .bug("https://github.com/mcclowes/barred/issues/46"))
    func dividerImageIsVisible() throws {
        let image = SectionDivider.makeDividerImage()
        #expect(image.isTemplate)
        #expect(image.accessibilityDescription == "Barred section divider")
        var rect = NSRect(origin: .zero, size: image.size)
        let cgImage = try #require(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let centerX = bitmap.pixelsWide / 2
        let centerY = bitmap.pixelsHigh / 2

        for y in (bitmap.pixelsHigh / 4) ..< (bitmap.pixelsHigh * 3 / 4) {
            let color = try #require(bitmap.colorAt(x: centerX, y: y))
            #expect(color.alphaComponent > 0.5)
        }
        let edge = try #require(bitmap.colorAt(x: 0, y: centerY))
        #expect(edge.alphaComponent == 0)
    }

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
