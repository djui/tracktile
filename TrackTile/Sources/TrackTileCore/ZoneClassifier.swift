import CoreGraphics

/// Maps a swipe to a snap zone by treating the trackpad as a mini-map of the
/// screen: a 3x3 grid of corners, edges and center, plus an upward flick for
/// maximize.
public struct ZoneClassifier: Sendable, Equatable {
    /// Width of the edge bands as a fraction of the trackpad.
    public var edgeFraction: CGFloat
    /// Upward speed, in trackpad heights per second, that counts as a flick.
    public var flickVelocity: CGFloat
    /// Releasing within this distance of the start point cancels the swipe.
    public var deadZoneRadius: CGFloat

    public init(edgeFraction: CGFloat = 1.0 / 3.0, flickVelocity: CGFloat = 2.5, deadZoneRadius: CGFloat = 0.03) {
        self.edgeFraction = edgeFraction
        self.flickVelocity = flickVelocity
        self.deadZoneRadius = deadZoneRadius
    }

    public func zone(for sample: GestureSample) -> SnapZone? {
        if distance(sample.centroid, sample.start) < deadZoneRadius {
            return nil
        }
        let v = sample.velocity
        if v.dy >= flickVelocity, v.dy > 2 * abs(v.dx) {
            return .maximize
        }

        enum Band { case low, middle, high }
        func band(_ value: CGFloat) -> Band {
            if value < edgeFraction { return .low }
            if value > 1 - edgeFraction { return .high }
            return .middle
        }

        switch (band(sample.centroid.x), band(sample.centroid.y)) {
        case (.low, .high): return .topLeft
        case (.middle, .high): return .top
        case (.high, .high): return .topRight
        case (.low, .middle): return .left
        case (.middle, .middle): return .center
        case (.high, .middle): return .right
        case (.low, .low): return .bottomLeft
        case (.middle, .low): return .bottom
        case (.high, .low): return .bottomRight
        }
    }
}
