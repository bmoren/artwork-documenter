# Artwork Documenter

A native macOS app for documenting screen-based artworks. Guides you through a three-step process to produce a complete documentation folder on your Desktop containing a written description, screenshots, and a screen recording with system audio.

Built with SwiftUI and ScreenCaptureKit. No subscription, no uploads — everything stays on your Mac.

---

## What it produces

```
[Project Title] Documentation/
├── description.txt        — title, conceptual statement, technical details, URL
├── screenshot_01.png      — up to 5 screenshots (PNG or JPEG)
├── screenshot_02.png
└── screen_recording.mp4   — up to 3 minutes, with system audio (H.264/H.265, MP4/MOV)
```

---

## Requirements

- macOS 15 or later
- Xcode 16 or later (free from the Mac App Store, ~8 GB)
- No Apple Developer account required

---

## Build & run

```bash
# Install xcodegen if you don't have it
brew install xcodegen

# Clone and generate the Xcode project
git clone <repo-url>
cd "MCAD project docmuneter"
xcodegen generate

# Open in Xcode and press ▶ Run
open ArtworkDocumenter.xcodeproj
```

On first launch the app will ask for Screen Recording permission. Grant it in System Settings → Privacy & Security → Screen Recording, then return to the app.

---

## How it works

**Step 1 — Description**
Fill in a project title, a conceptual statement, technical attributes, and an optional URL. Export settings (codec, resolution, frame rate, image format) are adjustable here and default to 1080p H.264 MP4 / PNG.

**Step 2 — Screenshots**
Capture 3–5 screenshots of your artwork from any display or specific window. Thumbnails appear in a grid; each can be retaken individually.

**Step 3 — Screen Recording**
Record 1–3 minutes of your screen (system audio included automatically). After recording you can optionally insert an existing video clip at the beginning, end, or any scrubbed position before saving.

---

## Distribution

The app is signed to run locally (no notarization). To share it:

1. In Xcode: **Product → Archive → Distribute App → Copy App**
2. Zip the `.app` and share via AirDrop, email, or a shared folder
3. Recipients: right-click the `.app` → **Open** → click **Open** in the Gatekeeper dialog (one-time only)

---

## Tech stack

| Component | Purpose |
|---|---|
| SwiftUI + `@Observable` | UI and state management |
| ScreenCaptureKit | Screenshots and screen recording with system audio |
| AVFoundation | `AVAssetWriter` recording pipeline, video clip merging |
| ImageIO | PNG / JPEG screenshot saving |
| FileManager | Output folder written to `~/Desktop` |

---

## Project structure

```
ArtworkDocumenter/
├── ArtworkDocumenterApp.swift
├── Models/
│   ├── ProjectState.swift        — shared session state
│   └── ExportSettings.swift      — codec/resolution/format prefs (persisted to UserDefaults)
├── Managers/
│   ├── ScreenCaptureManager.swift — SCStream → AVAssetWriter recording pipeline
│   └── VideoMergeManager.swift    — AVMutableComposition clip insertion
├── Views/
│   ├── ContentView.swift          — step indicator shell
│   ├── SetupView.swift            — permission request screen
│   ├── Step1DescriptionView.swift — description form + export settings
│   ├── Step2ScreenshotsView.swift — screenshot capture and grid
│   ├── Step3RecordingView.swift   — recording controls, clip insertion, done state
│   └── VideoPlayerView.swift      — AVPlayerView wrapper for scrubbing
└── Resources/
    ├── Info.plist
    └── ArtworkDocumenter.entitlements
```
