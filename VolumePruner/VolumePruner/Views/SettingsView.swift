import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var launchAtLogin = LoginItemManager.isEnabled
    @State private var loginError: String?
    @State private var hasFullDiskAccess = AppState.hasFullDiskAccess

    var body: some View {
        Form {
            if !hasFullDiskAccess {
                Section("Permissions") {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .imageScale(.large)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Full Disk Access required for .Spotlight-V100")
                                .fontWeight(.medium)
                            Text("macOS only allows system processes to remove Spotlight index directories. Grant Full Disk Access so VolumePruner can remove them too.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Button("Open Privacy Settings…") {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    }
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            try LoginItemManager.setLaunchAtLogin(newValue)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = !newValue
                        }
                    }

                if let err = loginError {
                    Text(err).foregroundStyle(.red).font(.caption)
                }

                HStack {
                    Text("Max volume size")
                    Spacer()
                    TextField("", value: Binding(
                        get: { appState.maxVolumeSizeGB },
                        set: { appState.maxVolumeSizeGB = max(1, $0) }
                    ), format: .number)
                    .frame(width: 72)
                    .multilineTextAlignment(.trailing)
                    Text("GB")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Watched Volumes") {
                let paths = Array(appState.watchedPaths).sorted { $0.path < $1.path }
                if paths.isEmpty {
                    Text("No volumes being watched")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(paths, id: \.self) { url in
                        HStack {
                            Image(systemName: "eye.fill")
                                .foregroundStyle(.secondary)
                            Text(url.lastPathComponent)
                            Text(url.path)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .truncationMode(.middle)
                                .lineLimit(1)
                            Spacer()
                            Button("Remove", role: .destructive) {
                                appState.removeWatchedPath(url)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                        }
                    }
                }
            }

            Section("Recent Activity") {
                if appState.cleanHistory.isEmpty {
                    Text("No cleaning done yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.cleanHistory) { event in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.volumeName)
                                    .fontWeight(.medium)
                                Text(event.date, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(event.filesRemoved) file(s)")
                                Text(event.formattedBytes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 520)
        .onAppear { hasFullDiskAccess = AppState.hasFullDiskAccess }
    }
}
