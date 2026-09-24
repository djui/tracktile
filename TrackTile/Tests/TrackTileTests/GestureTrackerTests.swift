import CoreGraphics
import Testing
@testable import TrackTileCore

private func frame(_ time: Double, _ fingers: Int, at point: CGPoint, device: Int = 1) -> TouchFrame {
    // Spread fingers horizontally around the centroid.
    let touches = (0..<fingers).map { i in
        CGPoint(x: point.x + (CGFloat(i) - CGFloat(fingers - 1) / 2) * 0.05, y: point.y)
    }
    return TouchFrame(deviceID: device, timestamp: time, touches: touches)
}

struct GestureTrackerTests {
    @Test func ignoresUnacceptedFingerCounts() {
        var tracker = GestureTracker(configuration: .init(acceptedFingerCounts: [4]))
        #expect(tracker.process(frame(0, 3, at: CGPoint(x: 0.5, y: 0.5))) == nil)
        #expect(tracker.process(frame(0.1, 3, at: CGPoint(x: 0.9, y: 0.9))) == nil)
        #expect(!tracker.isActive)
    }

    @Test func beginsAfterActivationDistance() throws {
        var tracker = GestureTracker(configuration: .init(acceptedFingerCounts: [4], activationDistance: 0.05))
        #expect(tracker.process(frame(0, 4, at: CGPoint(x: 0.5, y: 0.5))) == nil)
        #expect(tracker.process(frame(0.01, 4, at: CGPoint(x: 0.52, y: 0.5))) == nil)
        let event = tracker.process(frame(0.02, 4, at: CGPoint(x: 0.6, y: 0.5)))
        guard case let .began(sample) = event else {
            Issue.record("expected began, got \(String(describing: event))")
            return
        }
        #expect(abs(sample.start.x - 0.5) < 0.0001)
        #expect(abs(sample.centroid.x - 0.6) < 0.0001)
        #expect(sample.fingerCount == 4)
        #expect(tracker.isActive)
    }

    @Test func staggeredLiftEndsWithLastFullSample() {
        var tracker = GestureTracker(configuration: .init(acceptedFingerCounts: [3]))
        _ = tracker.process(frame(0, 3, at: CGPoint(x: 0.5, y: 0.5)))
        _ = tracker.process(frame(0.02, 3, at: CGPoint(x: 0.2, y: 0.8)))
        _ = tracker.process(frame(0.04, 3, at: CGPoint(x: 0.1, y: 0.9)))
        #expect(tracker.process(frame(0.05, 2, at: CGPoint(x: 0.4, y: 0.4))) == nil)
        #expect(tracker.process(frame(0.06, 1, at: CGPoint(x: 0.4, y: 0.4))) == nil)
        let event = tracker.process(frame(0.07, 0, at: .zero))
        guard case let .ended(sample) = event else {
            Issue.record("expected ended, got \(String(describing: event))")
            return
        }
        #expect(abs(sample.centroid.x - 0.1) < 0.0001)
        #expect(abs(sample.centroid.y - 0.9) < 0.0001)
    }

    @Test func releaseGraceEndsWhenAFingerStaysDown() {
        var tracker = GestureTracker(configuration: .init(acceptedFingerCounts: [4], releaseGracePeriod: 0.2))
        _ = tracker.process(frame(0, 4, at: CGPoint(x: 0.5, y: 0.5)))
        _ = tracker.process(frame(0.02, 4, at: CGPoint(x: 0.8, y: 0.5)))
        #expect(tracker.process(frame(0.05, 1, at: CGPoint(x: 0.8, y: 0.5))) == nil)
        guard case .ended = tracker.process(frame(0.3, 1, at: CGPoint(x: 0.8, y: 0.5))) else {
            Issue.record("expected ended after grace period")
            return
        }
        // The resting finger must not start a new gesture.
        #expect(tracker.process(frame(0.4, 4, at: CGPoint(x: 0.1, y: 0.1))) == nil)
        #expect(!tracker.isActive)
    }

    @Test func addingFingersCancels() {
        var tracker = GestureTracker(configuration: .init(acceptedFingerCounts: [3, 4]))
        _ = tracker.process(frame(0, 3, at: CGPoint(x: 0.5, y: 0.5)))
        _ = tracker.process(frame(0.02, 3, at: CGPoint(x: 0.8, y: 0.5)))
        #expect(tracker.process(frame(0.03, 4, at: CGPoint(x: 0.8, y: 0.5))) == .cancelled)
        #expect(tracker.process(frame(0.2, 4, at: CGPoint(x: 0.2, y: 0.5))) == nil)
        #expect(tracker.process(frame(0.3, 0, at: .zero)) == nil)
    }

    @Test func externalCancelWaitsForLift() {
        var tracker = GestureTracker(configuration: .init(acceptedFingerCounts: [4]))
        _ = tracker.process(frame(0, 4, at: CGPoint(x: 0.5, y: 0.5)))
        _ = tracker.process(frame(0.02, 4, at: CGPoint(x: 0.8, y: 0.5)))
        #expect(tracker.cancel() == .cancelled)
        #expect(tracker.process(frame(0.03, 4, at: CGPoint(x: 0.2, y: 0.5))) == nil)
        #expect(tracker.process(frame(0.04, 0, at: .zero)) == nil)
        #expect(tracker.process(frame(0.05, 4, at: CGPoint(x: 0.5, y: 0.5))) == nil)
        guard case .began = tracker.process(frame(0.06, 4, at: CGPoint(x: 0.8, y: 0.5))) else {
            Issue.record("expected a new gesture after lifting")
            return
        }
    }

    @Test func ignoresOtherDevicesWhileTracking() {
        var tracker = GestureTracker(configuration: .init(acceptedFingerCounts: [4]))
        _ = tracker.process(frame(0, 4, at: CGPoint(x: 0.5, y: 0.5), device: 1))
        _ = tracker.process(frame(0.02, 4, at: CGPoint(x: 0.8, y: 0.5), device: 1))
        #expect(tracker.process(frame(0.03, 0, at: .zero, device: 2)) == nil)
        #expect(tracker.isActive)
    }

    @Test func measuresUpwardVelocity() {
        var tracker = GestureTracker(configuration: .init(acceptedFingerCounts: [4], velocityWindow: 0.05))
        _ = tracker.process(frame(0, 4, at: CGPoint(x: 0.5, y: 0.3)))
        var last: GestureEvent?
        for step in 1...10 {
            last = tracker.process(frame(Double(step) * 0.01, 4, at: CGPoint(x: 0.5, y: 0.3 + CGFloat(step) * 0.04)))
        }
        guard case let .changed(sample) = last else {
            Issue.record("expected changed")
            return
        }
        #expect(abs(sample.velocity.dy - 4) < 0.01)
        #expect(abs(sample.velocity.dx) < 0.01)
    }
}
