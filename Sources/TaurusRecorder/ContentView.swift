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
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    transport
                    AudioLevelMeterView(reading: viewModel.meterReading, statusText: viewModel.meterStatusText)
                    WaveformView(points: viewModel.waveformPoints, isActive: viewModel.state == .recording)
                    saveControls
                    footer
                }
                .padding(28)
                .frame(maxWidth: .infinity)
            }
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            RecordingHistorySidebar(viewModel: viewModel)
                .frame(width: 270)
                .background(Color(nsColor: .underPageBackgroundColor))
        }
        .frame(minWidth: 880, minHeight: 620)
        .onChange(of: appSettings.defaultSaveFolderURL) { _, _ in
            viewModel.applyDefaultsFromSettings()
        }
        .onChange(of: appSettings.defaultOutputFormat) { _, _ in
            viewModel.applyDefaultsFromSettings()
        }
        .onChange(of: appSettings.defaultInputMode) { _, _ in
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

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Taurus Recorder")
                    .font(.system(size: 22, weight: .semibold))
            }

            Spacer()

            Text(viewModel.state.title)
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(stateColor.opacity(0.14), in: Capsule())
                .foregroundStyle(stateColor)
        }
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
                .buttonStyle(.borderedProminent)
                .tint(viewModel.canStop ? .red : nil)
                .controlSize(.large)
                .disabled(viewModel.state == .saving)

                Button {
                    viewModel.secondaryControlTapped()
                } label: {
                    Label(viewModel.secondaryControlTitle, systemImage: viewModel.secondaryControlSystemImage)
                        .frame(width: 106, height: 44)
                }
                .controlSize(.large)
                .disabled(!viewModel.canStop || viewModel.state == .saving)

                Button {
                    viewModel.cancel()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                        .frame(width: 106, height: 44)
                }
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
                        Text("Open Folder")
                    }
                }
            }

            GridRow {
                Text("Format")
                    .foregroundStyle(.secondary)
                FormatSelector(selection: $viewModel.outputFormat) {
                    openSettingsWindow()
                }
                .frame(width: 240)
            }

            GridRow {
                Text("Source")
                    .foregroundStyle(.secondary)
                SourceSelector(selection: $viewModel.inputMode)
                    .frame(width: 300)
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

    private var footer: some View {
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
        .frame(minHeight: 28)
        .animation(.easeInOut(duration: 0.35), value: viewModel.lastSavedURL)
    }

    @ViewBuilder
    private var permissionButtons: some View {
        if let permissionIssue = viewModel.permissionIssue {
            HStack(spacing: 8) {
                if permissionIssue.destinations.contains(.screenRecording) {
                    Button("Open Screen Settings") {
                        viewModel.openScreenRecordingSettings()
                    }
                }
                if permissionIssue.destinations.contains(.microphone) {
                    Button("Open Microphone Settings") {
                        viewModel.openMicrophoneSettings()
                    }
                }
                Spacer()
            }
        } else {
            HStack {
                if viewModel.errorMessage != nil {
                    Button("Open Settings") {
                        viewModel.openScreenRecordingSettings()
                    }
                }
            }
        }
    }

    private var stateColor: Color {
        switch viewModel.state {
        case .recording:
            .red
        case .paused:
            .orange
        case .saving:
            .blue
        case .error:
            .orange
        default:
            .secondary
        }
    }
}

struct SourceSelector: View {
    @Binding var selection: RecordingInputMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(RecordingInputMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Text(mode.displayName)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == mode ? .white : .primary)
                .background {
                    if selection == mode {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor)
                    } else {
                        Color.clear
                    }
                }

                if mode != RecordingInputMode.allCases.last {
                    Divider()
                        .frame(height: 18)
                }
            }
        }
        .padding(2)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        }
    }
}

struct GainSlider: View {
    @Binding var gain: InputGain

    private var multiplierBinding: Binding<Double> {
        Binding(
            get: { Double(gain.multiplier) },
            set: { gain = InputGain(multiplier: Float($0)) }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("1/3x")
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)

            Slider(
                value: multiplierBinding,
                in: Double(InputGain.minimumMultiplier)...Double(InputGain.maximumMultiplier)
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
        HStack(spacing: 0) {
            ForEach(OutputFormat.allCases) { format in
                Button {
                    handleTap(format)
                } label: {
                    Text(format.rawValue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(foregroundStyle(for: format))
                .background(background(for: format))
                .help(helpText(for: format))

                if format != OutputFormat.allCases.last {
                    Divider()
                        .frame(height: 18)
                }
            }
        }
        .padding(2)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        }
    }

    private func handleTap(_ format: OutputFormat) {
        if format.isExportAvailable {
            selection = format
        } else if format == .mp3 {
            unavailableMP3Tapped()
        }
    }

    private func foregroundStyle(for format: OutputFormat) -> Color {
        if selection == format {
            return .white
        }
        return format.isExportAvailable ? .primary : .secondary.opacity(0.55)
    }

    @ViewBuilder
    private func background(for format: OutputFormat) -> some View {
        if selection == format {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor)
        } else {
            Color.clear
        }
    }

    private func helpText(for format: OutputFormat) -> String {
        if format == .mp3, !format.isExportAvailable {
            return AudioFileConverter.mp3UnavailableExplanation
        }
        return "\(format.rawValue) format"
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
                List(viewModel.recordingHistory) { item in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.displayName)
                                .lineLimit(2)
                            Text(item.detailText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

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
                    .contextMenu {
                        Button("Open") {
                            viewModel.openRecording(item)
                        }
                        Button("Reveal in Finder") {
                            viewModel.revealRecording(item)
                        }
                    }
                }
                .listStyle(.sidebar)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
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
