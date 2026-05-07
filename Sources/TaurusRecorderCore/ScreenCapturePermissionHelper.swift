import AppKit
import Foundation
import ScreenCaptureKit

public struct ScreenCapturePermissionHelper {
    public init() {}

    public var onboardingMessage: String {
        "macOS requires Screen & System Audio Recording permission for computer audio capture. Microphone capture also requires Microphone permission. Taurus Recorder does not save screen video."
    }

    public func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    public func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
