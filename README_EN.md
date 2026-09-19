# ClickFlow

**Mouse Automation for macOS**

[简体中文](README.md) | [English](README_EN.md)

ClickFlow is a native macOS input automation utility built with Swift, SwiftUI, AppKit, Quartz, GameController, and a small Carbon API wrapper. It provides mouse and keyboard auto-clicking, global mouse macros, combined macros, global hotkeys, and menu bar controls.

## Macro loops and sharing

Both macro editors offer Once, Specified Count, and Unlimited playback. Enter the total number of plays directly, including the first play. Loop delays are independent of playback speed. Held mouse buttons and keys are released after each iteration. The playback bar shows the current loop and provides pause, resume, and stop controls.

Select a macro and click Export Macro to share its JSON file. Import Macro on either macro page detects the type, saves a new copy, and selects it without replacing existing macros or starting playback. Events, speed, repeat mode, count, and delay are preserved. Sharing files are limited to 20 MB; invalid or unsupported files report an error.

Mouse coordinates retain their original screen positions; recipients should adjust them for their display and target window. Controller events can be shared but retain the playback limitations described below.

## Features

- Automatically repeat the left, right, or middle mouse button, or a custom keyboard key.
- Single- and double-click gestures with finite or continuous execution.
- Two-way interval/CPS conversion from 10 ms–60 s or 0.0167–100 CPS.
- Use the current pointer position or a fixed Quartz global coordinate.
- Press the built-in global hotkey `⌘⌥X` to capture the current pointer position in fixed-position mode.
- Record mouse movement, three-button down/up events, dragging, and scrolling.
- Record the full mouse path or click positions only.
- Record combined mouse and keyboard input, plus controllers recognized by GameController such as Xbox, DualSense, and Switch controllers.
- Replay A/B/X/Y, D-pad, shoulders, triggers, sticks, Start/View, L3/R3, and Guide through the experimental CrossOver XInput proxy; while ClickFlow is running, physical controller input is passed through to the same XInput slot and mixed with the macro per control.
- The CrossOver Controller Macro Setup, Diagnostics & Restore entry at the bottom of Combined Macros opens a secondary page that discovers CrossOver installations and bottles, applies runtime-validated profiles for Aniimo, Genshin Impact, and Zenless Zone Zero, and provides per-game install, diagnostics, backups, and safe restore. See [CrossOver controller adapter](docs/CrossOverControllerAdapter.md).
- Continue recording at the end of an existing mouse or combined macro. Clicking the on-screen stop button is excluded from the saved recording.
- Sample mouse movement at approximately 60 Hz with a distance threshold to reduce redundant events.
- Play macros at 0.25×, 0.5×, 1×, 1.5×, 2×, or 4× speed.
- Schedule against absolute recorded timestamps so event-posting overhead does not progressively slow complex macros.
- Pause and resume mouse or combined macro playback. Pausing freezes the timeline and safely releases held inputs.
- Run once, repeat a specified number of times, or loop indefinitely with a configurable loop delay.
- Edit macro events in a table, delete multiple events, reorder steps, and undo changes.
- Capture any key or key combination as a global hotkey and apply changes immediately.
- Control ClickFlow from the menu bar, keep it running in the background, and use Emergency Stop.
- Use the interface in Simplified Chinese or English.

No user-action global hotkeys are assigned on a fresh installation. The Settings page organizes shortcuts into Auto Clicker, Mouse Macros, and Combined Macros. You can assign separate shortcuts for starting/stopping the auto clicker, starting/stopping recording, playing, pausing/resuming, and stopping macros. Matching start/stop actions may share one shortcut. `⌘⌥X` is reserved for capturing a fixed position. Whether macOS treats the top-row keys as F1–F12 depends on the function-key setting in System Settings > Keyboard.

## System and Development Requirements

- macOS 14 or later.
- Xcode 16 or later with Swift 6 support.
- Swift 6 strict concurrency checking is enabled.
- Debug builds target `arm64` by default; Release builds target `arm64 + x86_64`.

The initial project verification used the only Xcode installation available on the development Mac: **Xcode 27.0 Beta / Swift 6.4**. The project has not yet been reverified with the equivalent stable Xcode release.

## First Launch

When ClickFlow opens for the first time, it displays the disclaimer before initializing macros, global hotkeys, or automation features.

- Select **Agree** to store the current disclaimer version locally and continue to the main interface.
- Select **Decline and Quit** to close ClickFlow immediately.

The internal acceptance version can be increased in a future release if users need to review an updated disclaimer.

## Building

Open `ClickFlow.xcodeproj` in Xcode, select the ClickFlow scheme and My Mac, then run the project. The current working copy uses development team `HP5WBFL9G3` with Automatic Signing to keep the app identity stable for macOS privacy permissions. When building on another developer's Mac, select your own team under Signing & Capabilities.

Build and test from the command line:

```bash
xcodebuild -project ClickFlow.xcodeproj \
  -scheme ClickFlow \
  -configuration Debug \
  -destination 'platform=macOS' \
  build

xcodebuild -project ClickFlow.xcodeproj \
  -scheme ClickFlow \
  -configuration Debug \
  -destination 'platform=macOS' \
  test
```

Add `CODE_SIGNING_ALLOWED=NO` when you only need an unsigned compilation check.

## Permissions

### Accessibility

