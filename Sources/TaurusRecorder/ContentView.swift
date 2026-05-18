import AppKit
import TaurusRecorderCore
import SwiftUI

struct ContentView: View {
    @ObservedObject private var appSettings: AppSettings
    @StateObject private var viewModel: RecorderViewModel

    init(appSettings: AppSettings) {
        self.appSettings = appSettings
        _viewModel = StateObject(wrappedValue: RecorderViewModel(appSettings: appSettings))
    }

    var body: some View {
        NavigationSplitView {
            RecordingHistorySidebar(viewModel: viewModel)
                .navigationTitle("History")
                .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 330)
        } detail: {
            ScrollView {
                VStack(spacing: 20) {
                    transport
                    AudioLevelMeterView(reading: viewModel.meterReading, statusText: viewModel.meterStatusText)
                    WaveformView(points: viewModel.waveformPoints, isActive: viewModel.state == .recording)
                    saveControls
                    footer
                }
                .padding(.top, 28)
                .padding(.horizontal, 28)
                .padding(.bottom, 18)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 10) {
                    Spacer()
                    RecordingStatusPill(state: viewModel.state)
                    SettingsPillButton {
                        openSettingsWindow()
                    }
                }
                .padding(.top, 8)
                .padding(.trailing, 22)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 840, minHeight: 600)
        .background(WindowTitleHider())
        .onAppear {
            viewModel.refreshAvailableCaptureApps()
            viewModel.startMonitoring()
        }
        .onChange(of: appSettings.defaultSaveFolderURL) { _, _ in
            viewModel.applyDefaultsFromSettings()
        }
        .onChange(of: appSettings.defaultOutputFormat) { _, _ in
            viewModel.applyDefaultsFromSettings()
        }
        .onChange(of: appSettings.defaultInputGain) { _, _ in
            viewModel.applyDefaultsFromSettings()
        }
        .sheet(isPresented: pendingSaveSheetBinding) {
            PendingRecordingSheet(viewModel: viewModel)
                .frame(width: 460)
                .interactiveDismissDisabled()
        }
        .sheet(item: $viewModel.renameTarget) { item in
            RenameRecordingSheet(viewModel: viewModel, item: item)
                .frame(width: 420)
        }
    }

    private var pendingSaveSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingRecording != nil },
            set: { _ in }
        )
    }

    private var transport: some View {
        VStack(spacing: 14) {
            Text(viewModel.formattedElapsedTime)
                .font(.system(size: 48, weight: .medium, design: .rounded))
                .monospacedDigit()

            HStack(spacing: 14) {
                Button {
                    viewModel.primaryControlTapped()
                } label: {
                    Label(viewModel.primaryControlTitle, systemImage: viewModel.primaryControlSystemImage)
                        .font(.title3.weight(.semibold))
                        .frame(width: 152, height: 54)
                }
                .recorderPrimaryButtonStyle(isDestructive: viewModel.canStop)
                .controlSize(.large)
                .disabled(viewModel.state == .saving || viewModel.isMonitoringStarting || viewModel.isStartingRecording)

                Button {
                    viewModel.secondaryControlTapped()
                } label: {
                    Label(viewModel.secondaryControlTitle, systemImage: viewModel.secondaryControlSystemImage)
                        .frame(width: 106, height: 44)
                }
                .recorderSecondaryButtonStyle()
                .controlSize(.large)
                .disabled(!viewModel.canStop || viewModel.state == .saving)

                Button {
                    viewModel.cancel()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                        .frame(width: 106, height: 44)
                }
                .recorderSecondaryButtonStyle()
                .controlSize(.large)
                .disabled(!viewModel.canStop || viewModel.state == .saving)
            }
        }
    }

    private var saveControls: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
            GridRow {
                Text("Save Location")
                    .foregroundStyle(.secondary)
                HStack {
                    Text(viewModel.saveFolderURL.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.callout)
                    Spacer()
                    Button {
                        viewModel.chooseSaveFolder()
                    } label: {
                        Label("Choose", systemImage: "folder")
                    }
                    Button {
                        viewModel.openSaveFolder()
                    } label: {
                        Label("Open", systemImage: "arrow.up.forward.app")
                    }
                }
            }

            GridRow {
                Text("Format")
                    .foregroundStyle(.secondary)
                FormatSelector(selection: $viewModel.outputFormat) {
                    openSettingsWindow()
                }
                .frame(width: 300)
            }

            GridRow {
                Text("Audio Source")
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    CaptureTargetSelector(
                        selection: $viewModel.captureTarget,
                        targets: viewModel.captureTargetOptions
                    )
                    .frame(width: 300)
                    .disabled(viewModel.canStop || viewModel.state == .saving)

                    Button {
                        viewModel.refreshAvailableCaptureApps()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh running apps")
                    .disabled(viewModel.canStop || viewModel.state == .saving)
                }
            }

            GridRow {
                Text("Input Gain")
                    .foregroundStyle(.secondary)
                GainSlider(gain: $viewModel.inputGain)
                    .frame(width: 300)
            }
        }
        .font(.callout)
    }

    private func openSettingsWindow() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }

    @ViewBuilder
    private var footer: some View {
        if viewModel.errorMessage != nil || viewModel.lastSavedURL != nil {
            VStack(alignment: .leading, spacing: 8) {
                if let errorMessage = viewModel.errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(viewModel.permissionIssue?.message ?? errorMessage)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }

                        permissionButtons
                    }
                    .font(.callout)
                }

                if let lastSavedURL = viewModel.lastSavedURL {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Saved: \(lastSavedURL.lastPathComponent)")
                            .lineLimit(1)
                        Spacer()
                    }
                    .font(.callout)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .recorderGlassSurface(cornerRadius: 14)
            .animation(.easeInOut(duration: 0.35), value: viewModel.lastSavedURL)
        }
    }

    @ViewBuilder
    private var permissionButtons: some View {
        if let permissionIssue = viewModel.permissionIssue {
            HStack(spacing: 8) {
                if permissionIssue.destinations.contains(.systemAudioRecording) {
                    Button {
                        viewModel.openScreenRecordingSettings()
                    } label: {
                        Label("Open Audio Settings", systemImage: "gearshape")
                    }
                }
                Spacer()
            }
        } else {
            HStack {
                if viewModel.errorMessage != nil {
                    Button {
                        viewModel.openScreenRecordingSettings()
                    } label: {
                        Label("Open Settings", systemImage: "gearshape")
                    }
                }
            }
        }
    }

}

