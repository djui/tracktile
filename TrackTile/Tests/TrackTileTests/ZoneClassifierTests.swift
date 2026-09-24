import CoreGraphics
import Testing
import TrackTileCore

struct ZoneClassifierTests {
    private let classifier = ZoneClassifier()

    private func sample(_ x: CGFloat, _ y: CGFloat, start: CGPoint = CGPoint(x: 0.5, y: 0.5), velocity: CGVector = .zero) -> GestureSample {
        GestureSample(start: start, centroid: CGPoint(x: x, y: y), velocity: velocity, fingerCount: 4)
    }

    @Test(arguments: [
        (CGFloat(0.1), CGFloat(0.9), SnapZone.topLeft),
        (0.5, 0.9, .top),
        (0.9, 0.9, .topRight),
        (0.1, 0.5, .left),
        (0.9, 0.5, .right),
        (0.1, 0.1, .bottomLeft),
        (0.5, 0.1, .bottom),
        (0.9, 0.1, .bottomRight),
    ])
    func mapsGridCells(x: CGFloat, y: CGFloat, expected: SnapZone) {
        #expect(classifier.zone(for: sample(x, y)) == expected)
    }

    @Test func centerCellWhenMovedAwayFromStart() {
        #expect(classifier.zone(for: sample(0.55, 0.5, start: CGPoint(x: 0.4, y: 0.5))) == .center)
    }

    @Test func deadZoneAroundStartCancels() {
        #expect(classifier.zone(for: sample(0.51, 0.5)) == nil)
        #expect(classifier.zone(for: sample(0.12, 0.9, start: CGPoint(x: 0.1, y: 0.9))) == nil)
    }

    @Test func upwardFlickMaximizes() {
        #expect(classifier.zone(for: sample(0.5, 0.9, velocity: CGVector(dx: 0.2, dy: 3))) == .maximize)
    }

    @Test func slowOrDiagonalMovementDoesNotMaximize() {
        #expect(classifier.zone(for: sample(0.5, 0.9, velocity: CGVector(dx: 0, dy: 1))) == .top)
        #expect(classifier.zone(for: sample(0.9, 0.9, velocity: CGVector(dx: 3, dy: 3))) == .topRight)
        #expect(classifier.zone(for: sample(0.5, 0.1, velocity: CGVector(dx: 0, dy: -4))) == .bottom)
    }
}
