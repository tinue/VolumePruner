import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