private struct WindowTitleHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: NSView) {
        DispatchQueue.main.async {
            view.window?.titleVisibility = .hidden
        }
    }
}

private struct RecordingStatusPill: View {
    let state: RecordingState

    var body: some View {
        Text(title)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(minWidth: 108)
            .background(backgroundColor, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .accessibilityLabel("Recording status: \(title)")
    }

    private var title: String {
        switch state {
        case .idle, .monitoring, .saving:
            "Ready"
        case .recording:
            "Recording"
        case .paused:
            "Paused"
        case .error:
            "Error"
        }
    }

    private var tintColor: Color {
        switch state {
        case .recording:
            .red
        case .paused:
            .orange
        case .error:
            .red
        case .idle, .monitoring, .saving:
            .secondary
        }
    }

    private var foregroundColor: Color {
        switch state {
        case .recording:
            .red
        case .paused:
            .orange
        case .error:
            .red
        case .idle, .monitoring, .saving:
            .secondary
        }
    }

    private var tintOpacity: Double {
        switch state {
        case .idle, .monitoring, .saving:
            0.1
        default:
            0.16
        }
    }

    private var backgroundColor: Color {
        tintColor.opacity(tintOpacity)
    }

    private var borderColor: Color {
        switch state {
        case .idle, .monitoring, .saving:
            Color(nsColor: .separatorColor).opacity(0.45)
        default:
            tintColor.opacity(0.35)
        }
    }
}

private struct SettingsPillButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Color.secondary.opacity(0.1), in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help("Settings")
        .accessibilityLabel("Settings")
    }
}

struct CaptureTargetSelector: View {
    @Binding var selection: AudioCaptureTarget
    let targets: [AudioCaptureTarget]

    var body: some View {
        Picker("Audio Source", selection: $selection) {
            ForEach(targets, id: \.self) { target in
                Text(target.displayName)
                    .tag(target)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }
}

struct GainSlider: View {
    @Binding var gain: InputGain

    private var notchBinding: Binding<Double> {
        Binding(
            get: { Double(gain.notchIndex) },
            set: { gain = InputGain(notchIndex: Int($0.rounded())) }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("1/3x")
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)

            Slider(
                value: notchBinding,
                in: Double(InputGain.minimumNotchIndex)...Double(InputGain.maximumNotchIndex),
                step: 1
            )

            Text("3x")
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            Text(gain.decibelLabel)
                .monospacedDigit()
                .frame(width: 58, alignment: .trailing)
        }
    }
}

struct FormatSelector: View {
    @Binding var selection: OutputFormat
    var unavailableMP3Tapped: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("Format", selection: $selection) {
                ForEach(OutputFormat.allCases) { format in
                    Text(format.rawValue)
                        .tag(format)
                        .disabled(!format.isExportAvailable)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            if !OutputFormat.mp3.isExportAvailable {
                Button {
                    unavailableMP3Tapped()
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .help(AudioFileConverter.mp3UnavailableExplanation)
                .recorderSecondaryButtonStyle()
            }
        }
    }
}

private struct RecordingHistorySidebar: View {
    @ObservedObject var viewModel: RecorderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("History")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.refreshHistory()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }

