import SwiftUI

@main
struct VolumePrunerApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("VolumePruner", systemImage: "externaldrive.badge.minus") {
            MenuBarView()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
