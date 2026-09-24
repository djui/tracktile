/// A macOS trackpad gesture that fires on the same swipe as TrackTile.
public struct GestureConflict: Identifiable, Hashable, Sendable {
    public let id: String
    public let fingers: Int
    public let description: String
    public let location: String
    /// Dock swipes that TrackTile can block while one of its swipes is active.
    public let suppressible: Bool

    public init(id: String, fingers: Int, description: String, location: String, suppressible: Bool) {
        self.id = id
        self.fingers = fingers
        self.description = description
        self.location = location
        self.suppressible = suppressible
    }
}

/// Decides which macOS gestures clash with TrackTile, from raw preference values.
///
/// macOS stores one swipe flag per finger count and direction in the trackpad
/// domains (`com.apple.AppleMultitouchTrackpad` and the Bluetooth variant).
/// The vertical flag is shared by Mission Control and App Exposé; whether each
/// feature is on is stored separately in `com.apple.dock`, and a missing Dock
/// key means enabled. macOS keeps the four-finger flags on while the
/// three-finger variants are selected.
public enum ConflictRules {
    public static let trackpadLocation = "Trackpad > More Gestures"
    public static let pointerLocation = "Accessibility > Pointer Control > Trackpad Options"

    /// - Parameters:
    ///   - trackpad: Value of a trackpad key, or nil if unset.
    ///   - dock: Value of a `com.apple.dock` key, or nil if unset.
    public static func conflicts(
        for fingerCounts: Set<Int>,
        trackpad: (String) -> Int?,
        dock: (String) -> Int?
    ) -> [GestureConflict] {
        var result: [GestureConflict] = []

        if fingerCounts.contains(3), (trackpad("TrackpadThreeFingerDrag") ?? 0) != 0 {
            result.append(GestureConflict(
                id: "threeFingerDrag", fingers: 3, description: "Three-finger drag",
                location: pointerLocation, suppressible: false
            ))
        }

        let missionControlOn = (dock("showMissionControlGestureEnabled") ?? 1) != 0
        let appExposeOn = (dock("showAppExposeGestureEnabled") ?? 1) != 0

        for (fingers, word) in [(3, "Three"), (4, "Four")] where fingerCounts.contains(fingers) {
            let spelled = word.lowercased()
            if (trackpad("Trackpad\(word)FingerVertSwipeGesture") ?? 0) != 0 {
                if missionControlOn {
                    result.append(GestureConflict(
                        id: "missionControl.\(fingers)", fingers: fingers,
                        description: "Mission Control (swipe up with \(spelled) fingers)",
                        location: trackpadLocation, suppressible: true
                    ))
                }
                if appExposeOn {
                    result.append(GestureConflict(
                        id: "appExpose.\(fingers)", fingers: fingers,
                        description: "App Exposé (swipe down with \(spelled) fingers)",
                        location: trackpadLocation, suppressible: true
                    ))
                }
            }

            switch trackpad("Trackpad\(word)FingerHorizSwipeGesture") ?? 0 {
            case 0:
                break
            // 1 is "Swipe between pages" (three fingers only): scroll events apps handle.
            case 1 where fingers == 3:
                result.append(GestureConflict(
                    id: "swipePages.\(fingers)", fingers: fingers,
                    description: "Swipe between pages with three fingers",
                    location: trackpadLocation, suppressible: false
                ))
            default:
                result.append(GestureConflict(
                    id: "fullScreenApps.\(fingers)", fingers: fingers,
                    description: "Swipe between full-screen apps and Spaces with \(spelled) fingers",
                    location: trackpadLocation, suppressible: true
                ))
            }
        }
        return result
    }
}
