# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## What this is

Two Swift-only macOS command-line tools sharing a single build script:

- **`InputMethodStatus`** — combined program: optionally locks the active input source to a target ID **and** shows a tiny cursor-following overlay ("中" red / "A" blue) reflecting the IME's internal Chinese/English mode.
- **`InputSourceLock`** — legacy pure-terminal lock only (no GUI). Kept for compatibility; no longer the recommended path.

Both use Apple's TIS (Text Input Sources) API from `Carbon.HIToolbox` to read and select input sources, and `Cocoa` for the NSPanel overlay.

## Build

```bash
cd InputSourceLock && bash build.sh
```

Produces both binaries into `InputSourceLock/build/`:

- `InputSourceLock/build/InputMethodStatus`
- `InputSourceLock/build/InputSourceLock`

The script is a thin wrapper around two `swiftc` invocations (Cocoa + Carbon frameworks). There is no SPM-based build; the `Package.swift` exists but is **not** wired into `build.sh` and has a known source-path issue (see "Gotchas" below).

## Run

```bash
# Status overlay only (no locking) — also lists available input sources then runs
./InputSourceLock/build/InputMethodStatus

# Lock + overlay (recommended)
./InputSourceLock/build/InputMethodStatus com.tencent.inputmethod.wetype.pinyin
```

Exit with `Ctrl+C` or `Cmd+Q`. The `--list` flag shown in `build.sh` output is **not** actually implemented in code — the no-arg invocation just prints the list as part of its startup banner.

A standalone helper for listing input sources also exists:

```bash
swift InputSourceLock/list_input_sources.swift
```

## Tests / Lint / CI

None. There is no test target, no SwiftLint config, and no CI workflow. Don't introduce these without asking.

## Architecture

### Source layout

```
InputMethodStatus/main.swift                       # combined lock + overlay (current focus)
InputSourceLock/InputSourceLock/main.swift         # legacy terminal-only lock
InputSourceLock/list_input_sources.swift           # one-shot TIS lister
InputSourceLock/build.sh                           # compiles both
InputSourceLock/Package.swift                      # SPM (currently unused by build.sh)
```

### `InputMethodStatus/main.swift` — the main program

Single-file Swift program organized top-to-bottom as four sections:

1. **TIS helpers** (top of file) — pure functions: `getCurrentInputSourceID`, `tisGetString`, `isChineseCapableInputSource`, `getAvailableInputSources`. `asciiOnlyInputSourceIDs` is a hardcoded `Set<String>` of layout IDs (ABC, US, Dvorak, …) used as the heuristic for "is this a Chinese-capable IME"; anything not in the set is treated as Chinese-capable.
2. **`StatusOverlayWindow: NSPanel`** — borderless, non-activating, floating level, click-through (`ignoresMouseEvents = true`), `canJoinAllSpaces` + `stationary` + `fullScreenAuxiliary`. Holds a colored `NSView` + a centered `NSTextField`. Red 0.88/0.28/0.24 = Chinese, blue 0.22/0.55/0.92 = English, both at α 0.82.
3. **`InputMethodManager: NSObject`** — owns the overlay, the polling timer, and the CGEventTap. Three timers: 0.15 s `pollingTimer` (status + lock), 0.08 s `cursorTrackTimer` (window follows `NSEvent.mouseLocation`), plus a `DistributedNotificationCenter` observer for `kTISNotifySelectedKeyboardInputSourceChanged` (with 50 ms debounce into `onTick`).
4. **`AppDelegate` + entry point** — sets `.accessory` activation policy, installs `SIGINT` handler that calls `NSApp.terminate(nil)`.

### Lock + state machine

