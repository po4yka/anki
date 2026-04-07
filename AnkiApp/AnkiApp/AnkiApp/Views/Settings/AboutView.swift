import AppKit
import SwiftUI

struct AboutView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            Text("Anki")
                .font(.title)
                .fontWeight(.semibold)

            Text("Version \(appVersion) (\(buildNumber))")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            Text("Built on Anki's Rust core with Atlas analytics")
                .foregroundStyle(.secondary)
                .font(.caption)
                .multilineTextAlignment(.center)

            Divider()
                .padding(.horizontal, 40)

            Text("Licensed under the GNU Affero General Public License v3.0")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Ankitects Pty Ltd and contributors")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("View Source on GitHub") {
                // swiftlint:disable:next force_unwrapping
                NSWorkspace.shared.open(URL(string: "https://github.com/ankitects/anki")!)
            }
            .buttonStyle(.link)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    AboutView()
}
