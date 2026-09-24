import AppKit
import TrackTileCore

/// Reads the macOS gesture settings and opens the related System Settings panes.
enum GestureConflicts {
    /// Built-in and Bluetooth (Magic Trackpad) settings are stored separately.
    private static let trackpadDomains = [
        "com.apple.AppleMultitouchTrackpad",
        "com.apple.driver.AppleBluetoothMultitouch.trackpad",
    ]
    private static let dockDomain = "com.apple.dock"

    static func detect(for fingerCounts: Set<Int>) -> [GestureConflict] {
        (trackpadDomains + [dockDomain]).forEach { CFPreferencesAppSynchronize($0 as CFString) }
        return ConflictRules.conflicts(
            for: fingerCounts,
            trackpad: { key in
                // A gesture is on if either trackpad type has it on.
                trackpadDomains.compactMap { value(key, in: $0) }.max()
            },
            dock: { value($0, in: dockDomain) }
        )
    }

    private static func value(_ key: String, in domain: String) -> Int? {
        let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString)
        if let number = value as? Int { return number }
        if let flag = value as? Bool { return flag ? 1 : 0 }
        return nil
    }

    static func openTrackpadSettings() {
        open("x-apple.systempreferences:com.apple.Trackpad-Settings.extension")
    }

    static func openAccessibilityPointerSettings() {
        open("x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Pointer")
    }

    static func openAccessibilityPrivacySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func open(_ url: String) {
        if let url = URL(string: url) {
            NSWorkspace.shared.open(url)
        }
    }
}
