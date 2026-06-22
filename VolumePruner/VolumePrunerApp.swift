import SwiftUI

@main
struct VolumePrunerApp: App {
    // AppState is created once here and injected into both scenes via .environment().
    @State private var appState = AppState()

    var body: some Scene {
        // The app lives entirely in the menu bar — no Dock icon, no main window.
        MenuBarExtra("VolumePruner", image: "MenuBarIcon") {
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
