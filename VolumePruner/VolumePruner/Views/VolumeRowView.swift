import SwiftUI

struct VolumeRowView: View {
    let volume: VolumeInfo
    @Environment(AppState.self) private var appState
    @State private var isRunning = false
    @State private var lastResult: CleanResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
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
                    HStack(spacing: 6) {
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

                        Toggle(isOn: Binding(
                            get: { appState.isWatching(volume) },
                            set: { _ in appState.toggleWatch(volume: volume) }
                        )) {
                            Image(systemName: "eye")
                        }
                        .toggleStyle(.checkbox)
                        .help("Auto-clean when files are created on this volume")
                    }
                }
            }

            if let result = lastResult, !isRunning {
                Text(result.filesRemoved == 0
                    ? "Nothing to clean"
                    : "Removed \(result.filesRemoved) file(s), \(result.formattedBytes) freed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var volumeIcon: String {
        if volume.isRemovable { return "sdcard" }
        return "externaldrive"
    }

    private func runClean(eject: Bool) async {
        isRunning = true
        lastResult = nil
        await appState.clean(volume: volume, ejectAfter: eject)
        isRunning = false
        if !eject {
            lastResult = nil
            // Reflect history entry count as proxy for result
            if let event = appState.cleanHistory.first, event.volumeName == volume.name {
                lastResult = CleanResult(filesRemoved: event.filesRemoved, bytesReclaimed: event.bytesReclaimed, errors: [])
            }
        }
    }
}
