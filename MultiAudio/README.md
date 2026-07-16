# MultiAudio

Share Mac audio to **multiple Bluetooth (and wired) output devices at once**.

Native macOS menu bar app built with **AppKit** and **Core Audio**.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange)
![SPM](https://img.shields.io/badge/SPM-compatible-brightgreen)

---

## What it does

1. Lists available audio output devices  
2. Lets you select two or more  
3. Creates a **multi-output device** (same mechanism as Audio MIDI Setup)  
4. Sets it as the system default so **every app** plays to all selected devices  

Works with Netflix, YouTube, Spotify, VLC, Music, Safari, and anything else that uses the system default output.

---

## Requirements

- macOS 14 Sonoma or later  
- [Swift](https://www.swift.org) 5.9+  
  - **Xcode** from the Mac App Store, **or**  
  - Command Line Tools: `xcode-select --install`

---

## Quick start (clone → run)

```bash
git clone https://github.com/YOUR_USERNAME/MultiAudio.git
cd MultiAudio
chmod +x Scripts/package-app.sh
./Scripts/package-app.sh release
open dist/MultiAudio.app
```

That’s it. The menu bar shows a **waveform** icon.

### Build only (no `.app` bundle)

```bash
swift build -c release
swift run MultiAudio
```

---

## How to use

1. Connect two or more headphones/speakers  
2. Click the **waveform** icon in the menu bar  
3. Select the devices you want  
4. Click **Start Multi-Output**  
5. Play anything — audio goes to all selected devices  
6. Click **Stop** when done (restores previous output)  

Save frequent setups as **Sessions** for one-click reuse.

### Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘⇧S | Start / Stop session |
| ⌘⇧R | Reconnect active session |
| ⌘O | Open main window |
| ⌘Q | Quit |

---

## Project structure

```
MultiAudio/
├── Package.swift                 # Swift Package Manager manifest
├── Scripts/package-app.sh        # Build + package into .app
├── Sources/MultiAudio/
│   ├── App/                      # App entry, menu bar, main window
│   ├── Core/Audio/               # Core Audio multi-output engine
│   ├── Core/Models/              # Device / session models
│   ├── Core/Services/            # Session controller & persistence
│   └── Resources/Info.plist      # App bundle metadata
├── Documentation/ARCHITECTURE.md # Design decisions
└── Tests/                        # Model tests (need full Xcode for XCTest)
```

---

## Architecture

See [Documentation/ARCHITECTURE.md](Documentation/ARCHITECTURE.md).

**Short version:** uses the public Core Audio API  
`AudioHardwareCreateAggregateDevice` with `kAudioAggregateDeviceIsStackedKey`  
to create a multi-output device, then sets it as the system default output.

No private APIs. No kernel extensions. No virtual audio driver required for multi-output.

---

## Importing into GitHub

### Option A — GitHub website

1. Create a new empty repository on GitHub (no README/license if this folder already has them)  
2. In this folder:

```bash
git remote add origin https://github.com/YOUR_USERNAME/MultiAudio.git
git branch -M main
git push -u origin main
```

### Option B — GitHub CLI

```bash
gh repo create MultiAudio --public --source=. --remote=origin --push
```

### Option C — Drag & drop

GitHub → **New repository** → **uploading an existing file** works for small projects, but `git push` (A/B) is preferred so history is preserved.

---

## Known limitations

- Two Bluetooth headsets may have slight latency differences (hardware / A2DP)  
- Multi-output has no single master volume — adjust each device separately  
- If a device disconnects mid-session, use **Reconnect**  
- Unit tests need full **Xcode** (Command Line Tools alone do not ship XCTest)

---

## License

Use and modify freely for personal or commercial projects unless you add a different license file.
