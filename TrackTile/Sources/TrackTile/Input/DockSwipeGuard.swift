import CoreGraphics
import Foundation
import os
import Synchronization

/// Swallows the WindowServer's Dock swipe events (Mission Control, App Exposé,
/// Spaces) that start while TrackTile's finger count is on the trackpad.
///
/// Event types and fields are undocumented (CGSEventTypes): type 30 is a Dock
/// control event, field 110 its HID event type (23 = Dock swipe) and field 132
/// the phase. Only whole sequences are swallowed so the Dock never sees a
/// swipe without its end.
final class DockSwipeGuard: @unchecked Sendable {
    static let shared = DockSwipeGuard()

    private struct State {
        var fingerCount = 0
        var acceptedFingerCounts: Set<Int> = []
        var swallowing = false
        /// macOS sometimes sends both a cancel and an end; the stray second
        /// one must follow the fate of its sequence.
        var lastSequenceSwallowed = false
    }

    private enum Raw {
        static let gestureType: UInt32 = 29
        static let dockControlType: UInt32 = 30
        static let hidTypeField: UInt32 = 110
        static let phaseField: UInt32 = 132
        static let dockSwipeHIDType: Int64 = 23
        static let phaseBegan: Int64 = 1
        static let phaseEnded: Int64 = 4
        static let phaseCancelled: Int64 = 8
    }

    private let state = Mutex(State())
    /// Guards `port` and `runLoop`.
    private let tapLock = NSLock()
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    fileprivate static let log = Logger(subsystem: "com.djui.tracktile", category: "dockswipe")

    var isRunning: Bool { tapLock.withLock { port != nil } }

    /// Called from the multitouch callback thread on every frame.
    func setFingerCount(_ count: Int) {
        state.withLock { $0.fingerCount = count }
    }

    func setAcceptedFingerCounts(_ counts: Set<Int>) {
        state.withLock { $0.acceptedFingerCounts = counts }
    }

    /// Installs the event tap. Returns false if macOS refused it (no Accessibility access).
    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        let mask = CGEventMask(1) << Raw.gestureType | CGEventMask(1) << Raw.dockControlType
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: dockSwipeTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Self.log.error("Event tap could not be created")
            return false
        }
        tapLock.withLock { self.port = port }
        state.withLock { $0.swallowing = false }

        // A dedicated run loop keeps the tap responsive while the main thread
        // waits on slow Accessibility calls; macOS disables slow taps.
        let thread = Thread { [self] in
            let runLoop = CFRunLoopGetCurrent()
            guard let port = tapLock.withLock({ () -> CFMachPort? in
                self.runLoop = runLoop
                return self.port
            }) else { return }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()
        }
        thread.name = "TrackTile.DockSwipeGuard"
        thread.qualityOfService = .userInteractive
        thread.start()
        Self.log.info("Dock swipe guard started")
        return true
    }

    func stop() {
        let (port, runLoop) = tapLock.withLock {
            defer {
                self.port = nil
                self.runLoop = nil
            }
            return (self.port, self.runLoop)
        }
        state.withLock { $0.swallowing = false }
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
        Self.log.info("Dock swipe guard stopped")
    }

    /// Returns true if `event` should be dropped.
    fileprivate func shouldSwallow(type: UInt32, event: CGEvent) -> Bool {
        let hidType = event.getIntegerValueField(Self.field(Raw.hidTypeField))
        let phase = event.getIntegerValueField(Self.field(Raw.phaseField))

        let isDockSwipe = type == Raw.dockControlType && hidType == Raw.dockSwipeHIDType
        let (swallow, fingers) = state.withLock { state -> (Bool, Int) in
            if isDockSwipe {
                switch phase {
                case Raw.phaseBegan:
                    state.swallowing = state.acceptedFingerCounts.contains(state.fingerCount)
                    state.lastSequenceSwallowed = state.swallowing
                    return (state.swallowing, state.fingerCount)
                case Raw.phaseEnded, Raw.phaseCancelled:
                    state.swallowing = false
                    return (state.lastSequenceSwallowed, state.fingerCount)
                default:
                    return (state.swallowing, state.fingerCount)
                }
            }
            // Gesture events belonging to a swallowed swipe go too.
            return (type == Raw.gestureType && state.swallowing, state.fingerCount)
        }

        if isDockSwipe {
            Self.log.debug("Dock swipe phase=\(phase) fingers=\(fingers) swallow=\(swallow)")
        } else if hidType != 0 {
            Self.log.debug("Gesture event type=\(type) hid=\(hidType) phase=\(phase) swallow=\(swallow)")
        }
        return swallow
    }

    fileprivate func reenable() {
        guard let port = tapLock.withLock({ self.port }) else { return }
        CGEvent.tapEnable(tap: port, enable: true)
        Self.log.info("Event tap re-enabled")
    }

    private static func field(_ raw: UInt32) -> CGEventField {
        // CGEventField is a UInt32-backed C enum; these fields are undeclared.
        unsafeBitCast(raw, to: CGEventField.self)
    }
}

private func dockSwipeTapCallback(
    proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let guardInstance = Unmanaged<DockSwipeGuard>.fromOpaque(refcon).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        guardInstance.reenable()
    default:
        if guardInstance.shouldSwallow(type: type.rawValue, event: event) {
            return nil
        }
    }
    return Unmanaged.passUnretained(event)
}
