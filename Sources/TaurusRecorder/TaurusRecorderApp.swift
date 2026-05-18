import SwiftUI

@main
struct TaurusRecorderApp: App {
    @StateObject private var appSettings = AppSettings()

    var body: some Scene {
        WindowGroup("Taurus Recorder") {
            ContentView(appSettings: appSettings)
                .environmentObject(appSettings)
                .frame(minWidth: 840, minHeight: 600)
        }
        .defaultSize(width: 840, height: 600)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(appSettings)
        }
    }
}
