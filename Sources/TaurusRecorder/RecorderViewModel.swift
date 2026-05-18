import AppKit
import AVFoundation
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

struct LiveVisualFrame: Equatable, Sendable {
    let meterReading: MeterReading
    let waveformPoints: [WaveformPoint]

    static let empty = LiveVisualFrame(meterReading: .silence, waveformPoints: [])
}

@MainActor
final class LiveVisualStore: ObservableObject {
    @Published private(set) var frame: LiveVisualFrame = .empty

    func update(meterReading: MeterReading, waveformPoints: [WaveformPoint]?) {
        frame = LiveVisualFrame(
            meterReading: meterReading,
            waveformPoints: waveformPoints ?? frame.waveformPoints
        )
    }

    func reset(clearWaveform: Bool) {
        frame = LiveVisualFrame(
            meterReading: .silence,
            waveformPoints: clearWaveform ? [] : frame.waveformPoints
        )
    }
}

enum PermissionSettingsDestination: Hashable {
    case systemAudioRecording
}

struct PermissionIssue: Equatable {
    let message: String
    let destinations: Set<PermissionSettingsDestination>
}

struct AvailableCaptureApp: Identifiable, Equatable, Sendable {
    let bundleIdentifier: String
    let displayName: String

    var id: String { bundleIdentifier }

