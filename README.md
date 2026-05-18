# Taurus Recorder

Native SwiftUI macOS app for recording system audio with Core Audio process taps.

System recording programs for Mac exist, but they always felt somewhat complex because they had such rich features. This program is extremely bare bones for super simple use.

맥용 시스템 녹음 프로그램은 이미 많지만, 기능이 많다 보니 가끔은 조금 복잡하게 느껴질 때가 있습니다. 이 프로그램은 최대한 단순하게 사용하실 수 있도록 꼭 필요한 기본 기능만 담았습니다.

GitHub: [Chung5ter/taurus-recorder](https://github.com/Chung5ter/taurus-recorder)

DMG download: [latest release](https://github.com/Chung5ter/taurus-recorder/releases/latest)

## What It Includes

- Computer audio capture through Core Audio process taps.
- Audio writing through `AVAssetWriter`.
- Throttled RMS/peak audio meter before and during recording.
- Rolling waveform from the same captured audio buffers used for recording.
- App-specific audio capture, so one running app can be recorded without picking up other app audio.
- Notched input gain control from 1/3x to 3x with a live dB label.
- Default English filenames like `260507 New Recording 01.m4a`, incremented without overwriting.
- Save folder selector, post-stop save/delete confirmation, M4A/MP3/WAV output selector, and in-app playback mini-player.
- Native Settings panel available from the app menu or `Command + ,`.
- Plain System Audio Recording Only permission guidance inside the app.
- Core Audio monitoring runs while the app is idle so audio pickup is visible before recording.

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

Taurus Recorder captures outgoing audio through Core Audio process taps and uses macOS System Audio Recording Only permission.

MP3 export uses the system `afconvert` tool plus LAME because `AVAssetWriter` on macOS does not accept MP3 as an output file type. Install LAME with `brew install lame` if MP3 save fails.
