import AppKit
import SwiftUI

struct AboutView: View {
    static let projectURL = URL(string: "https://github.com/djui/tracktile")!

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    private var copyright: String? {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
            Text("TrackTile")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text(version)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Snap windows into halves, quarters, the center, or the full screen with a multi-finger trackpad swipe.")
                .multilineTextAlignment(.center)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: Self.projectURL) {
                Label("github.com/djui/tracktile", systemImage: "arrow.up.right.square")
            }
            if let copyright {
                Text(copyright)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(28)
        .frame(width: 340)
    }
}