            if viewModel.recordingHistory.isEmpty {
                ContentUnavailableView(
                    "No Recordings",
                    systemImage: "waveform",
                    description: Text("Saved recordings in this folder will appear here.")
                )
                .font(.callout)
            } else {
                ScrollViewReader { proxy in
                    List(viewModel.recordingHistory) { item in
                        RecordingHistoryRow(viewModel: viewModel, item: item)
                        .id(item.id)
                        .contextMenu {
                            Button("Play") {
                                viewModel.togglePlayback(for: item)
                            }
                            Button("Open") {
                                viewModel.openRecording(item)
                            }
                            Button("Reveal in Finder") {
                                viewModel.revealRecording(item)
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .onAppear {
                        if let firstID = viewModel.recordingHistory.first?.id {
                            proxy.scrollTo(firstID, anchor: .top)
                        }
                    }
                    .onChange(of: viewModel.recordingHistory.first?.id) { _, newID in
                        guard let newID else {
                            return
                        }
                        Task { @MainActor in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(newID, anchor: .top)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

private struct RecordingHistoryRow: View {
    @ObservedObject var viewModel: RecorderViewModel
    let item: RecordingHistoryItem

    private var isExpanded: Bool {
        viewModel.playbackItemID == item.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    viewModel.togglePlayback(for: item)
                } label: {
                    Image(systemName: viewModel.playbackControlSystemImage(for: item))
                        .frame(width: 16)
                }
                .buttonStyle(.borderless)
                .help(isExpanded && viewModel.isPlaybackPlaying ? "Pause" : "Play")

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayName)
                        .lineLimit(2)
                    Text(item.detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.showPlayback(for: item)
                }

                Button {
                    viewModel.beginRename(item)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Rename")

                Button(role: .destructive) {
                    viewModel.deleteRecording(item)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete local file")

                Button {
                    viewModel.revealRecording(item)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Open in folder")
            }

            if isExpanded {
                RecordingMiniPlayer(viewModel: viewModel, item: item)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, isExpanded ? 4 : 0)
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
    }
}

private struct RecordingMiniPlayer: View {
    @ObservedObject var viewModel: RecorderViewModel
    let item: RecordingHistoryItem

    private var playheadBinding: Binding<Double> {
        Binding(
            get: { viewModel.playbackProgress },
            set: { viewModel.seekPlayback(toProgress: $0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Slider(value: playheadBinding, in: 0...1)
                .controlSize(.small)
                .disabled(viewModel.playbackDuration <= 0)
                .help("Seek")

            HStack(spacing: 8) {
                Text(viewModel.formatDuration(viewModel.playbackElapsed))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Button {
                    viewModel.skipPlayback(by: -10)
                } label: {
                    Image(systemName: "gobackward.10")
                }
                .buttonStyle(.borderless)
                .help("Back 10 seconds")

                Button {
                    viewModel.togglePlayback(for: item)
                } label: {
                    Image(systemName: viewModel.playbackControlSystemImage(for: item))
                }
                .buttonStyle(.borderless)
                .help(viewModel.isPlaybackPlaying ? "Pause" : "Play")

                Button {
                    viewModel.skipPlayback(by: 10)
                } label: {
                    Image(systemName: "goforward.10")
                }
                .buttonStyle(.borderless)
                .help("Forward 10 seconds")

                Spacer(minLength: 4)

                Text(viewModel.formatDuration(viewModel.playbackDuration))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let playbackErrorMessage = viewModel.playbackErrorMessage {
                Text(playbackErrorMessage)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
        }
    }
}

private struct RenameRecordingSheet: View {
    @ObservedObject var viewModel: RecorderViewModel
    let item: RecordingHistoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Rename Recording")
                    .font(.title3.weight(.semibold))
                Text(item.url.lastPathComponent)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack {
                TextField("Name", text: $viewModel.renameFileName)
                    .textFieldStyle(.roundedBorder)
                Text(".\(item.url.pathExtension)")
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Cancel") {
                    viewModel.cancelRename()
                }
                Spacer()
                Button("Rename") {
                    viewModel.confirmRename()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
    }
}

private struct PendingRecordingSheet: View {
    @ObservedObject var viewModel: RecorderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Save Recording")
                    .font(.title3.weight(.semibold))
                if let pending = viewModel.pendingRecording {
                    Text("Duration \(viewModel.formatDuration(pending.duration)) · \(pending.format.rawValue)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("Recording name", text: $viewModel.pendingFileName)
                        .textFieldStyle(.roundedBorder)
                    if let pending = viewModel.pendingRecording {
                        Text(".\(pending.format.fileExtension)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(role: .destructive) {
                    viewModel.deletePendingRecording()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(viewModel.isSavingPendingRecording)

                Spacer()

                Button {
                    viewModel.savePendingRecording()
                } label: {
                    Text(viewModel.isSavingPendingRecording ? "Saving" : "Save")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isSavingPendingRecording)
            }
        }
        .padding(22)
    }
}
