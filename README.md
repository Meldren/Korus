# Korus

Real-time live captions and translation overlay for macOS. Hear any audio playing on your Mac (a YouTube video, a Zoom call, a Twitch stream, a movie) and see it transcribed — and optionally translated to any of 60+ languages — in a floating panel on top of every other window.

![Korus overlay](docs/screenshot.jpeg)

- Native Swift / SwiftUI app, no Electron, no background services
- macOS 14.4+ (uses the modern CoreAudio Process Tap API — **no Screen Recording prompt**)
- Captures system audio, microphone, or both
- Streams to [Soniox](https://soniox.com) for transcription + one-way translation (`stt-rt-v4` model — Russian, English, Ukrainian and ~60 more languages, ≈6% WER)
- Side-by-side split view (original / translation) with a draggable divider
- Auto-saves every Listen session to disk: `original.txt`, `translation.txt`, `audio.wav` — nothing is lost on crash or accidental close
- Bring your own Soniox API key — pay-as-you-go (~$0.12/hr transcription, ~$0.18/hr with translation)

## Requirements

- macOS 14.4 or newer (Sonoma 14.4+ / Sequoia / Tahoe)
- A Soniox API key from [console.soniox.com](https://console.soniox.com)
- Xcode 15.4+ and `xcodegen` (`brew install xcodegen`) for building from source

## Install

### Build from source

```bash
git clone https://github.com/Meldren/Korus.git
cd Korus
xcodegen generate
open Korus.xcodeproj
```

In Xcode pick the `Korus` scheme and press ⌘R. The first launch will ask for **Microphone** permission and, the first time you press Listen, for **Audio Recording** (the macOS permission that backs the system-audio Tap API).

### Pre-built binary

Grab the latest `.app` from [Releases](https://github.com/Meldren/Korus/releases) (when published), drop it into `/Applications`, launch.

## First run

1. The overlay appears on launch with a "Welcome to Korus" prompt.
2. Click the gear icon → **Settings**.
3. Paste your Soniox API key. The language list auto-loads from the Soniox `/v1/models` endpoint.
4. Pick translation on/off in **Translation**.
5. In the toolbar pick **source language** (Auto works for most cases), **target language** (only when translation is on), and **audio source** (System / Microphone / Both).
6. Click **Listen** — captions appear as you speak or as audio plays.

The session cost (`≈ $0.001`) updates live next to the status chip — that's a local estimate based on the audio Soniox has actually billed for. Click the cost chip to open the Soniox Console for your real account balance.

## Toolbar at a glance

| Icon | Action |
|------|--------|
| ● Listening | Connection status |
| `$0.001` | Estimated session cost — click to open Soniox Console |
| **Listen / Stop** | Start/stop transcription |
| 🌐 Auto / Russian | Source / target language pickers |
| 🔊 System | Audio source |
| 📋 | Copy transcript to clipboard |
| 🗑 | Clear current transcript (resets cost chip too) |
| 📌 | Pin overlay above fullscreen apps |
| ⚙️ | Settings (disabled while listening) |
| 👁 | Hide overlay |
| ⏻ | Quit |

The vertical bar between original and translation is **draggable** — pull it left or right to rebalance the columns. Position is auto-saved.

## Session backup

Every Listen session writes to disk in real time. Default location:

```
~/Library/Application Support/Korus/sessions/2026-05-05 14-35-12/
├── original.txt      # raw transcribed text, plain UTF-8, no header
├── translation.txt   # translated text (only if translation was on)
└── audio.wav         # 16 kHz / mono / 16-bit PCM — exactly the bytes sent to Soniox
```

If the app crashes mid-stream, all three files are still on disk with everything captured up to that point. The WAV header is patched on graceful stop; if Korus didn't get to stop cleanly the file still contains valid PCM data — any audio editor can repair the header (or just open it as raw).

You can change the save location in **Settings → Session backup → Save folder**.

## Pricing context (Soniox)

All cost goes through Soniox — Korus itself is free. From [soniox.com/pricing](https://soniox.com/pricing):

- Real-time STT (`stt-rt-v4`): **~$0.12 / hour** of audio
- Real-time STT + one-way translation: **~$0.18 / hour**
- No subscriptions, pay-as-you-go, billed by tokens

Korus shows a live session estimate in the toolbar, but the authoritative balance lives in [console.soniox.com](https://console.soniox.com).

## Project layout

```
Sources/
  App/                AppDelegate, KorusApp
  Audio/              MicrophoneCapture, SystemAudioCapture (CATap), AudioCaptureCoordinator, SessionRecorder
  Soniox/             SonioxClient (WebSocket), SonioxLanguageService (REST), message types
  State/              AppSettings (UserDefaults), TranscriptStore, AppActions
  UI/                 OverlayWindow, SubtitleView, InlineSettingsView, KLogo, SplitColumnsView, VisualEffectBackground
Resources/            Info.plist, Korus.entitlements, Assets.xcassets
project.yml           XcodeGen spec — the .xcodeproj is generated, don't edit by hand
```

## Tech notes

- The dock icon and overlay header are rendered from a single `KLogoView` SwiftUI view; the dock icon is generated at launch via `ImageRenderer` so the binary ships without a real `.icns`.
- The frosted backdrop is an `NSVisualEffectView` (`.hudWindow`) wrapped via `NSViewRepresentable`, sitting under a tinted `RoundedRectangle`. The opacity slider tints the rectangle; the material handles the blur.
- The split between the two caption columns is a real `NSSplitView` (not SwiftUI `GeometryReader`) — that's what gives smooth live-resize on long transcripts.
- The system-audio Tap is created with the parameter-less `CATapDescription()` initialiser plus `processes = []` and `isExclusive = true`. The aggregate device follows the [insidegui/AudioCap](https://github.com/insidegui/AudioCap) pattern (Main subdevice = system output, `TapAutoStart = true`) — required for hardened-runtime apps to start without `kAudioHardwareIllegalOperationError`.

## License

MIT — see [LICENSE](LICENSE).
