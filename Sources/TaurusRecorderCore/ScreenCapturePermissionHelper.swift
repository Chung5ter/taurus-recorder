import AppKit
import Foundation
import ScreenCaptureKit

public struct ScreenCapturePermissionHelper {
    public init() {}

    public var onboardingMessage: String {
        "macOS requires Screen Recording permission for system audio capture. Taurus Recorder only listens to system audio and does not save screen video."
    }

    public func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
