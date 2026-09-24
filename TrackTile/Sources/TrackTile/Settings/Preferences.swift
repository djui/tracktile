import Foundation
import ServiceManagement
import TrackTileCore

enum FingerMode: String, CaseIterable, Identifiable {
    case three, four, both

    var id: Self { self }

    var fingerCounts: Set<Int> {
        switch self {
        case .three: [3]
        case .four: [4]
        case .both: [3, 4]
        }
    }

    var title: String {
        switch self {
        case .three: "Three fingers"
        case .four: "Four fingers"
        case .both: "Three or four fingers"
        }
    }
}

enum CenterMode: String, CaseIterable, Identifiable {
    case keepSize, fraction

    var id: Self { self }

    var title: String {
        switch self {
        case .keepSize: "Keep window size"
        case .fraction: "Resize to fraction of screen"
        }
    }
}

/// `UserDefaults` keys shared by `@AppStorage` in views and `Preferences`.
enum PreferenceKey {
    static let enabled = "enabled"
    static let fingerMode = "fingerMode"
    static let showOutline = "showOutline"
    static let gap = "gap"
    static let centerMode = "centerMode"
    static let centerFraction = "centerFraction"
    static let flickSensitivity = "flickSensitivity"
    static let showMenuBarIcon = "showMenuBarIcon"
    /// Finger mode and conflict IDs the user was last warned about.
    static let acknowledgedConflicts = "acknowledgedConflicts"
}

/// A snapshot of the user's settings.
struct Preferences: Equatable {
    var enabled: Bool
    var fingerMode: FingerMode
    var showOutline: Bool
    var gap: Double
    var centerMode: CenterMode
    var centerFraction: Double
    /// 0 (needs a hard flick) to 1 (a light flick is enough).
    var flickSensitivity: Double
    var showMenuBarIcon: Bool

    static let defaults = Preferences(
        enabled: true,
        fingerMode: .four,
        showOutline: true,
        gap: 0,
        centerMode: .keepSize,
        centerFraction: 0.6,
        flickSensitivity: 0.5,
        showMenuBarIcon: true
    )

    static func registerDefaults(in store: UserDefaults = .standard) {
        let d = defaults
        store.register(defaults: [
            PreferenceKey.enabled: d.enabled,
            PreferenceKey.fingerMode: d.fingerMode.rawValue,
            PreferenceKey.showOutline: d.showOutline,
            PreferenceKey.gap: d.gap,
            PreferenceKey.centerMode: d.centerMode.rawValue,
            PreferenceKey.centerFraction: d.centerFraction,
            PreferenceKey.flickSensitivity: d.flickSensitivity,
            PreferenceKey.showMenuBarIcon: d.showMenuBarIcon,
        ])
    }

    static func load(from store: UserDefaults = .standard) -> Preferences {
        Preferences(
            enabled: store.bool(forKey: PreferenceKey.enabled),
            fingerMode: FingerMode(rawValue: store.string(forKey: PreferenceKey.fingerMode) ?? "") ?? defaults.fingerMode,
            showOutline: store.bool(forKey: PreferenceKey.showOutline),
            gap: store.double(forKey: PreferenceKey.gap),
            centerMode: CenterMode(rawValue: store.string(forKey: PreferenceKey.centerMode) ?? "") ?? defaults.centerMode,
            centerFraction: store.double(forKey: PreferenceKey.centerFraction),
            flickSensitivity: store.double(forKey: PreferenceKey.flickSensitivity),
            showMenuBarIcon: store.bool(forKey: PreferenceKey.showMenuBarIcon)
        )
    }

    var layoutOptions: LayoutOptions {
        LayoutOptions(
            gap: gap,
            centerSizing: centerMode == .keepSize ? .keepCurrent : .fraction(centerFraction)
        )
    }

    var classifier: ZoneClassifier {
        ZoneClassifier(flickVelocity: 4.0 - 2.5 * min(max(flickSensitivity, 0), 1))
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
