# MultiAudio Architecture

## Problem

macOS routes system audio to a single default output device. Users with multiple Bluetooth headphones cannot watch the same content together without sharing earbuds.

## Solution (MVP)

Create a **Multi-Output Device** (stacked Core Audio aggregate) programmatically and set it as the system default output. Every app that plays through the default device — Netflix, Spotify, Safari, VLC, Music — automatically multiplies to all selected outputs.

## Research Summary

| Topic | Finding |
|-------|---------|
| Multi-Output Device | Mirrors the same mix to every sub-device |
| Aggregate Device | Combines channels into a wider device (not what we want for shared listening) |
| API | `AudioHardwareCreateAggregateDevice` (public, macOS 10.9+) |
| Multi-output flag | `kAudioAggregateDeviceIsStackedKey = 1` |
| Drift correction | `kAudioSubDeviceDriftCompensationKey` on non-master sub-devices |
| System routing | `kAudioHardwarePropertyDefaultOutputDevice` |
| Virtual driver | Not required for multi-output; useful later for capture/processing |
| DriverKit | Not required for this architecture |
| Private APIs | Not required for multi-output |

### Why not a virtual driver (BlackHole / DriverKit)?

Virtual drivers add install friction, signing requirements, and App Store barriers. Multi-output already solves simultaneous playback for the default-output path. A virtual device becomes valuable for per-app routing, latency tools, or processing — post-1.0.

### Why not independent streaming engines?

Capturing system audio, resampling, and streaming to each device independently requires a virtual input (or ScreenCaptureKit audio tap), custom clocks, and far more complexity. Latency control can be better, but time-to-working and reliability favor the HAL multi-output path first.

## Architecture

```
┌─────────────────────────────────────────────┐
│  AppKit (NSStatusItem + Main Window)        │
└─────────────────────┬───────────────────────┘
                      │
┌─────────────────────▼───────────────────────┐
│  SessionController (orchestration)          │
│  SessionStore / SettingsStore (persistence) │
└─────────────────────┬───────────────────────┘
                      │
┌─────────────────────▼───────────────────────┐
│  AudioDeviceService                         │
│  MultiOutputDeviceService                   │
│  CoreAudioHelpers                           │
└─────────────────────┬───────────────────────┘
                      │
┌─────────────────────▼───────────────────────┐
│  Core Audio HAL                             │
│  stacked aggregate → default output         │
└─────────────────────────────────────────────┘
```

> **UI note:** The first build uses AppKit so it compiles with Command Line Tools alone (SwiftUI property-wrapper macros require full Xcode). Core audio architecture is unchanged; SwiftUI can replace the shell later without touching the engine.

## Module layout

| Path | Role |
|------|------|
| `App/` | `@main`, composition root, lifecycle |
| `Core/Audio/` | Core Audio HAL wrappers |
| `Core/Models/` | Device, session, error types |
| `Core/Services/` | Session/settings stores + controller |
| `Features/` | Menu bar, devices, sessions, settings UI |
| `Views/Components/` | Shared UI pieces |
| `Resources/` | Info.plist |
| `Documentation/` | Architecture & decisions |
| `Scripts/` | Package into `.app` |

## Known limitations

1. **Bluetooth latency** — A2DP buffering is per-device; two headsets may not be perfectly lip-synced. Drift correction helps long-term skew, not absolute latency equality.
2. **No master volume** on multi-output devices — volume is adjusted per sub-device.
3. **Device disconnect** — losing a sub-device can break the aggregate; Reconnect rebuilds it.
4. **App Store** — creating system-visible aggregates and setting default output is generally fine with public APIs; sandbox may restrict some HAL operations. Outside-store distribution is the safe default until sandbox behavior is fully validated.

## Decision log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-07-16 | Option A: stacked aggregate multi-output | Public API, system-wide, minimal install friction |
| 2026-07-16 | Menu bar primary UI | Matches Raycast/CleanShot interaction model |
| 2026-07-16 | Codable JSON sessions (not SwiftData) | Simple, file-based, easy to inspect/debug for MVP |
| 2026-07-16 | Public (non-private) aggregates | Must appear as system default for all apps |
| 2026-07-16 | AppKit UI for MVP | CLT lacks SwiftUIMacros; AppKit ships a working menu bar app now |
| 2026-07-16 | Drift correction on non-master sub-devices | Bluetooth clocks diverge without it |
