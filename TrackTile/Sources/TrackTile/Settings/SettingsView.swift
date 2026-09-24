import SwiftUI
import TrackTileCore

/// Width shared by all settings panes so the window only changes height.
let settingsPaneWidth: CGFloat = 520

struct GeneralSettings: View {
    @Bindable var coordinator: SnapCoordinator
    let presenter: WindowPresenter
    @AppStorage(PreferenceKey.showMenuBarIcon) private var showMenuBarIcon = Preferences.defaults.showMenuBarIcon
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section {
                PermissionsView(coordinator: coordinator)
            }
            Section {
                Toggle("Snap windows with trackpad swipes", isOn: $coordinator.isEnabled)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LaunchAtLogin.set(enabled)
                            launchError = nil
                        } catch {
                            launchError = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
                Toggle(isOn: $showMenuBarIcon) {
                    Text("Show menu bar icon")
                    Text("When hidden, open TrackTile again from Finder or Spotlight to show this window.")
                }
            }
            Section("Status") {
                if !coordinator.multitouchAvailable {
                    Label("MultitouchSupport could not be loaded", systemImage: "xmark.octagon")
                        .foregroundStyle(.red)
                } else {
                    LabeledContent("Multitouch devices", value: "\(coordinator.trackpadCount)")
                }
                if !coordinator.activeConflicts.isEmpty {
                    LabeledContent {
                        Button("Show") { presenter.showSettings(tab: .gestures) }
                    } label: {
                        Label(
                            "Conflicts with \(coordinator.activeConflicts.count) macOS gesture\(coordinator.activeConflicts.count == 1 ? "" : "s")",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    }
                }
                if let zone = coordinator.lastZone {
                    LabeledContent("Last snap", value: zone.displayName)
                }
            }
            Section {
                HStack {
                    Button("About TrackTile") { presenter.showAbout() }
                    Spacer()
                    Button("Quit TrackTile") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: settingsPaneWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct GestureSettings: View {
    let coordinator: SnapCoordinator
    @AppStorage(PreferenceKey.fingerMode) private var fingerMode = Preferences.defaults.fingerMode
    @AppStorage(PreferenceKey.flickSensitivity) private var flickSensitivity = Preferences.defaults.flickSensitivity

    @AppStorage(PreferenceKey.blockSystemSwipes) private var blockSystemSwipes = Preferences.defaults.blockSystemSwipes

    private var conflicts: [GestureConflict] { coordinator.conflicts }
    private var hasSuppressible: Bool { conflicts.contains(where: \.suppressible) }

    var body: some View {
        Form {
            Section {
                Picker("Swipe with", selection: $fingerMode) {
                    ForEach(FingerMode.allCases) { mode in
                        Text(optionTitle(mode)).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                LabeledContent("Flick up to fill screen") {
                    Slider(value: $flickSensitivity, in: 0...1) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("Hard")
                    } maximumValueLabel: {
                        Text("Light")
                    }
                }
            }

            Section("Trackpad map") {
                HStack(alignment: .top, spacing: 16) {
                    TrackpadMapView()
                        .frame(width: 200, height: 130)
                    Text("Place your fingers anywhere, then slide toward the area of the trackpad that matches where the window should go. Release to snap. Flick upward to fill the screen. To cancel, slide back to where you started, add a finger, or press Esc.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Conflicting system gestures") {
                if conflicts.isEmpty {
                    Label("No conflicting gestures detected", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                } else {
                    if !coordinator.activeConflicts.isEmpty {
                        Text("macOS uses the same swipe for these gestures, so both would happen at once. Turn them off or move them to another finger count, or pick a different finger count for TrackTile.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if fingerMode.fingerCounts.contains(4) {
                        Text("macOS keeps four-finger swipes for Mission Control and Spaces active even when you choose three fingers for them. Only turning the gesture Off frees four fingers.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !coordinator.activeConflicts.isEmpty, let alternative = coordinator.conflictFreeAlternative {
                        Button("Use \(alternative.title.lowercased()) instead (no conflicts)") {
                            fingerMode = alternative
                        }
                    }
                    ForEach(conflicts) { conflict in
                        if coordinator.isBlocked(conflict) {
                            Label("\(conflict.description): blocked by TrackTile", systemImage: "hand.raised.slash")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(conflict.description, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("Turn off or change in System Settings > \(conflict.location).")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if hasSuppressible || blockSystemSwipes {
                    Toggle(isOn: $blockSystemSwipes) {
                        Text("Block these macOS swipes while swiping with TrackTile (experimental)")
                        Text("Swallows Mission Control, App Exposé and Spaces swipes that start with TrackTile's finger count. Three-finger drag and page swipes can't be blocked.")
                    }
                }
                HStack {
                    Button("Open Trackpad Settings") { GestureConflicts.openTrackpadSettings() }
                    if conflicts.contains(where: { $0.id == "threeFingerDrag" }) {
                        Button("Open Pointer Control") { GestureConflicts.openAccessibilityPointerSettings() }
                    }
                    Spacer()
                    Button("Check Again") { coordinator.refreshConflicts() }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: settingsPaneWidth)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { coordinator.refreshConflicts() }
    }

    private func optionTitle(_ mode: FingerMode) -> String {
        let count = coordinator.activeConflicts(for: mode).count
        switch count {
        case 0: return mode.title
        case 1: return "\(mode.title) (1 conflict)"
        default: return "\(mode.title) (\(count) conflicts)"
        }
    }
}

struct LayoutSettings: View {
    @AppStorage(PreferenceKey.showOutline) private var showOutline = Preferences.defaults.showOutline
    @AppStorage(PreferenceKey.gap) private var gap = Preferences.defaults.gap
    @AppStorage(PreferenceKey.centerMode) private var centerMode = Preferences.defaults.centerMode
    @AppStorage(PreferenceKey.centerFraction) private var centerFraction = Preferences.defaults.centerFraction

    var body: some View {
        Form {
            Section {
                Toggle("Show outline of the final position while swiping", isOn: $showOutline)
                LabeledContent("Gap between windows") {
                    HStack {
                        Slider(value: $gap, in: 0...40)
                            .onChange(of: gap) { _, value in
                                if value != value.rounded() { gap = value.rounded() }
                            }
                        Text("\(Int(gap)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
            }
            Section("Center") {
                Picker("Window size", selection: $centerMode) {
                    ForEach(CenterMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                if centerMode == .fraction {
                    LabeledContent("Size") {
                        HStack {
                            Slider(value: $centerFraction, in: 0.3...0.95)
                            Text("\(Int(centerFraction * 100))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: settingsPaneWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A small diagram of which trackpad area maps to which layout.
private struct TrackpadMapView: View {
    private let rows: [[SnapZone]] = [
        [.topLeft, .top, .topRight],
        [.left, .center, .right],
        [.bottomLeft, .bottom, .bottomRight],
    ]

    var body: some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            ForEach(rows.indices, id: \.self) { row in
                GridRow {
                    ForEach(rows[row], id: \.self) { zone in
                        ZonePreview(zone: zone)
                    }
                }
            }
        }
        .padding(6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .top) {
            Image(systemName: "arrow.up")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .offset(y: -14)
        }
        .help("Flick up to fill the screen")
    }
}

private struct ZonePreview: View {
    let zone: SnapZone

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let target = zone.frame(
                in: bounds.insetBy(dx: 4, dy: 4),
                currentSize: CGSize(width: proxy.size.width * 0.5, height: proxy.size.height * 0.5)
            )
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.background.opacity(0.6))
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.accentColor.opacity(0.8))
                    // `frame(in:)` uses a bottom-left origin; SwiftUI draws top-down.
                    .frame(width: target.width, height: target.height)
                    .offset(x: target.minX, y: bounds.height - target.maxY)
            }
        }
        .help(zone.displayName)
    }
}
