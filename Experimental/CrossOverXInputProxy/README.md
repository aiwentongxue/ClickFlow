# ClickFlow CrossOver XInput proxy

This experimental backend replays controller events from a ClickFlow combined
macro into one CrossOver/Wine game. It does not create a macOS HID device and
does not require Apple's restricted virtual-HID entitlement.

Current ClickFlow builds bundle the x86/x64 proxy set and expose the supported
workflow in the **Windows Games** page. That page is the recommended path for
end users because it discovers bottles, applies the runtime-validated game
profiles, backs up replaced files and registry values, diagnoses the result,
and can restore the pre-install state. The commands below remain useful for
development and controlled investigation.

```text
physical controller + ClickFlow combined macro
  -> /private/tmp/ClickFlow.xinput (32-byte state + heartbeat)
  -> native xinput*.dll loaded by the Windows game
  -> XInputGetState(0)
  -> Xbox-layout controller state
```

## Build

Install Homebrew `mingw-w64`, then run:

```sh
./Experimental/CrossOverXInputProxy/build.sh
```

The script builds x64 and x86 variants of `xinput1_1.dll`, `xinput1_2.dll`,
`xinput1_3.dll`, `xinput1_4.dll`, and `xinput9_1_0.dll` under `build/`.

Before installing anything, inspect the actual game executable (a CrossOver
macOS alias is also accepted):

```sh
./Experimental/CrossOverXInputProxy/inspect-target.sh /path/to/game.exe
```

The inspector is read-only. It resolves Finder aliases, reports x64/x86,
searches the executable and adjacent Unity player for XInput/HID/RawInput
evidence, and warns when common anti-cheat-sensitive filenames are present.

## Per-game setup

1. Determine the architecture and exact XInput DLL imported by the game.
2. Back up any same-named DLL beside the game executable.
3. Copy only the matching proxy DLL beside the executable.
4. Configure that DLL as native in the CrossOver bottle. For example,
   `WINEDLLOVERRIDES="xinput1_3=n"` selects the native `xinput1_3.dll`.
5. Record a ClickFlow combined macro containing controller events and play it.

The proxy exposes only synthetic user index 0. While ClickFlow is running, its
GameController input is continuously passed through to that user index. During
macro playback, each non-neutral macro control overrides only the matching
physical control; all other physical buttons, sticks, and triggers remain live.
Releasing a macro control, pausing, stopping, or reaching a loop boundary gives
that control back to the physical controller. When ClickFlow is not running or
its heartbeat is more than three seconds old, the proxy automatically forwards
all XInput calls and user indices to CrossOver/Wine's built-in XInput DLL. This
keeps physical controllers usable when ClickFlow was never opened or is quit
while the game is running, while still preventing duplicate physical input when
ClickFlow owns synthetic user index 0. The fallback defaults to the alternate
system DLL (`xinput1_4` for the other proxy names, or `xinput1_3` for the
`xinput1_4` proxy) to avoid recursively loading the proxy itself.

`CLICKFLOW_XINPUT_FALLBACK_DLL` can override that fallback path for controlled
diagnostics. It must resolve to a non-ClickFlow XInput DLL; proxy-to-proxy
fallback is rejected. Normal installations should leave this variable unset.

For a controlled diagnostic run, set `CLICKFLOW_XINPUT_TRACE_FILE` to a Windows
path such as `Z:\\private\\tmp\\ClickFlow.xinput.trace`. The proxy then appends
at most one line per second with the process ID, `XInputGetState` call count,
selected source (`clickflow` or `fallback`), result, packet sequence, connection
flag, and buttons. Tracing is off when the variable is absent.

## Aniimo live validation

On 2026-09-18, the x64 `xinput1_3.dll` build was loaded by
`Aniimo.exe` in the CrossOver Preview `20260821` `aniimo` bottle. Runtime module
inspection was essential: despite the Unity player containing several XInput
fallback names, this run loaded `xinput1_3.dll`, not `xinput1_4.dll`.

This Unity build initially selected `Windows.Gaming.Input` and therefore never
called the loaded XInput proxy. Disabling `windows.gaming.input` in this one
bottle made Unity log `fallback to XInputUsing XInput`; that setting is specific
to this tested bottle and should not be applied globally.

With a controller-only ClickFlow macro looping sticks and triggers, Aniimo's
own `XInputGetState(0)` calls returned success and the trace call counter grew
from 1 to 9,258. The trace observed both stick extremes plus `LT=255` and
`RT=255`.

On 2026-09-19, the fallback build was tested with the paired Xbox controller.
With ClickFlow never launched, Aniimo continuously polled `source=fallback`
with `result=0`. Launching ClickFlow changed the same running game process to
`source=clickflow`, `connected=1`; quitting ClickFlow changed it back to
`source=fallback`, `result=0` without restarting Aniimo. This validates both
cold-start fallback and live handoff back to the physical controller.

## Limits and safety

- Only games that call the overridden XInput DLL use this state. DirectInput,
  raw HID, GameInput, Windows.Gaming.Input, and statically linked input bypass it.
- This is per-game injection, not a system-wide virtual controller. IORegistry,
  GameController.framework, and native macOS apps do not see it.
- A game that separately opens the physical controller can still double-input.
- Do not install or test the DLL in anti-cheat or competitive online games. DLL
  overrides may be rejected or classified as process tampering.
- These are unsigned research builds. Rebuild them from source for each test.

For a distributable macOS-wide virtual controller, use CoreHID only after Apple
grants `com.apple.developer.hid.virtual.device`, or use an external USB HID
device if that entitlement is unavailable.
