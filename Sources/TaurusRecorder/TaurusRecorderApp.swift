import SwiftUI

@main
struct TaurusRecorderApp: App {
    @StateObject private var appSettings = AppSettings()

    var body: some Scene {
        WindowGroup("Taurus Recorder") {
            ContentView(appSettings: appSettings)
                .environmentObject(appSettings)
                .frame(minWidth: 880, minHeight: 620)
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(appSettings)
        }
    }
}
