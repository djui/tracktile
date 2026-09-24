import AppKit
import ApplicationServices
import Observation
import TrackTileCore

/// Connects trackpad input to the outline preview and window moves.
@MainActor
@Observable
final class SnapCoordinator {
    private(set) var isTrusted = WindowMover.isTrusted
    private(set) var trackpadCount = 0
    private(set) var multitouchAvailable = true
    private(set) var lastZone: SnapZone?
    /// macOS gestures that use the configured finger count.
    private(set) var conflicts: [GestureConflict] = []
    /// Whether the Dock swipe event tap is installed.
    private(set) var isBlockingSystemSwipes = false

    /// Conflicts that still need the user's attention.
    var activeConflicts: [GestureConflict] {
        conflicts.filter { !isBlocked($0) }
    }

    func isBlocked(_ conflict: GestureConflict) -> Bool {
        conflict.suppressible && isBlockingSystemSwipes
    }

    /// Called when new conflicts appear that the user hasn't been shown yet.
    @ObservationIgnored var onConflictsNeedAttention: (() -> Void)?

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: PreferenceKey.enabled)
            updateRunning()
        }
    }

    @ObservationIgnored private var preferences: Preferences
    @ObservationIgnored private let touch = MultitouchDevice()
    @ObservationIgnored private let overlay = OverlayController()
    @ObservationIgnored private var tracker = GestureTracker()
    @ObservationIgnored private var session: Session?
    @ObservationIgnored private var trustTimer: Timer?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var conflictTimer: Timer?

    private struct Session {
        let window: TargetWindow
        var zone: SnapZone?
    }

    init() {
        Preferences.registerDefaults()
        preferences = Preferences.load()
        isEnabled = preferences.enabled
        applyTrackerConfiguration()
    }

    func start() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadPreferences() }
        }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return } // Esc
            MainActor.assumeIsolated { self?.cancelGesture() }
        }
        // Users usually fix conflicts in System Settings and then come back.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshConflicts() }
        }
        // macOS posts no notification when trackpad gestures change.
        conflictTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshConflicts() }
        }
        touch.onFrame = { [weak self] frame in self?.handle(frame) }

        if !isTrusted {
            requestAccessibility()
        }
        updateRunning()
        refreshConflicts()
    }

    /// Re-reads the macOS trackpad settings and warns once per new set of conflicts.
    func refreshConflicts() {
        let mode = preferences.fingerMode
        let detected = GestureConflicts.detect(for: mode.fingerCounts)
        if detected != conflicts {
            conflicts = detected
        }
        let active = activeConflicts
        guard !active.isEmpty else {
            UserDefaults.standard.removeObject(forKey: PreferenceKey.acknowledgedConflicts)
            return
        }
        // Accessibility onboarding comes first; warn once that's done.
        guard isTrusted else { return }
        let signature = ([mode.rawValue] + active.map(\.id).sorted()).joined(separator: ",")
        guard UserDefaults.standard.string(forKey: PreferenceKey.acknowledgedConflicts) != signature else { return }
        UserDefaults.standard.set(signature, forKey: PreferenceKey.acknowledgedConflicts)
        onConflictsNeedAttention?()
    }

    /// Conflicts `mode` would have, excluding those TrackTile blocks.
    func activeConflicts(for mode: FingerMode) -> [GestureConflict] {
        GestureConflicts.detect(for: mode.fingerCounts).filter { !isBlocked($0) }
    }

    /// A finger count that doesn't clash with any enabled macOS gesture.
    var conflictFreeAlternative: FingerMode? {
        [FingerMode.four, .three]
            .filter { $0 != preferences.fingerMode }
            .first { activeConflicts(for: $0).isEmpty }
    }

    /// Shows the system prompt and polls until the user grants access.
    func requestAccessibility() {
        // The value of `kAXTrustedCheckOptionPrompt`, which Swift 6 flags as unsafe shared state.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        guard !isTrusted, trustTimer == nil else { return }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, WindowMover.isTrusted else { return }
                self.isTrusted = true
                self.trustTimer?.invalidate()
                self.trustTimer = nil
                self.updateRunning()
                self.refreshConflicts()
            }
        }
    }

    private func updateRunning() {
        if isEnabled, isTrusted {
            multitouchAvailable = touch.start()
        } else {
            cancelGesture()
            touch.stop()
        }
        trackpadCount = touch.deviceCount

        if isEnabled, isTrusted, preferences.blockSystemSwipes {
            isBlockingSystemSwipes = DockSwipeGuard.shared.start()
        } else {
            DockSwipeGuard.shared.stop()
            isBlockingSystemSwipes = false
        }
    }

    private func reloadPreferences() {
        let updated = Preferences.load()
        guard updated != preferences else { return }
        let fingerModeChanged = updated.fingerMode != preferences.fingerMode
        let blockingChanged = updated.blockSystemSwipes != preferences.blockSystemSwipes
        preferences = updated
        applyTrackerConfiguration()
        if isEnabled != updated.enabled {
            isEnabled = updated.enabled
        } else if blockingChanged {
            updateRunning()
        }
        if fingerModeChanged || blockingChanged {
            refreshConflicts()
        }
    }

    private func applyTrackerConfiguration() {
        tracker.configuration.acceptedFingerCounts = preferences.fingerMode.fingerCounts
        DockSwipeGuard.shared.setAcceptedFingerCounts(preferences.fingerMode.fingerCounts)
    }

    private func handle(_ frame: TouchFrame) {
        trackpadCount = touch.deviceCount
        guard let event = tracker.process(frame) else { return }
        handle(event)
    }

    private func handle(_ event: GestureEvent) {
        switch event {
        case let .began(sample):
            begin(sample)
        case let .changed(sample):
            update(sample)
        case let .ended(sample):
            finish(sample)
        case .cancelled:
            session = nil
            overlay.hide()
        }
    }

    private func cancelGesture() {
        if let event = tracker.cancel() {
            handle(event)
        }
    }

    private func begin(_ sample: GestureSample) {
        switch WindowMover.windowUnderPointer() {
        case let .found(window):
            session = Session(window: window)
            if preferences.showOutline {
                overlay.begin(from: window.frame, on: window.screen)
            }
            update(sample)
        case let .unsupported(frame, screen):
            _ = tracker.cancel()
            reject(frame, on: screen)
        case .none:
            _ = tracker.cancel()
        }
    }

    private func update(_ sample: GestureSample) {
        guard var session else { return }
        let zone = allowedZone(for: sample, window: session.window)
        guard zone != session.zone else { return }
        session.zone = zone
        self.session = session

        guard preferences.showOutline else { return }
        let window = session.window
        if let zone {
            overlay.show(targetFrame(for: zone, window: window), label: zone.displayName, on: window.screen)
        } else {
            overlay.begin(from: window.frame, on: window.screen)
        }
    }

    private func finish(_ sample: GestureSample) {
        guard let window = session?.window else { return }
        session = nil
        guard let zone = allowedZone(for: sample, window: window) else {
            // Swiping a non-resizable window toward a zone it can't take.
            if !window.isResizable, preferences.classifier.zone(for: sample) != nil {
                reject(window.frame, on: window.screen)
            } else {
                overlay.hide()
            }
            return
        }
        if WindowMover.move(window, to: targetFrame(for: zone, window: window)) {
            lastZone = zone
            overlay.hide()
        } else {
            reject(window.frame, on: window.screen)
        }
    }

    /// Non-resizable windows can only be centered at their own size.
    private func allowedZone(for sample: GestureSample, window: TargetWindow) -> SnapZone? {
        guard let zone = preferences.classifier.zone(for: sample) else { return nil }
        if window.isResizable { return zone }
        return zone == .center && preferences.centerMode == .keepSize ? zone : nil
    }

    private func targetFrame(for zone: SnapZone, window: TargetWindow) -> CGRect {
        zone.frame(in: window.screen.visibleFrame, currentSize: window.frame.size, options: preferences.layoutOptions)
    }

    private func reject(_ frame: CGRect?, on screen: NSScreen) {
        if preferences.showOutline {
            overlay.reject(frame, on: screen)
        } else {
            NSSound.beep()
        }
    }
}
