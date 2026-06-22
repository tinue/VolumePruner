import SwiftUI

// One row in the menu-bar popup for a single eligible mounted volume.
struct VolumeRowView: View {
    let volume: VolumeInfo
    @Environment(AppState.self) private var appState
    // Local flag prevents the buttons from stacking while a clean is in progress.
    @State private var isRunning = false

    var body: some View {
        HStack(spacing: 10) {
            statusDot

            Image(systemName: volumeIcon)
                .imageScale(.large)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(volume.name)
                    .fontWeight(.medium)
                Text(volume.fsTypeName.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isRunning {
                ProgressView().controlSize(.small)
            } else {
                HStack(spacing: 8) {
                    Button("Clean") {
                        Task { await runClean(eject: false) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("& Eject") {
                        Task { await runClean(eject: true) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    // Hoist to a property so the same dictionary lookup drives
                    // the icon, color, and help text without hitting it three times.
                    let watching = isWatching
                    Button {
                        appState.toggleWatch(volume: volume)
                    } label: {
                        Image(systemName: watching ? "eye.fill" : "eye")
                            .foregroundStyle(watching ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(watching
                          ? "Watching — auto-cleans when junk appears"
                          : "Watch this volume and auto-clean junk")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // Computed once per body evaluation; avoids the repeated dictionary lookup.
    private var isWatching: Bool { appState.isWatching(volume) }

    @ViewBuilder
    private var statusDot: some View {
        let status = appState.volumeStatuses[volume.id] ?? .unknown
        Circle()
            .fill(dotColor(for: status))
            .frame(width: 8, height: 8)
            .help(dotLabel(for: status))
    }

    private func dotColor(for status: VolumeStatus) -> Color {
        switch status {
        case .clean:   return .green
        case .dirty:   return .orange
        case .unknown: return Color.secondary.opacity(0.3)
        }
    }

    private func dotLabel(for status: VolumeStatus) -> String {
        switch status {
        case .clean:   return "No junk files found"
        case .dirty:   return "Junk files present — click Clean"
        case .unknown: return "Checking…"
        }
    }

    // SD cards show a card icon; all other removable/external drives use the drive icon.
    private var volumeIcon: String {
        volume.isRemovable ? "sdcard" : "externaldrive"
    }

    private func runClean(eject: Bool) async {
        isRunning = true
        await appState.clean(volume: volume, ejectAfter: eject)
        isRunning = false
        if !eject {
            appState.refreshStatuses()
        }
    }
}
