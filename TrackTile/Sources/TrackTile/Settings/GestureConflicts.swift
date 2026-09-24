import AppKit

/// A macOS trackpad gesture that fires on the same swipe as TrackTile.
struct GestureConflict: Identifiable, Hashable {
    let id: String
    let fingers: Int
    let description: String
    let location: String
}

enum GestureConflicts {
    /// Built-in and Bluetooth (Magic Trackpad) settings are stored separately.
    private static let domains = [
        "com.apple.AppleMultitouchTrackpad",
        "com.apple.driver.AppleBluetoothMultitouch.trackpad",
    ]

    private static let known: [(key: String, fingers: Int, description: String, location: String)] = [
        ("TrackpadThreeFingerDrag", 3, "Three-finger drag", "Accessibility > Pointer Control > Trackpad Options"),
        ("TrackpadThreeFingerVertSwipeGesture", 3, "Mission Control and App Exposé with three fingers", "Trackpad > More Gestures"),
        ("TrackpadThreeFingerHorizSwipeGesture", 3, "Swipe between pages or full-screen apps with three fingers", "Trackpad > More Gestures"),
        ("TrackpadFourFingerVertSwipeGesture", 4, "Mission Control and App Exposé with four fingers", "Trackpad > More Gestures"),
        ("TrackpadFourFingerHorizSwipeGesture", 4, "Swipe between full-screen apps with four fingers", "Trackpad > More Gestures"),
    ]

    static func detect(for fingerCounts: Set<Int>) -> [GestureConflict] {
        domains.forEach { CFPreferencesAppSynchronize($0 as CFString) }
        return known.compactMap { entry in
            guard fingerCounts.contains(entry.fingers) else { return nil }
            let enabled = domains.contains { domain in
                let value = CFPreferencesCopyAppValue(entry.key as CFString, domain as CFString)
                return (value as? Int ?? 0) != 0
            }
            guard enabled else { return nil }
            return GestureConflict(id: entry.key, fingers: entry.fingers, description: entry.description, location: entry.location)
        }
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
