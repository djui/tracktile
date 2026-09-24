import CoreGraphics
import Foundation

/// One contact frame from a trackpad, reduced to the fingers that are touching.
///
/// Positions are normalized to the trackpad surface: `(0, 0)` is the
/// bottom-left corner and `(1, 1)` is the top-right corner.
public struct TouchFrame: Sendable, Equatable {
    public var deviceID: Int
    public var timestamp: TimeInterval
    public var touches: [CGPoint]

    public init(deviceID: Int, timestamp: TimeInterval, touches: [CGPoint]) {
        self.deviceID = deviceID
        self.timestamp = timestamp
        self.touches = touches
    }

    public var centroid: CGPoint {
        guard !touches.isEmpty else { return .zero }
        let sum = touches.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let n = CGFloat(touches.count)
        return CGPoint(x: sum.x / n, y: sum.y / n)
    }
}
