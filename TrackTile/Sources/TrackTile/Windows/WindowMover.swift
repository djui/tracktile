import AppKit
import ApplicationServices
import TrackTileCore

/// A window captured at the start of a swipe.
struct TargetWindow {
    let element: AXUIElement
    let pid: pid_t
    /// Current frame in Cocoa coordinates.
    let frame: CGRect
    let screen: NSScreen
    let isResizable: Bool
}

enum WindowLookup {
    case found(TargetWindow)
    /// A window was hit but can't be snapped; carries its frame for feedback.
    case unsupported(CGRect?, NSScreen)
    case none
}

/// Finds and moves windows through the Accessibility API.
@MainActor
enum WindowMover {
    private static let systemWide: AXUIElement = {
        let element = AXUIElementCreateSystemWide()
        // Unresponsive apps would otherwise block the main thread for seconds.
        AXUIElementSetMessagingTimeout(element, 0.25)
        return element
    }()

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func windowUnderPointer() -> WindowLookup {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main else {
            return .none
        }
        let axPoint = ScreenGeometry.flip(pointer, primaryScreenHeight: primaryScreenHeight)

        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(axPoint.x), Float(axPoint.y), &hit) == .success,
              let hit, let window = window(containing: hit)
        else { return .none }

        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        guard pid != ProcessInfo.processInfo.processIdentifier else { return .none }

        let frame = frame(of: window)
        let fullScreen: Bool = attribute(window, "AXFullScreen") ?? false
        let positionSettable = isSettable(window, kAXPositionAttribute)
        guard let frame, !fullScreen, positionSettable else {
            return .unsupported(frame, screen)
        }
        return .found(TargetWindow(
            element: window,
            pid: pid,
            frame: frame,
            screen: screen,
            isResizable: isSettable(window, kAXSizeAttribute)
        ))
    }

    /// Moves `window` to `frame` (Cocoa coordinates). Returns false if the app refused.
    @discardableResult
    static func move(_ window: TargetWindow, to frame: CGRect) -> Bool {
        let app = AXUIElementCreateApplication(window.pid)
        // Enhanced UI mode (set by assistive apps) makes some apps animate and
        // clamp every size change; disable it for the duration of the move.
        let enhanced: Bool = attribute(app, "AXEnhancedUserInterface") ?? false
        if enhanced {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
        }
        defer {
            if enhanced {
                AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            }
        }

        let axFrame = ScreenGeometry.flip(frame, primaryScreenHeight: primaryScreenHeight)
        var origin = axFrame.origin
        var size = axFrame.size
        guard let position = AXValueCreate(.cgPoint, &origin), let sizeValue = AXValueCreate(.cgSize, &size) else {
            return false
        }
        // Size first so a shrinking window fits where it's going, then position,
        // then size again for apps that clamped the first resize to the old screen.
        if window.isResizable {
            AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, sizeValue)
        }
        let moved = AXUIElementSetAttributeValue(window.element, kAXPositionAttribute as CFString, position) == .success
        if window.isResizable {
            AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, sizeValue)
        }
        return moved
    }

    static var primaryScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    private static func window(containing element: AXUIElement) -> AXUIElement? {
        if let window: AXUIElement = attribute(element, kAXWindowAttribute) {
            return window
        }
        var current: AXUIElement? = element
        while let candidate = current {
            if let role: String = attribute(candidate, kAXRoleAttribute), role == kAXWindowRole {
                return candidate
            }
            current = attribute(candidate, kAXParentAttribute)
        }
        return nil
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        guard let positionValue: AXValue = attribute(window, kAXPositionAttribute),
              let sizeValue: AXValue = attribute(window, kAXSizeAttribute)
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &origin), AXValueGetValue(sizeValue, .cgSize, &size) else {
            return nil
        }
        return ScreenGeometry.flip(CGRect(origin: origin, size: size), primaryScreenHeight: primaryScreenHeight)
    }

    private static func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else { return nil }
        // Casts to CF types are unchecked, so verify the type ID explicitly.
        if T.self == AXUIElement.self, CFGetTypeID(value) != AXUIElementGetTypeID() { return nil }
        if T.self == AXValue.self, CFGetTypeID(value) != AXValueGetTypeID() { return nil }
        return value as? T
    }
}
