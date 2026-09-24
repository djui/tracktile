import AppKit
import SwiftUI

/// Owns the Settings and About windows.
///
/// These are AppKit windows rather than SwiftUI scenes because they must open
/// from the app delegate (on reopen) when the menu bar icon is hidden, and
/// SwiftUI's `openSettings`/`openWindow` actions need a view to call them from.
@MainActor
final class WindowPresenter {
    private let coordinator: SnapCoordinator
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?

    init(coordinator: SnapCoordinator) {
        self.coordinator = coordinator
    }

    enum SettingsTab: Int {
        case general, gestures, layout
    }

    /// Shows Settings, switching to `tab` if given and otherwise keeping the current one.
    func showSettings(tab: SettingsTab? = nil) {
        if settingsWindow == nil {
            settingsWindow = makeSettingsWindow()
        }
        if let tab, let tabs = settingsWindow?.contentViewController as? NSTabViewController {
            tabs.selectedTabViewItemIndex = tab.rawValue
        }
        present(settingsWindow)
    }

    /// Toolbar-style tabs like the system Settings scene.
    private func makeSettingsWindow() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.canPropagateSelectedChildViewControllerTitle = true
        tabs.addTabViewItem(pane("General", symbol: "gearshape", GeneralSettings(coordinator: coordinator, presenter: self)))
        tabs.addTabViewItem(pane("Gestures", symbol: "hand.draw", GestureSettings(coordinator: coordinator)))
        tabs.addTabViewItem(pane("Layout", symbol: "rectangle.split.2x2", LayoutSettings()))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func pane(_ title: String, symbol: String, _ content: some View) -> NSTabViewItem {
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = .preferredContentSize
        controller.title = title
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    func showAbout() {
        if aboutWindow == nil {
            aboutWindow = makeWindow(title: "About TrackTile", content: AboutView())
        }
        present(aboutWindow)
    }

    private func makeWindow(title: String, content: some View) -> NSWindow {
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
