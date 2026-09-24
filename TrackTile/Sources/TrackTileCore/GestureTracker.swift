import CoreGraphics
import Foundation

/// The state of an active multi-finger swipe, in normalized trackpad space.
public struct GestureSample: Sendable, Equatable {
    public var start: CGPoint
    public var centroid: CGPoint
    /// Trackpad widths/heights per second; positive `dy` is toward the top edge.
    public var velocity: CGVector
    public var fingerCount: Int

    public init(start: CGPoint, centroid: CGPoint, velocity: CGVector, fingerCount: Int) {
        self.start = start
        self.centroid = centroid
        self.velocity = velocity
        self.fingerCount = fingerCount
    }
}

public enum GestureEvent: Sendable, Equatable {
    case began(GestureSample)
    case changed(GestureSample)
    case ended(GestureSample)
    case cancelled
}

/// Turns contact frames into swipe events.
///
/// A swipe begins once an accepted number of fingers has moved further than
/// `activationDistance`. Fingers rarely lift in the same frame, so a drop in
/// the finger count starts a short release phase that ends the gesture with
/// the last sample taken at the full finger count. Adding fingers cancels.
public struct GestureTracker: Sendable {
    public struct Configuration: Sendable, Equatable {
        public var acceptedFingerCounts: Set<Int>
        public var activationDistance: CGFloat
        public var releaseGracePeriod: TimeInterval
        public var velocityWindow: TimeInterval

        public init(
            acceptedFingerCounts: Set<Int> = [4],
            activationDistance: CGFloat = 0.04,
            releaseGracePeriod: TimeInterval = 0.25,
            velocityWindow: TimeInterval = 0.08
        ) {
            self.acceptedFingerCounts = acceptedFingerCounts
            self.activationDistance = activationDistance
            self.releaseGracePeriod = releaseGracePeriod
            self.velocityWindow = velocityWindow
        }
    }

    private enum State: Sendable {
        case idle
        case possible(device: Int, fingers: Int, start: CGPoint)
        case active(device: Int, fingers: Int, last: GestureSample)
        case releasing(device: Int, fingers: Int, last: GestureSample, since: TimeInterval)
        /// Ignores input until every finger has lifted.
        case waitingForLift(device: Int)
    }

    public var configuration: Configuration
    private var state: State = .idle
    private var history: [(time: TimeInterval, point: CGPoint)] = []

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    public var isActive: Bool {
        switch state {
        case .active, .releasing: true
        default: false
        }
    }

    public mutating func process(_ frame: TouchFrame) -> GestureEvent? {
        let count = frame.touches.count
        switch state {
        case .idle:
            beginPossible(frame)
            return nil

        case let .possible(device, fingers, start):
            guard frame.deviceID == device else { return nil }
            guard count == fingers else {
                state = .idle
                beginPossible(frame)
                return nil
            }
            let centroid = frame.centroid
            record(centroid, at: frame.timestamp)
            guard distance(centroid, start) >= configuration.activationDistance else { return nil }
            let sample = GestureSample(start: start, centroid: centroid, velocity: velocity(), fingerCount: fingers)
            state = .active(device: device, fingers: fingers, last: sample)
            return .began(sample)

        case let .active(device, fingers, last):
            guard frame.deviceID == device else { return nil }
            return track(frame, device: device, fingers: fingers, last: last, releasingSince: nil)

        case let .releasing(device, fingers, last, since):
            guard frame.deviceID == device else { return nil }
            return track(frame, device: device, fingers: fingers, last: last, releasingSince: since)

        case let .waitingForLift(device):
            if frame.deviceID == device, count == 0 {
                state = .idle
            }
            return nil
        }
    }

    /// Cancels an active gesture, for example when Esc is pressed.
    public mutating func cancel() -> GestureEvent? {
        switch state {
        case let .active(device, _, _), let .releasing(device, _, _, _):
            state = .waitingForLift(device: device)
            return .cancelled
        case .possible:
            state = .idle
            return nil
        case .idle, .waitingForLift:
            return nil
        }
    }

    private mutating func beginPossible(_ frame: TouchFrame) {
        guard configuration.acceptedFingerCounts.contains(frame.touches.count) else { return }
        let centroid = frame.centroid
        history = [(frame.timestamp, centroid)]
        state = .possible(device: frame.deviceID, fingers: frame.touches.count, start: centroid)
    }

    private mutating func track(
        _ frame: TouchFrame, device: Int, fingers: Int, last: GestureSample, releasingSince: TimeInterval?
    ) -> GestureEvent? {
        let count = frame.touches.count
        if count > fingers {
            state = .waitingForLift(device: device)
            return .cancelled
        }
        if count == 0 {
            state = .idle
            return .ended(last)
        }
        if count < fingers {
            let since = releasingSince ?? frame.timestamp
            if frame.timestamp - since >= configuration.releaseGracePeriod {
                state = .waitingForLift(device: device)
                return .ended(last)
            }
            state = .releasing(device: device, fingers: fingers, last: last, since: since)
            return nil
        }
        let centroid = frame.centroid
        record(centroid, at: frame.timestamp)
        let sample = GestureSample(start: last.start, centroid: centroid, velocity: velocity(), fingerCount: fingers)
        state = .active(device: device, fingers: fingers, last: sample)
        return .changed(sample)
    }

    private mutating func record(_ point: CGPoint, at time: TimeInterval) {
        history.append((time, point))
        let cutoff = time - configuration.velocityWindow
        if let firstKept = history.firstIndex(where: { $0.time >= cutoff }), firstKept > 0 {
            // Keep one sample older than the window so the span covers it fully.
            history.removeFirst(firstKept - 1)
        }
    }

    private func velocity() -> CGVector {
        guard let first = history.first, let last = history.last, last.time > first.time else { return .zero }
        let dt = CGFloat(last.time - first.time)
        return CGVector(dx: (last.point.x - first.point.x) / dt, dy: (last.point.y - first.point.y) / dt)
    }
}

func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    hypot(a.x - b.x, a.y - b.y)
}
