import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                ForEach(appState.mountedVolumes) { volume in
                    VolumeRowView(volume: volume)
                    if volume.id != appState.mountedVolumes.last?.id {
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
        .task {
            await appState.refreshStatuses()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await appState.refreshStatuses()
            }
        }
    }
}
