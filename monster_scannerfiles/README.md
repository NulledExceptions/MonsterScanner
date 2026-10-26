# Monster Scanner

A single-screen iOS 17+ "haunted camera" built with Swift + SwiftUI and no third-party dependencies.
The live rear camera feed gets a real-time night-vision horror filter; monsters spawn at random
compass bearings, an arrow guides you to them, and when you point the camera at one it jump-scares you.

It is also a survival score-attack game: the scanner runs on a battery that drains constantly and is
only recharged by catching monsters. Each catch scores points (with a speed bonus and a streak
multiplier), every three catches levels you up and tightens the hunt, and a monster you fail to find
before its hunt timer runs out escapes, breaking your streak. When the battery hits zero the run ends
with a score card and a tap-to-reboot.

## Requirements

- Xcode 16 or newer (the project uses Xcode 16's folder-synchronised groups, so every file you drop
  into the `MonsterScanner/` folder is picked up automatically — no pbxproj editing).
- A physical iPhone running iOS 17+. The Simulator has no camera and no magnetometer; the app
  launches there but shows "CAMERA OFFLINE" and never reveals anything.
- Set your team under Signing & Capabilities (bundle id defaults to `com.example.MonsterScanner`).

## Architecture

```
MonsterScanner/
├── MonsterScannerApp.swift        App entry; creates the single view model
├── Camera/
│   ├── CameraManager.swift        AVCaptureSession → CIImage frames on a video queue
│   ├── FilterPipeline.swift       FilterConfiguration + the Core Image "scary" chain
│   └── FilteredCameraView.swift   FrameStore hand-off + MTKView/CIContext renderer
├── Motion/
│   └── MotionTracker.swift        CMMotionManager → camera heading & pitch (Orientation)
├── Game/
│   ├── Monster.swift              Monster model, MonsterArt placeholders, AngularOffset
│   ├── MonsterSpawner.swift       Pure state machine: idle → spawned → (revealed | escaped) → cooldown
│   ├── GameSession.swift          Pure run state: score, streak multiplier, battery, level, rank
│   └── HighScoreStore.swift       UserDefaults persistence for high score / best streak / lifetime total
├── Audio/
│   ├── AudioManager.swift         AVAudioEngine cue playback (bundled file or synthesized)
│   ├── SoundSynthesizer.swift     Procedural placeholder cue + jump-scare sounds
│   └── HapticsManager.swift       UIKit feedback generators
├── ViewModel/
│   └── ScannerViewModel.swift     @Observable @MainActor; owns components + 20 Hz tick loop
├── Views/
│   ├── ContentView.swift          ZStack: camera, monster overlay, arrow, HUD, popups, game over
│   ├── ArrowView.swift            Direction arrow + hunt-timer ring + signal-strength bars
│   ├── MonsterOverlayView.swift
│   ├── HUDView.swift              Status, level/rank, battery, score, streak, best
│   ├── BatteryView.swift          Battery icon with discrete bars
│   ├── ScorePopupView.swift       "+150" popup and event toasts
│   └── GameOverView.swift         End-of-run score card (tap to reboot)
└── Support/
    ├── Log.swift                  One os.Logger per component
    ├── Angles.swift               Heading math helpers
    └── Theme.swift                HUD colours/fonts
```

Data flow per frame: `CameraManager` (video queue) → `FilterPipeline.apply` (builds a lazy CIImage
graph) → `FrameStore` → `CameraRenderer.draw` (Metal-backed CIContext, 30 fps, aspect-fill).

Game loop: `MotionTracker` pushes `Orientation` to the view model at 30 Hz; the view model ticks
`MonsterSpawner.update(now:orientation:)` every 50 ms and reacts to the returned events
(play cue / haptic, show overlay, fade out).

## Where to tweak things

| What | Where |
|---|---|
| Filter look (tint, grain, vignette, scanlines, flicker) | `FilterConfiguration` in `Camera/FilterPipeline.swift`. Live-tweak via `viewModel.filterConfiguration`. `FilterConfiguration.passthrough` shows the raw feed. |
| Spawn timing, reveal tolerance, reveal/cooldown durations, hunt timer, per-level difficulty curve | `SpawnerConfiguration` in `Game/MonsterSpawner.swift` (`scaled(toLevel:)`) |
| Points, speed bonus, streak multiplier, catches per level, battery drain / recharge / bars | `GameConfiguration` in `Game/GameSession.swift` |
| Motion smoothing / reference frame | `MotionConfiguration` in `Motion/MotionTracker.swift` |
| Camera resolution / frame rate | `CameraManager.Configuration` |
| HUD colour & fonts | `Support/Theme.swift` |

## Swapping in real assets

**Monster art:** add imagesets to `Assets.xcassets` named `monster-lurker`, `monster-screamer`,
`monster-crawler`, `monster-watcher`. `MonsterArtView` checks `UIImage(named:)` first and only
falls back to the SF Symbol placeholder when the asset is missing. Add/rename cases in `MonsterArt`
to change the roster.

**Sounds:** add any of `monster_cue`, `jump_scare`, `score_chime`, `level_up`, `signal_lost`,
`power_down` with a wav/caf/aiff/m4a/mp3 extension to the app target. `AudioManager` loads a bundled
file if present and otherwise uses `SoundSynthesizer`.

## Heading convention (read this if the arrow points the wrong way)

The camera's compass heading is derived from `CMAttitude.rotationMatrix`: the rear camera looks
along device −Z, and the matrix is treated as a reference→device rotation (the same convention
Apple's pARk sample uses as a view matrix), so the camera direction in world space is the negated
third row. That assumption lives in exactly one function, `MotionTracker.cameraForward(from:)`.
If on your device the arrow is mirrored relative to reality, set
`MotionConfiguration.useColumnConvention = true` and nothing else needs to change. The tracker
also logs its computed heading alongside `CMDeviceMotion.heading` every 5 s at debug level so you
can sanity-check in Console.

## Logging

Everything logs through `os.Logger` with subsystem = the app's bundle identifier and one category
per component (`Camera`, `FilterPipeline`, `Renderer`, `Motion`, `Spawner`, `Game`, `Audio`, `Haptics`,
`ViewModel`). In Console.app filter on the subsystem; set the log level to Debug to see
per-frame/per-tick diagnostics.