The auto clicker and macro players post mouse and keyboard events through `CGEvent`, so ClickFlow requires Accessibility/event-injection permission. ClickFlow checks permission with the system preflight API. Without permission, automation does not run silently; the app provides buttons to request access and open System Settings.

Authorization path: System Settings > Privacy & Security > Accessibility.

macOS may request authorization again if the signing identity, bundle identifier, or application path changes.

### Input Monitoring

Mouse and combined macros listen for mouse and keyboard events in other applications. ClickFlow does not request this permission at launch; it requests access only when recording begins.

Authorization path: System Settings > Privacy & Security > Input Monitoring.

Global hotkeys use `RegisterEventHotKey` and do not independently require Accessibility or Input Monitoring permission.

## App Sandbox

`ENABLE_APP_SANDBOX` is set to `NO`. ClickFlow's core purpose requires listening for and injecting input across applications; forcing these operations into the App Sandbox would unnecessarily restrict and destabilize them. The current project is intended for local source builds or direct distribution, not the Mac App Store.

Hardened Runtime remains enabled. A temporary ad-hoc or unsigned command-line build is not equivalent to a Developer ID-signed and notarized distribution.

## Data Storage and Privacy

Each macro is stored as a versioned JSON file at:

```text
~/Library/Application Support/ClickFlow/Macros/<UUID>.json
~/Library/Application Support/ClickFlow/CombinedMacros/<UUID>.json
```

Settings, recent-item identifiers, and disclaimer acceptance are stored in UserDefaults. ClickFlow does not delete or rewrite a damaged macro file; it skips the file, records the issue in OSLog, and notifies the user.

ClickFlow is offline by default:

- It does not upload macros or pointer paths.
- It contains no analytics SDK.
- It contains no telemetry.
- It does not send user interaction records.
- It does not access the network.

## ⚠️ Disclaimer

ClickFlow is a macOS mouse automation utility that provides features such as automatic clicking and mouse macro recording/playback.

ClickFlow is intended for lawful automation, productivity, accessibility, software testing, and educational purposes only.

By using ClickFlow, you acknowledge and agree that:

- You are responsible for complying with the terms of service and rules of any third-party software, game, website, or service you use with ClickFlow.
- Some applications and online services may prohibit automated input, macros, or similar tools. Use of ClickFlow may result in account restrictions or other consequences.
- ClickFlow must not be used for unauthorized access, cheating, abuse, disruption, circumvention of security mechanisms, or any unlawful activity.
- Automated mouse actions may interact with unintended UI elements due to changes in screen layout, window position, timing, display configuration, or application behavior.
- You should carefully test macros before using them for destructive, financial, irreversible, or otherwise sensitive operations.
- ClickFlow is provided "AS IS", without warranties of any kind.
- To the maximum extent permitted by law, the developer shall not be liable for any direct or indirect damages resulting from the use or inability to use ClickFlow.
- ClickFlow processes macro and configuration data locally by default and does not intentionally upload recorded mouse activity.
- ClickFlow is an independent project and is not affiliated with or endorsed by Apple Inc. or any third-party software or game developer unless explicitly stated otherwise.

Use ClickFlow responsibly.

## Project Architecture

- `App/`: application entry point, shared state, and automation mutual-exclusion coordination.
- `Models/`: auto-clicker, macro, event, and hotkey data models.
- `Services/`: CGEvent posting, event taps, clicking, recording, playback, hotkeys, permissions, settings, and storage.
- `Utilities/`: coordinate validation, sampling, scheduling logic, and OSLog.
- `Views/`: split navigation, auto clicker, macro editors, settings, disclaimer, and menu bar UI.
- `Resources/`: Simplified Chinese and English resources, Accent Color, and AppIcon.
- `ClickFlowTests/`: logic-focused unit tests.

UI state is isolated to MainActor. The auto clicker, recorders, players, and storage services use actors. Core Foundation event-tap run loops are confined to dedicated thread-safe wrappers. Every long-running operation retains a cancellable task, and Emergency Stop cancels clicking, playback, and recording.

## Coordinates and Multiple Displays

Recording and playback use Quartz global point coordinates from `CGEvent.location` and `CGDisplayBounds`. SwiftUI points, Retina backing pixels, and display pixels are not mixed. Before playback, ClickFlow verifies that all coordinates are inside the combined bounds of the currently connected displays. If a display-layout change moves an event outside those bounds, playback is blocked rather than silently rewriting the macro.

## Known Limitations

- Apple's public GameController API still cannot inject controller events into other macOS applications. Controller playback currently works only for CrossOver/Wine XInput games configured with the [experimental XInput proxy](Experimental/CrossOverXInputProxy/README.md); it is not a system-wide virtual controller. DirectInput, raw HID, GameInput, direct SDL input, and anti-cheat games may bypass or reject it.
- Conditional triggers and scripting are not implemented.
- Coordinates are not automatically remapped after a display-layout change.
- Trackpad inertia and gesture phases are not fully preserved; playback uses the captured horizontal and vertical scroll deltas.
- Exclusive Carbon hotkey registration detects many system conflicts but cannot detect every third-party shortcut implemented with nonexclusive event monitoring.
- System permissions require manual confirmation. Automated tests cannot replace runtime verification with real TCC authorization.
- The project has not yet been Developer ID-signed, notarized, or distributed as a DMG.

## Copyright

Copyright © 2026 我是艾文喵
