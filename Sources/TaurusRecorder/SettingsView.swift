import AppKit
import TaurusRecorderCore
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSettings: AppSettings
    @State private var draftSaveFolderURL = FileManager.default.homeDirectoryForCurrentUser
    @State private var draftOutputFormat: OutputFormat = .m4a
    @State private var draftInputGain: InputGain = .unity
    @State private var selectedTab = SettingsTab.general

    private let permissionHelper = ScreenCapturePermissionHelper()

    private var hasChanges: Bool {
        draftSaveFolderURL != appSettings.defaultSaveFolderURL
            || draftOutputFormat != appSettings.defaultOutputFormat
            || draftInputGain != appSettings.defaultInputGain
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem {
                    Label("General", systemImage: "slider.horizontal.3")
                }
                .tag(SettingsTab.general)

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
        }
        .padding(20)
        .frame(width: 620, height: 430)
        .onAppear {
            selectedTab = .general
            loadDraftFromSettings()
        }
    }

    private var generalTab: some View {
        VStack(spacing: 16) {
            Form {
                Section("Recording Defaults") {
                    FormatSelector(selection: $draftOutputFormat) {}
                    GainSlider(gain: $draftInputGain)

                    HStack {
                        Text("Save Folder")
                        Text(draftSaveFolderURL.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            chooseDraftSaveFolder()
                        } label: {
                            Label("Choose", systemImage: "folder")
                        }
                        Button {
                            NSWorkspace.shared.open(draftSaveFolderURL)
                        } label: {
                            Label("Open", systemImage: "arrow.up.forward.app")
                        }
                    }
                }

            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") {
                    loadDraftFromSettings()
                    dismiss()
                }
                .recorderSecondaryButtonStyle()

                Button {
                    appSettings.updateDefaults(
                        saveFolderURL: draftSaveFolderURL,
                        outputFormat: draftOutputFormat,
                        inputGain: draftInputGain
                    )
                    loadDraftFromSettings()
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .recorderPrimaryButtonStyle()
                .disabled(!hasChanges)
            }
        }
    }

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Taurus Recorder")
                    .font(.title2.weight(.semibold))
                Text(versionText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("© \(String(Calendar.current.component(.year, from: Date()))) Jee Hoon Chung (정지훈)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(permissionHelper.onboardingMessage)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Permissions")
                    .font(.headline)
                Text("Computer audio capture uses macOS System Audio Recording Only permission.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    permissionHelper.openSystemAudioRecordingSettings()
                } label: {
                    Label("Open Audio Recording Settings", systemImage: "gearshape")
                }
            }

            Spacer()
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case let (version?, build?) where !version.isEmpty && !build.isEmpty:
            return "Version \(version) (\(build))"
        case let (version?, _) where !version.isEmpty:
            return "Version \(version)"
        case let (_, build?) where !build.isEmpty:
            return "Build \(build)"
        default:
            return "Version unavailable"
        }
    }

    private func loadDraftFromSettings() {
        draftSaveFolderURL = appSettings.defaultSaveFolderURL
        draftOutputFormat = appSettings.defaultOutputFormat
        draftInputGain = appSettings.defaultInputGain
    }

    private func chooseDraftSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = draftSaveFolderURL

        if panel.runModal() == .OK, let url = panel.url {
            draftSaveFolderURL = url
        }
    }

    private enum SettingsTab: Hashable {
        case general
        case about
    }
}
