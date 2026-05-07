import AppKit
import Foundation
import TaurusRecorderCore

struct RecordingHistoryItem: Identifiable, Equatable, Sendable {
    let id: URL
    let url: URL
    let modifiedAt: Date
    let fileSize: Int64

    var displayName: String {
        url.deletingPathExtension().lastPathComponent
    }

    var detailText: String {
        let size = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        return "\(Self.dateFormatter.string(from: modifiedAt)) · \(size)"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

struct PendingRecording: Equatable, Sendable {
    let temporaryURL: URL
    let suggestedURL: URL
    let format: OutputFormat
    let duration: TimeInterval

    var suggestedBaseName: String {
        suggestedURL.deletingPathExtension().lastPathComponent
    }
}

@MainActor
final class RecorderViewModel: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var elapsedTime: TimeInterval = 0
    @Published var saveFolderURL: URL {
        didSet {
            refreshHistory()
            if appSettings.defaultSaveFolderURL != saveFolderURL {
                appSettings.defaultSaveFolderURL = saveFolderURL
            }
        }
    }
    @Published var outputFormat: OutputFormat = .m4a {
        didSet {
            if !outputFormat.isExportAvailable {
                outputFormat = .m4a
                return
            }
            if appSettings.defaultOutputFormat != outputFormat {
                appSettings.defaultOutputFormat = outputFormat
            }
        }
    }
    @Published var meterReading: MeterReading = .silence
    @Published var waveformPoints: [WaveformPoint] = []
    @Published var errorMessage: String?
    @Published var lastSavedURL: URL?
    @Published var recordingHistory: [RecordingHistoryItem] = []
    @Published var pendingRecording: PendingRecording?
    @Published var pendingFileName = ""
    @Published var isSavingPendingRecording = false
    @Published var renameTarget: RecordingHistoryItem?
    @Published var renameFileName = ""

    let permissionMessage: String

    private let recorder: AudioRecorder
    private let appSettings: AppSettings
    private let permissionHelper = ScreenCapturePermissionHelper()
    private let fileNamingService = FileNamingService()
    private var timerTask: Task<Void, Never>?
    private var recordingStartedAt: Date?
    private var accumulatedElapsed: TimeInterval = 0
    private var activeSuggestedURL: URL?
    private var activeFormat: OutputFormat = .m4a
    private var pendingDuration: TimeInterval = 0
    private var saveConfirmationTask: Task<Void, Never>?
    private var isStartingRecording = false

    init(appSettings: AppSettings, recorder: AudioRecorder = AudioRecorder()) {
        self.recorder = recorder
        self.appSettings = appSettings
        self.permissionMessage = permissionHelper.onboardingMessage
        self.saveFolderURL = appSettings.defaultSaveFolderURL
        self.outputFormat = OutputFormat.availableDefault(preferred: appSettings.defaultOutputFormat)
        bindRecorder()
        refreshHistory()
    }

    var canStop: Bool {
        state == .recording || state == .paused
    }

    var primaryControlTitle: String {
        switch state {
        case .recording, .paused:
            "Stop"
        case .saving:
            "Saving"
        default:
            "Record"
        }
    }

    var primaryControlSystemImage: String {
        switch state {
        case .recording, .paused:
            "stop.fill"
        default:
            "record.circle"
        }
    }

    var secondaryControlTitle: String {
        switch state {
        case .paused:
            "Resume"
        default:
            "Pause"
        }
    }

    var secondaryControlSystemImage: String {
        switch state {
        case .paused:
            "play.fill"
        default:
            "pause.fill"
        }
    }

    var formattedElapsedTime: String {
        formatDuration(elapsedTime)
    }

    var meterStatusText: String {
        meterReading.isSilent ? "No system audio detected" : "System audio detected"
    }

    var defaultPreviewName: String {
        "\(fileNamingService.defaultBaseName())01.\(outputFormat.fileExtension)"
    }

    func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded(.down))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    func beginMonitoring() {
        Task {
            do {
                try await recorder.startMonitoring()
                errorMessage = nil
            } catch {
                state = .error(error.localizedDescription)
                errorMessage = error.localizedDescription
            }
        }
    }

    func retryMonitoringIfPermissionWasGranted() {
        switch state {
        case .idle, .error:
            errorMessage = nil
            beginMonitoring()
        case .monitoring, .recording, .paused, .saving:
            break
        }
    }

    func primaryControlTapped() {
        switch state {
        case .recording, .paused:
            stop()
        case .saving:
            break
        default:
            startRecording()
        }
    }