    var captureTarget: AudioCaptureTarget {
        .application(bundleIdentifier: bundleIdentifier, displayName: displayName)
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
    @Published var inputGain: InputGain = .unity {
        didSet {
            if appSettings.defaultInputGain != inputGain {
                appSettings.defaultInputGain = inputGain
            }
            recorder.updateInputGain(inputGain)
        }
    }
    @Published var captureTarget: AudioCaptureTarget = .allComputerAudio {
        didSet {
            guard oldValue != captureTarget else {
                return
            }
            startMonitoring()
        }
    }
    @Published var availableCaptureApps: [AvailableCaptureApp] = []
    @Published var errorMessage: String?
    @Published var permissionIssue: PermissionIssue?
    @Published var lastSavedURL: URL?
    @Published var isMonitoringStarting = false
    @Published var isStartingRecording = false
    @Published var recordingHistory: [RecordingHistoryItem] = []
    @Published var pendingRecording: PendingRecording?
    @Published var pendingFileName = ""
    @Published var isSavingPendingRecording = false
    @Published var renameTarget: RecordingHistoryItem?
    @Published var renameFileName = ""
    @Published var playbackItemID: URL?
    @Published var isPlaybackPlaying = false
    @Published var playbackElapsed: TimeInterval = 0
    @Published var playbackDuration: TimeInterval = 0
    @Published var playbackErrorMessage: String?

    let visualStore = LiveVisualStore()
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
    private var monitoringTask: Task<Void, Never>?
    private var monitoringRequestID = UUID()
    private var playbackPlayer: AVPlayer?
    private var playbackTimeObserver: Any?
    private var playbackEndObserver: (any NSObjectProtocol)?
    private var playbackDurationTask: Task<Void, Never>?

    init(appSettings: AppSettings, recorder: AudioRecorder = AudioRecorder()) {
        self.recorder = recorder
        self.appSettings = appSettings
        self.permissionMessage = permissionHelper.onboardingMessage
        self.saveFolderURL = appSettings.defaultSaveFolderURL
        self.outputFormat = OutputFormat.availableDefault(preferred: appSettings.defaultOutputFormat)
        self.inputGain = appSettings.defaultInputGain
        bindRecorder()
        refreshAvailableCaptureApps()
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
        case .idle, .monitoring, .error:
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

    var playbackProgress: Double {
        PlaybackTimeline(duration: playbackDuration).progress(at: playbackElapsed)
    }

    var meterStatusText: String {
        if !canStop {
            return "Ready to record \(captureTargetStatusName)"
        }
        return visualStore.frame.meterReading.isSilent ? silentMeterStatusText : activeMeterStatusText
    }

    var readyMeterStatusText: String {
        "Ready to record \(captureTargetStatusName)"
    }

    var silentMeterStatusText: String {
        "No \(captureTargetStatusName) detected"
    }

    var activeMeterStatusText: String {
        "\(captureTargetDisplayName) detected"
    }

    var defaultPreviewName: String {
        "\(fileNamingService.defaultBaseName())01.\(outputFormat.fileExtension)"
    }

    private var captureTargetStatusName: String {
        switch captureTarget {
        case .allComputerAudio:
            "computer audio"
        case .application(_, let displayName):
            "\(displayName) audio"
        }
    }

    private var captureTargetDisplayName: String {
        switch captureTarget {
        case .allComputerAudio:
            "Computer audio"
        case .application(_, let displayName):
            "\(displayName) audio"
        }
    }

    var captureTargetOptions: [AudioCaptureTarget] {
        var options: [AudioCaptureTarget] = [.allComputerAudio]
        options.append(contentsOf: availableCaptureApps.map(\.captureTarget))
        if !options.contains(captureTarget) {
            options.append(captureTarget)
        }
        return options
    }

    func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded(.down))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    func primaryControlTapped() {
        switch state {
        case .recording, .paused:
            stop()
        case .saving:
            break
        case .idle, .monitoring, .error:
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

        let recorder = recorder
        Task {
            await Task.detached(priority: .userInitiated) {
                await recorder.stopRecording()
            }.value
        }
    }

    func cancel() {
        timerTask?.cancel()
        recordingStartedAt = nil
        accumulatedElapsed = 0
        elapsedTime = 0
        visualStore.reset(clearWaveform: true)
        activeSuggestedURL = nil
        let recorder = recorder
        Task {
            await Task.detached(priority: .userInitiated) {
                await recorder.cancelRecording()
            }.value
        }
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

    func showPlayback(for item: RecordingHistoryItem) {
        if playbackItemID == item.id {
            resetPlayback(clearSelection: true)
            return
        }

        loadPlayback(item, shouldPlay: false)
    }

    func togglePlayback(for item: RecordingHistoryItem) {
        if playbackItemID != item.id || playbackPlayer == nil {
            loadPlayback(item, shouldPlay: true)
            return
        }

        guard let playbackPlayer else {
            return
        }

        if isPlaybackPlaying {
            playbackPlayer.pause()
            isPlaybackPlaying = false
        } else {
            if playbackDuration > 0 && playbackElapsed >= playbackDuration - 0.15 {
                seekPlayback(to: 0)
            }
            playbackPlayer.play()
            isPlaybackPlaying = true
        }
    }

    func skipPlayback(by seconds: TimeInterval) {
        guard playbackPlayer != nil else {
            return
        }

        let targetTime: TimeInterval
        if playbackDuration > 0 {
            targetTime = PlaybackTimeline(duration: playbackDuration).time(afterSkipping: seconds, from: playbackElapsed)
        } else {
            targetTime = max(0, playbackElapsed + seconds)
        }
        seekPlayback(to: targetTime)
    }

    func seekPlayback(toProgress progress: Double) {
        guard playbackPlayer != nil else {
            return
        }

        let targetTime = PlaybackTimeline(duration: playbackDuration).time(atProgress: progress)
        seekPlayback(to: targetTime)
    }

    func playbackControlSystemImage(for item: RecordingHistoryItem) -> String {
        playbackItemID == item.id && isPlaybackPlaying ? "pause.fill" : "play.fill"
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
                if playbackItemID == renameTarget.id {
                    resetPlayback(clearSelection: true)
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
            if playbackItemID == item.id {
                resetPlayback(clearSelection: true)
            }
            try FileManager.default.removeItem(at: item.url)
            refreshHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openScreenRecordingSettings() {
        permissionHelper.openSystemAudioRecordingSettings()
    }

    func startMonitoring() {
        guard state != .recording,
              state != .paused,
              state != .saving else {
            return
        }

        errorMessage = nil
        permissionIssue = nil

        monitoringTask?.cancel()
        let settings = captureSettings
        let requestID = UUID()
        monitoringRequestID = requestID
        isMonitoringStarting = true
        let recorder = recorder
        monitoringTask = Task { [weak self, recorder] in
            do {
                try await Task.detached(priority: .userInitiated) {
                    try await recorder.startMonitoring(captureSettings: settings)
                }.value
            } catch {
                await MainActor.run {
                    self?.present(error)
                }
            }
            await MainActor.run {
                if self?.monitoringRequestID == requestID {
                    self?.isMonitoringStarting = false
                }
            }
        }
    }

    func refreshAvailableCaptureApps() {
        let currentBundleIdentifier = Bundle.main.bundleIdentifier
        let appsByBundleIdentifier = Dictionary(
            grouping: NSWorkspace.shared.runningApplications.compactMap { application -> AvailableCaptureApp? in
                guard application.activationPolicy == .regular,
                      let bundleIdentifier = application.bundleIdentifier,
                      bundleIdentifier != currentBundleIdentifier else {
                    return nil
                }
                let displayName = application.localizedName ?? bundleIdentifier
                return AvailableCaptureApp(bundleIdentifier: bundleIdentifier, displayName: displayName)
            },
            by: \.bundleIdentifier
        )

        availableCaptureApps = appsByBundleIdentifier.values
            .compactMap { apps in
                apps.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }.first
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
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
        if inputGain != appSettings.defaultInputGain {
            inputGain = appSettings.defaultInputGain
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
            permissionIssue = nil
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
                    visualStore.reset(clearWaveform: true)
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
        visualStore.reset(clearWaveform: true)
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

        if let playbackItemID,
           !recordingHistory.contains(where: { $0.id == playbackItemID }) {
            resetPlayback(clearSelection: true)
        }
    }

    private func startRecording() {
        guard !isStartingRecording else {
            return
        }
        guard !isMonitoringStarting else {
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
            permissionIssue = nil
            pendingRecording = nil
            visualStore.reset(clearWaveform: true)
            accumulatedElapsed = 0
            elapsedTime = 0
            pendingDuration = 0
            isStartingRecording = true
            monitoringTask?.cancel()
            let settings = captureSettings
            let recorder = recorder
            resetPlayback(clearSelection: true)

            Task { [weak self, recorder] in
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try await recorder.startRecording(
                            outputURL: temporaryURL,
                            format: recordingFormat,
                            captureSettings: settings
                        )
                    }.value
                    await MainActor.run {
                        guard let self else { return }
                        self.recordingStartedAt = Date()
                        self.startTimer()
                        self.isStartingRecording = false
                    }
                } catch {
                    await MainActor.run {
                        self?.timerTask?.cancel()
                        self?.recordingStartedAt = nil
                        self?.accumulatedElapsed = 0
                        self?.elapsedTime = 0
                        self?.pendingDuration = 0
                        self?.isStartingRecording = false
                        self?.present(error)
                    }
                    try? FileManager.default.removeItem(at: temporaryURL)
                }
            }
        } catch {
            isStartingRecording = false
            present(error)
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

    private var captureSettings: AudioCaptureSettings {
        AudioCaptureSettings(target: captureTarget, inputGain: inputGain)
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

    private func loadPlayback(_ item: RecordingHistoryItem, shouldPlay: Bool) {
        resetPlayback(clearSelection: false)
        playbackItemID = item.id
        playbackElapsed = 0
        playbackDuration = 0
        playbackErrorMessage = nil

        let asset = AVURLAsset(url: item.url)
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        playbackPlayer = player

        playbackTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { [weak self, weak player] time in
            Task { @MainActor in
                guard let self, self.playbackItemID == item.id else {
                    return
                }
                self.playbackElapsed = Self.finiteSeconds(time.seconds)
                if let duration = player?.currentItem?.duration.seconds,
                   duration.isFinite,
                   duration > 0 {
                    self.playbackDuration = duration
                }
            }
        }

        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.playbackItemID == item.id else {
                    return
                }
                self.isPlaybackPlaying = false
                if self.playbackDuration > 0 {
                    self.playbackElapsed = self.playbackDuration
                }
            }
        }

        playbackDurationTask = Task { [weak self] in
            do {
                let duration = try await asset.load(.duration)
                await MainActor.run {
                    guard let self, self.playbackItemID == item.id else {
                        return
                    }
                    self.playbackDuration = Self.finiteSeconds(duration.seconds)
                }
            } catch {
                await MainActor.run {
                    guard let self, self.playbackItemID == item.id else {
                        return
                    }
                    self.playbackErrorMessage = error.localizedDescription
                }
            }
        }

        if shouldPlay {
            player.play()
            isPlaybackPlaying = true
        }
    }

    private func seekPlayback(to seconds: TimeInterval) {
        let target = max(0, seconds)
        playbackElapsed = target
        playbackPlayer?.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func resetPlayback(clearSelection: Bool) {
        playbackDurationTask?.cancel()
        playbackDurationTask = nil

        if let playbackTimeObserver, let playbackPlayer {
            playbackPlayer.removeTimeObserver(playbackTimeObserver)
        }
        playbackTimeObserver = nil

        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
        }
        playbackEndObserver = nil

        playbackPlayer?.pause()
        playbackPlayer = nil
        isPlaybackPlaying = false
        playbackElapsed = 0
        playbackDuration = 0
        playbackErrorMessage = nil

        if clearSelection {
            playbackItemID = nil
        }
    }

    private static func finiteSeconds(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite, seconds > 0 else {
            return 0
        }
        return seconds
    }

    private func bindRecorder() {
        recorder.onStateChange = { [weak self] newState in
            Task { @MainActor in
                guard let self else { return }
                self.state = newState
                if newState == .idle {
                    self.visualStore.reset(clearWaveform: false)
                    self.startMonitoring()
                }
            }
        }
        recorder.onVisualUpdate = { [weak self] reading, points in
            Task { @MainActor in
                guard let self else { return }
                self.visualStore.update(meterReading: reading, waveformPoints: points)
            }
        }
        recorder.onError = { [weak self] message in
            Task { @MainActor in
                self?.permissionIssue = nil
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

    private func present(_ error: any Error) {
        state = .error(error.localizedDescription)
        errorMessage = error.localizedDescription
        permissionIssue = permissionIssue(for: error)
    }

    private func permissionIssue(for error: any Error) -> PermissionIssue? {
        guard let recorderError = error as? RecorderError else {
            return nil
        }

        switch recorderError {
        case .systemAudioRecordingPermissionNeeded:
            return PermissionIssue(
                message: "Computer audio requires System Audio Recording Only permission. If it is already enabled, toggle Taurus Recorder off and back on, then quit and reopen the app.",
                destinations: [.systemAudioRecording]
            )
        default:
            return nil
        }
    }
}
