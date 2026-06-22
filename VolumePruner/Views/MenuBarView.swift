import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Full Disk Access banner — only shown when we've already hit a permission error.
            if appState.needsFullDiskAccess {
                HStack(spacing: 8) {
                    Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Full Disk Access needed")
                            .font(.caption).fontWeight(.semibold)
                        Text("Required to remove .Spotlight-V100")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Grant…") {
                        openURL(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    }
                    .controlSize(.mini).buttonStyle(.bordered)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                Divider()
            }

            if appState.mountedVolumes.isEmpty {
                Text("No eligible volumes mounted")
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // enumerated() lets us draw a divider between rows without
                // comparing URLs to find the last element.
                ForEach(Array(appState.mountedVolumes.enumerated()), id: \.element.id) { index, volume in
                    VolumeRowView(volume: volume)
                    if index < appState.mountedVolumes.count - 1 {
                        Divider().padding(.horizontal)
                    }
                }
            }

            Divider()

            HStack {
                Button("Settings…") { openSettings() }
                    .buttonStyle(.borderless)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 320)
    }
}
