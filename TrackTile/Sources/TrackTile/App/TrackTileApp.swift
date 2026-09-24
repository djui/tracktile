import AppKit
import SwiftUI

@main
struct TrackTileApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(PreferenceKey.showMenuBarIcon) private var showMenuBarIcon = Preferences.defaults.showMenuBarIcon

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuContent(coordinator: appDelegate.coordinator, presenter: appDelegate.presenter)
        } label: {
            MenuBarIcon(coordinator: appDelegate.coordinator)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = SnapCoordinator()
    private(set) lazy var presenter = WindowPresenter(coordinator: coordinator)

    func applicationDidFinishLaunching(_: Notification) {
        coordinator.onConflictsNeedAttention = { [weak self] in
            self?.presenter.showSettings(tab: .gestures)
        }
        coordinator.start()
        if !coordinator.isTrusted {
            presenter.showSettings()
        }    }

    /// Opening the app while it's running (Finder, Spotlight, `open`) shows
    /// Settings, so it stays reachable with the menu bar icon hidden.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        presenter.showSettings()
        return false
    }
}

private struct MenuBarIcon: View {
    let coordinator: SnapCoordinator

    var body: some View {
        Image(systemName: symbol)
            .accessibilityLabel("TrackTile")
    }

    private var symbol: String {
        if !coordinator.isTrusted { return "exclamationmark.triangle" }
        return coordinator.isEnabled ? "rectangle.split.2x2" : "rectangle.dashed"
    }
}

private struct MenuContent: View {
    @Bindable var coordinator: SnapCoordinator
    let presenter: WindowPresenter

    var body: some View {
        Toggle("Snap with Trackpad Swipes", isOn: $coordinator.isEnabled)

        if !coordinator.isTrusted {
            Divider()
            Text("Accessibility access required")
            Button("Grant Accessibility Access…") {
                coordinator.requestAccessibility()
                GestureConflicts.openAccessibilityPrivacySettings()
            }
        } else if !coordinator.multitouchAvailable {
            Divider()
            Text("Trackpad input unavailable")
        } else if !coordinator.conflicts.isEmpty {
            Divider()
            Button {
                presenter.showSettings(tab: .gestures)
            } label: {
                Label(
                    coordinator.conflicts.count == 1
                        ? "1 conflicting macOS gesture…"
                        : "\(coordinator.conflicts.count) conflicting macOS gestures…",
                    systemImage: "exclamationmark.triangle"
                )
            }
        } else if let zone = coordinator.lastZone {
            Divider()
            Text("Last snap: \(zone.displayName)")
        }

        Divider()
        Button("About TrackTile") { presenter.showAbout() }
        Button("Settings…") { presenter.showSettings() }
            .keyboardShortcut(",")

        Divider()
        Button("Quit TrackTile") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