- **Locking**: `onTick` reads `TISCopyCurrentKeyboardInputSource()` every 0.15 s. If `targetInputSourceID` is set and current ≠ target, calls `selectAndLockSource`, which iterates `TISCreateInputSourceList` and calls `TISSelectInputSource` with up to `maxLockRetry = 3` attempts spaced `lockRetryDelay = 0.02 s` apart.
- **Chinese/English mode** is a boolean `isChineseMode` that is **not** derived from the input source alone — it's toggled by a bare Shift press/release observed via CGEventTap. Default is `false` (English) on startup, on any input source change, and after a successful lock, because Chinese IMEs (WeChat, etc.) boot into English mode until the user presses Shift.
- **Shift detection** uses `CGEvent.tapCreate` with `flagsChanged` + `keyDown` masks. The tap tracks `shiftHeld` and `otherKeyUsedWhileShift`; only a Shift press+release with no intervening non-Shift keyDown counts as a mode toggle. Shift keyCodes are 56 (left) and 60 (right).
- **Without Accessibility permission** the CGEvent tap fails to install — the program prints a warning and degrades to "input source change ⇒ reset to English mode" behavior. Shift toggles inside an IME are then invisible.

### `InputSourceLock/InputSourceLock/main.swift` — legacy

Same TIS primitives as the main program but: no overlay, no CGEventTap, `Timer.scheduledTimer` with `target:self`/`selector` style (Objective-C interop), and `RunLoop.current.run()` directly. Validates the target input source ID against `TISCreateInputSourceList` at startup. Don't port new features here — add them to `InputMethodStatus/main.swift`.

## Gotchas (read before changing anything)

- **CGEventTap requires Accessibility permission** for the parent process (Terminal / iTerm). The program does not request it programmatically; the user must enable it in System Settings → Privacy & Security → Accessibility. Without it, the program still runs but Shift detection is silently disabled.
- **`Package.swift` is currently broken** with respect to its own source path (`path: "InputSourceLock"` is set but `build.sh` does not invoke `swift build`). The build script is the source of truth. Don't try to `swift build` from the repo root.
- **`build.sh` does not respect the `Package.swift` `macOS(.v12)` platform floor.** The script invokes `swiftc` directly; minimum OS is whatever the user's `swiftc` supports (in practice, anything with the TIS + CGEventTap APIs — effectively 10.6+).
- **Status-detection heuristic is input-source-id based, not character based.** A non-ASCII-capable layout ID is treated as English; anything else is treated as Chinese-capable. Adding a new pure-English layout requires adding its ID to `asciiOnlyInputSourceIDs`. The historical reason for this design is documented in `memory/2026-04-09.md` — earlier character-based and character-classifier approaches were tried and rejected.
- **Initial `isChineseMode = false` is load-bearing.** Setting it to `true` causes the overlay to display backwards for Chinese IMEs that boot into English mode. Three places enforce this default: `start()`, `onTick()`, and `selectAndLockSource()`. Keep them in sync.
- **Overlay tracks the mouse cursor, not the text caret.** macOS does not expose a public API for text-caret position; `NSEvent.mouseLocation` is used as a proxy at 0.08 s intervals. There will be lag when the caret and cursor diverge (e.g. arrow-key navigation).
- **No code signing / notarization.** The binary is unsigned; first launch will require right-click → Open or removal of the quarantine attribute. This is intentional for a personal-utility project.
- **`pyproject.toml` is a stub** (workspace marker, no dependencies) — there is no Python in this project. Don't add Python tooling.
- **`MEMORY.md` and `memory/` are agent-only and gitignored.** They are not part of the codebase and must not be edited from project work.

## Conventions specific to this repo

- Single-file Swift programs; no module splitting. If a file is approaching ~500 lines, prefer a second top-level type in the same file over a new file.
- All user-facing strings are Chinese (Simplified) with emoji prefixes (🔒, 📍, ⌨️, ✅, ⚠️, 👋). Keep this style.
- Print to stdout for lifecycle events; reserve `print` warnings for degraded paths (missing permissions, failed lock retries).
- `unsafeBitCast(CFArrayGetValueAtIndex(...), to: TISInputSource.self)` is the established pattern for iterating `TISCreateInputSourceList` results — don't replace it with bridging casts without testing against the TIS headers.
