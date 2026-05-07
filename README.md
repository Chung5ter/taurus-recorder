# Taurus Recorder

Native SwiftUI macOS MVP for recording system audio with ScreenCaptureKit.

GitHub: [Chung5ter/taurus-recorder](https://github.com/Chung5ter/taurus-recorder)

## What It Includes

- System-audio-only capture through `ScreenCaptureKit`.
- Audio writing through `AVAssetWriter`.
- Live RMS/peak audio meter before and during recording.
- Rolling waveform from the same captured audio buffers used for recording.
- Default Korean filenames like `20260507 새로운 녹음01.m4a`, incremented without overwriting.
- Save folder selector, post-stop save/delete confirmation, and M4A/MP3/WAV output selector.
- Native Settings panel available from the app menu or `Command + ,`.
- Plain Screen Recording permission guidance inside the app.

## Build

```bash
swift build
```

Create a local `.app` bundle:

```bash
Scripts/build-app-bundle.sh
open ".build/release/Taurus Recorder.app"
```

Create a drag-and-drop installer DMG:

```bash
Scripts/build-dmg.sh
open "dist/Taurus Recorder.dmg"
```

Run the core behavior checks:

```bash
swift run CoreBehaviorTests
```

## Notes

The MVP intentionally does not add a microphone path and does not register a video stream output. ScreenCaptureKit still requires Screen Recording permission for system audio capture.

MP3 export uses the system `afconvert` tool plus LAME because `AVAssetWriter` on macOS does not accept MP3 as an output file type. Install LAME with `brew install lame` if MP3 save fails.
