import AppKit
import CMultitouch
import IOKit
import Synchronization
import TrackTileCore

/// Receives raw contact frames from every attached trackpad and forwards them
/// to `onFrame` on the main actor.
///
/// Frames with fewer than two fingers are dropped on the callback thread so
/// normal pointer movement doesn't wake the main thread.
@MainActor
final class MultitouchDevice {
    var onFrame: ((TouchFrame) -> Void)?

    private(set) var isRunning = false
    private(set) var deviceCount = 0

    private var devices: [MTDeviceRef] = []
    private var deviceList: CFArray?
    private var notifyPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var wakeObserver: NSObjectProtocol?
    private var restartWork: DispatchWorkItem?

    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        guard CMTLoad() else { return false }

        Self.installRouter { [weak self] frame in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.onFrame?(frame) }
            }
        }
        startDevices()
        observeDeviceChanges()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRestart() }
        }
        isRunning = true
        return true
    }

    func stop() {
        guard isRunning else { return }
        restartWork?.cancel()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        stopObservingDeviceChanges()
        stopDevices()
        Self.installRouter(nil)
        isRunning = false
    }

    private func startDevices() {
        guard let list = CMTDeviceCreateList() else { return }
        deviceList = list
        devices = (0..<CFArrayGetCount(list)).compactMap { index in
            CFArrayGetValueAtIndex(list, index).map { MTDeviceRef($0) }
        }
        for device in devices {
            CMTRegisterContactFrameCallback(device, contactCallback)
            CMTDeviceStart(device)
        }
        deviceCount = devices.count
    }

    private func stopDevices() {
        for device in devices {
            CMTUnregisterContactFrameCallback(device, contactCallback)
            CMTDeviceStop(device)
        }
        devices = []
        deviceList = nil
        deviceCount = 0
        lastCounts.withLock { $0.removeAll() }
    }

    /// Debounced: plugging in a Magic Trackpad fires several notifications.
    private func scheduleRestart() {
        guard isRunning else { return }
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isRunning else { return }
                self.stopDevices()
                self.startDevices()
            }
        }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: work)
    }

    private func observeDeviceChanges() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        IONotificationPortSetDispatchQueue(port, .main)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { refcon, iterator in
            MultitouchDevice.drain(iterator)
            guard let refcon else { return }
            let device = Unmanaged<MultitouchDevice>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { device.scheduleRestart() }
        }
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(
                port, type, IOServiceMatching("AppleMultitouchDevice"), callback, refcon, &iterator
            )
            guard result == KERN_SUCCESS else { continue }
            // Arms the notification; the existing devices were already started.
            Self.drain(iterator)
            iterators.append(iterator)
        }
    }

    private func stopObservingDeviceChanges() {
        iterators.forEach { IOObjectRelease($0) }
        iterators = []
        if let notifyPort {
            IONotificationPortDestroy(notifyPort)
        }
        notifyPort = nil
    }

    private nonisolated static func drain(_ iterator: io_iterator_t) {
        var object = IOIteratorNext(iterator)
        while object != 0 {
            IOObjectRelease(object)
            object = IOIteratorNext(iterator)
        }
    }

    private nonisolated static func installRouter(_ handler: (@Sendable (TouchFrame) -> Void)?) {
        router.withLock { $0 = handler }
    }
}

private let router = Mutex<(@Sendable (TouchFrame) -> Void)?>(nil)
private let lastCounts = Mutex<[Int: Int]>([:])

private let contactCallback: CMTContactCallback = { device, touches, count, timestamp, _ in
    let deviceID = Int(bitPattern: device)
    var points: [CGPoint] = []
    if let touches, count > 0 {
        points.reserveCapacity(Int(count))
        for touch in UnsafeBufferPointer(start: touches, count: Int(count))
        where touch.state == MTTouchStateMakeTouch || touch.state == MTTouchStateTouching {
            points.append(CGPoint(x: CGFloat(touch.normalized.position.x), y: CGFloat(touch.normalized.position.y)))
        }
    }

    let previous = lastCounts.withLock { counts in
        defer { counts[deviceID] = points.count }
        return counts[deviceID] ?? 0
    }
    guard points.count >= 2 || previous >= 2 else { return 0 }

    let frame = TouchFrame(deviceID: deviceID, timestamp: timestamp, touches: points)
    router.withLock { $0 }?(frame)
    return 0
}
