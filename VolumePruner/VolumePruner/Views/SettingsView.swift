import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var launchAtLogin = LoginItemManager.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
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
                let entries = appState.watchedVolumes.sorted { $0.value < $1.value }
                if entries.isEmpty {
                    Text("No volumes being watched")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries, id: \.key) { key, name in
                        let mounted = appState.mountedVolumes.contains { $0.watchKey == key }
                        HStack {
                            Image(systemName: "eye.fill")
                                .foregroundStyle(mounted ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(name)
                                if !mounted {
                                    Text("Not mounted")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            Button("Remove", role: .destructive) {
                                appState.removeWatchedVolume(key: key)
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
    }
}