    func secondaryControlTapped() {
        switch state {
        case .recording:
            pause()
        case .paused:
            resume()
        default:
            break
        }
    }

    func stop() {
        refreshElapsedTime()
        pendingDuration = elapsedTime
        timerTask?.cancel()
        if let recordingStartedAt {
            accumulatedElapsed += Date().timeIntervalSince(recordingStartedAt)
        }
        recordingStartedAt = nil

        Task {
            await recorder.stopRecording()
        }
    }

    func cancel() {
        timerTask?.cancel()
        recordingStartedAt = nil
        accumulatedElapsed = 0
        elapsedTime = 0
        waveformPoints = []
        activeSuggestedURL = nil
        recorder.cancelRecording()
    }

    func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = saveFolderURL

        if panel.runModal() == .OK, let url = panel.url {
            saveFolderURL = url
            appSettings.defaultSaveFolderURL = url
        }
    }

    func openSaveFolder() {
        NSWorkspace.shared.open(saveFolderURL)
    }

    func openRecording(_ item: RecordingHistoryItem) {
        NSWorkspace.shared.open(item.url)
    }

    func revealRecording(_ item: RecordingHistoryItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func beginRename(_ item: RecordingHistoryItem) {
        errorMessage = nil
        renameTarget = item
        renameFileName = item.displayName
    }

    func confirmRename() {
        guard let renameTarget else {
            return
        }

        do {
            let trimmed = renameFileName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return
            }

            let baseName = URL(fileURLWithPath: trimmed).deletingPathExtension().lastPathComponent
            let destination = renameTarget.url
                .deletingLastPathComponent()
                .appendingPathComponent(baseName)
                .appendingPathExtension(renameTarget.url.pathExtension)

            if destination != renameTarget.url {
                if FileManager.default.fileExists(atPath: destination.path) {
                    throw RecorderError.writerFailed("A recording with that name already exists.")
                }
                try FileManager.default.moveItem(at: renameTarget.url, to: destination)
            }

            self.renameTarget = nil
            renameFileName = ""
            refreshHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelRename() {
        renameTarget = nil
        renameFileName = ""
    }

    func deleteRecording(_ item: RecordingHistoryItem) {
        do {
            try FileManager.default.removeItem(at: item.url)
            refreshHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openScreenRecordingSettings() {
        permissionHelper.openScreenRecordingSettings()
    }

    func applyDefaultsFromSettings() {
        switch state {
        case .idle, .monitoring, .error:
            break
        case .recording, .paused, .saving:
            return
        }

        if saveFolderURL != appSettings.defaultSaveFolderURL {
            saveFolderURL = appSettings.defaultSaveFolderURL
        }
        let availableDefaultFormat = OutputFormat.availableDefault(preferred: appSettings.defaultOutputFormat)
        if outputFormat != availableDefaultFormat {
            outputFormat = availableDefaultFormat
        }
    }

    func savePendingRecording() {
        guard let pendingRecording else {
            return
        }
        guard !isSavingPendingRecording else {
            return
        }

        do {
            errorMessage = nil
            let destinationURL = try destinationURL(for: pendingRecording)
            isSavingPendingRecording = true

            Task {
                do {
                    try await Task.detached(priority: .userInitiated) {
                        if pendingRecording.format == .mp3 {
                            try AudioFileConverter().convertToMP3(
                                inputURL: pendingRecording.temporaryURL,
                                outputURL: destinationURL
                            )
                            try? FileManager.default.removeItem(at: pendingRecording.temporaryURL)
                        } else {
                            if FileManager.default.fileExists(atPath: destinationURL.path) {
                                try FileManager.default.removeItem(at: destinationURL)
                            }
                            try FileManager.default.moveItem(at: pendingRecording.temporaryURL, to: destinationURL)
                        }
                    }.value

                    showSavedConfirmation(for: destinationURL)
                    clearPendingRecording()
                    waveformPoints = []
                    refreshHistory()
                } catch {
                    errorMessage = error.localizedDescription
                }
                isSavingPendingRecording = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deletePendingRecording() {
        guard let pendingRecording else {
            return
        }
        guard !isSavingPendingRecording else {
            return
        }
        try? FileManager.default.removeItem(at: pendingRecording.temporaryURL)
        clearPendingRecording()
        waveformPoints = []
    }

    func refreshHistory() {
        let supportedExtensions = Set(OutputFormat.allCases.map(\.fileExtension))
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: saveFolderURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        recordingHistory = urls.compactMap { url in
            guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
                return nil
            }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else {
                return nil
            }
            return RecordingHistoryItem(
                id: url,
                url: url,
                modifiedAt: values?.contentModificationDate ?? .distantPast,
                fileSize: Int64(values?.fileSize ?? 0)
            )
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func startRecording() {
        guard !isStartingRecording else {
            return
        }

        do {
            if !outputFormat.isExportAvailable {
                outputFormat = .m4a
            }
            let suggestedURL = try fileNamingService.nextAvailableRecordingURL(
                in: saveFolderURL,
                format: outputFormat
            )
            let recordingFormat: OutputFormat = outputFormat == .mp3 ? .m4a : outputFormat
            let temporaryURL = try temporaryRecordingURL(format: recordingFormat)
            activeSuggestedURL = suggestedURL
            activeFormat = outputFormat
            lastSavedURL = nil
            errorMessage = nil
            pendingRecording = nil
            waveformPoints = []
            accumulatedElapsed = 0
            elapsedTime = 0
            pendingDuration = 0
            recordingStartedAt = Date()
            isStartingRecording = true
            startTimer()

            Task {
                do {
                    try await recorder.startRecording(outputURL: temporaryURL, format: recordingFormat)
                    isStartingRecording = false
                } catch {
                    timerTask?.cancel()
                    recordingStartedAt = nil
                    isStartingRecording = false
                    state = .error(error.localizedDescription)
                    errorMessage = error.localizedDescription
                    try? FileManager.default.removeItem(at: temporaryURL)
                }
            }
        } catch {
            isStartingRecording = false
            state = .error(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    private func pause() {
        recorder.pauseRecording()
        if let recordingStartedAt {
            accumulatedElapsed += Date().timeIntervalSince(recordingStartedAt)
        }
        recordingStartedAt = nil
        timerTask?.cancel()
    }

    private func resume() {
        recorder.resumeRecording()
        recordingStartedAt = Date()
        startTimer()
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                self?.refreshElapsedTime()
            }
        }
    }

    private func refreshElapsedTime() {
        if let recordingStartedAt {
            elapsedTime = accumulatedElapsed + Date().timeIntervalSince(recordingStartedAt)
        } else {
            elapsedTime = accumulatedElapsed
        }
    }

    private func temporaryRecordingURL(format: OutputFormat) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaurusRecorder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("\(UUID().uuidString).\(format.fileExtension)")
    }

    private func destinationURL(for pendingRecording: PendingRecording) throws -> URL {
        let trimmed = pendingFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? pendingRecording.suggestedBaseName : URL(fileURLWithPath: trimmed).deletingPathExtension().lastPathComponent

        if baseName == pendingRecording.suggestedBaseName,
           !FileManager.default.fileExists(atPath: pendingRecording.suggestedURL.path) {
            return pendingRecording.suggestedURL
        }

        return try fileNamingService.nextAvailableURL(
            in: saveFolderURL,
            baseName: baseName,
            format: pendingRecording.format
        )
    }

    private func clearPendingRecording() {
        pendingRecording = nil
        pendingFileName = ""
        isSavingPendingRecording = false
        activeSuggestedURL = nil
        accumulatedElapsed = 0
        elapsedTime = 0
    }

    private func showSavedConfirmation(for url: URL) {
        saveConfirmationTask?.cancel()
        lastSavedURL = url
        saveConfirmationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                if self?.lastSavedURL == url {
                    self?.lastSavedURL = nil
                }
            }
        }
    }

    private func bindRecorder() {
        recorder.onStateChange = { [weak self] newState in
            Task { @MainActor in
                self?.state = newState
            }
        }
        recorder.onMeterReading = { [weak self] reading in
            Task { @MainActor in
                self?.meterReading = reading
            }
        }
        recorder.onWaveform = { [weak self] points in
            Task { @MainActor in
                self?.waveformPoints = points
            }
        }
        recorder.onError = { [weak self] message in
            Task { @MainActor in
                self?.errorMessage = message
            }
        }
        recorder.onFinishedSaving = { [weak self] temporaryURL in
            Task { @MainActor in
                guard let self else { return }
                let suggestedURL = self.activeSuggestedURL ?? (try? self.fileNamingService.nextAvailableRecordingURL(
                    in: self.saveFolderURL,
                    format: self.activeFormat
                )) ?? self.saveFolderURL.appendingPathComponent("Recording.\(self.activeFormat.fileExtension)")
                let pending = PendingRecording(
                    temporaryURL: temporaryURL,
                    suggestedURL: suggestedURL,
                    format: self.activeFormat,
                    duration: self.pendingDuration
                )
                self.pendingRecording = pending
                self.pendingFileName = pending.suggestedBaseName
                self.recordingStartedAt = nil
            }
        }
    }
}
