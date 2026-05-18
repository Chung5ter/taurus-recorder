import AppKit
import Foundation

public struct ScreenCapturePermissionHelper {
    public init() {}

    public var onboardingMessage: String {
        "macOS requires System Audio Recording Only permission for computer audio capture."
    }

    public func openSystemAudioRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
