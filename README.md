# Taurus Recorder

Native SwiftUI macOS app for recording system audio with ScreenCaptureKit.

System recording programs for Mac exist, but they always felt somewhat complex because they had such rich features. This program is extremely bare bones for super simple use.

Mac용 시스템 녹음 프로그램은 이미 있지만, 기능이 워낙 많다 보니 항상 조금 복잡하게 느껴졌습니다. 이 프로그램은 아주 단순한 사용을 위해 극도로 기본적인 기능만 담았습니다.

GitHub: [Chung5ter/taurus-recorder](https://github.com/Chung5ter/taurus-recorder)

DMG download: [v0.1.0 release](https://github.com/Chung5ter/taurus-recorder/releases/tag/v0.1.0)

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

Taurus Recorder only listens to system audio and does not save screen video. ScreenCaptureKit still requires Screen Recording permission for system audio capture.

MP3 export uses the system `afconvert` tool plus LAME because `AVAssetWriter` on macOS does not accept MP3 as an output file type. Install LAME with `brew install lame` if MP3 save fails.
