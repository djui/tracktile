import CoreGraphics
import Testing
import TrackTileCore

struct SnapZoneTests {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let size = CGSize(width: 400, height: 300)

    @Test func halvesAndQuartersWithoutGap() {
        #expect(SnapZone.left.frame(in: screen, currentSize: size) == CGRect(x: 0, y: 0, width: 500, height: 800))
        #expect(SnapZone.right.frame(in: screen, currentSize: size) == CGRect(x: 500, y: 0, width: 500, height: 800))
        #expect(SnapZone.top.frame(in: screen, currentSize: size) == CGRect(x: 0, y: 400, width: 1000, height: 400))
        #expect(SnapZone.bottom.frame(in: screen, currentSize: size) == CGRect(x: 0, y: 0, width: 1000, height: 400))
        #expect(SnapZone.topLeft.frame(in: screen, currentSize: size) == CGRect(x: 0, y: 400, width: 500, height: 400))
        #expect(SnapZone.bottomRight.frame(in: screen, currentSize: size) == CGRect(x: 500, y: 0, width: 500, height: 400))
        #expect(SnapZone.maximize.frame(in: screen, currentSize: size) == screen)
    }

    @Test func gapsSeparateWindowsAndEdges() {
        let options = LayoutOptions(gap: 10)
        #expect(SnapZone.left.frame(in: screen, currentSize: size, options: options) == CGRect(x: 10, y: 10, width: 485, height: 780))
        #expect(SnapZone.right.frame(in: screen, currentSize: size, options: options) == CGRect(x: 505, y: 10, width: 485, height: 780))
        #expect(SnapZone.topRight.frame(in: screen, currentSize: size, options: options) == CGRect(x: 505, y: 405, width: 485, height: 385))
        #expect(SnapZone.maximize.frame(in: screen, currentSize: size, options: options) == CGRect(x: 10, y: 10, width: 980, height: 780))
    }

    @Test func centerKeepsSizeAndClampsToScreen() {
        #expect(SnapZone.center.frame(in: screen, currentSize: size) == CGRect(x: 300, y: 250, width: 400, height: 300))
        let huge = CGSize(width: 2000, height: 2000)
        #expect(SnapZone.center.frame(in: screen, currentSize: huge) == screen)
    }

    @Test func centerWithFraction() {
        let options = LayoutOptions(centerSizing: .fraction(0.5))
        #expect(SnapZone.center.frame(in: screen, currentSize: size, options: options) == CGRect(x: 250, y: 200, width: 500, height: 400))
    }

    @Test func secondaryDisplayOffsets() {
        // A display to the left of and above the primary one.
        let secondary = CGRect(x: -1440, y: 900, width: 1440, height: 875)
        #expect(SnapZone.right.frame(in: secondary, currentSize: size) == CGRect(x: -720, y: 900, width: 720, height: 875))
        #expect(SnapZone.topLeft.frame(in: secondary, currentSize: size) == CGRect(x: -1440, y: 1338, width: 720, height: 438))
    }

    @Test func flipsBetweenCocoaAndAccessibilityCoordinates() {
        let cocoa = CGRect(x: 100, y: 200, width: 300, height: 400)
        let ax = ScreenGeometry.flip(cocoa, primaryScreenHeight: 1000)
        #expect(ax == CGRect(x: 100, y: 400, width: 300, height: 400))
        #expect(ScreenGeometry.flip(ax, primaryScreenHeight: 1000) == cocoa)
        #expect(ScreenGeometry.flip(CGPoint(x: 5, y: 10), primaryScreenHeight: 1000) == CGPoint(x: 5, y: 990))
    }
}
