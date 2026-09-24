import SwiftUI

/// Explains and requests the Accessibility permission needed to move windows.
struct PermissionsView: View {
    let coordinator: SnapCoordinator

    var body: some View {
        if coordinator.isTrusted {
            Label("Accessibility access granted", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label("Accessibility access required", systemImage: "hand.raised.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("TrackTile moves and resizes other apps' windows through the Accessibility API. Enable TrackTile in System Settings > Privacy & Security > Accessibility. TrackTile starts automatically once access is granted.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Open Accessibility Settings") {
                        coordinator.requestAccessibility()
                        GestureConflicts.openAccessibilityPrivacySettings()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Ask Again") {
                        coordinator.requestAccessibility()
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}
