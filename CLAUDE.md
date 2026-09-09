# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A macOS app (plus legacy CLI tools) that locks the active input source to a target ID and shows a small cursor-following overlay ("中" red / "A" blue) reflecting the IME's internal Chinese/English mode.

- **`LockChineseIME/`** — current focus. Full `.app` bundle: Dock icon, menu bar (NSStatusItem), settings window, launch-at-login via `SMAppService`. Packaged by `build-app.sh` into `build/锁定中文输入法.app`.
- **`InputMethodStatus/main.swift`** — legacy single-file CLI version (still works, preserved for terminal users).
- **`InputSourceLock/InputSourceLock/main.swift`** — legacy pure-terminal lock only. Kept for compatibility; no longer the recommended path.

The App and the CLI tools share the same TIS + CGEventTap core (`AppCore.swift` in the App, `InputMethodStatus/main.swift` in the CLI). Both use Apple's TIS API from `Carbon.HIToolbox` to read and select input sources, `Cocoa` for the NSPanel overlay, and `ServiceManagement` for launch-at-login.

## Build

### App (recommended)

```bash
bash build-app.sh
```

Produces `build/锁定中文输入法.app` — Apple Silicon (arm64), macOS 13+. Drag to `/Applications`, double-click to launch. First launch requires right-click → Open (unsigned).

### CLI tools (legacy)

```bash
cd InputSourceLock && bash build.sh
```

Produces both binaries into `InputSourceLock/build/`:

- `InputSourceLock/build/InputMethodStatus`
- `InputSourceLock/build/InputSourceLock`

Both `build-app.sh` and `build.sh` invoke `swiftc` directly — no SPM, no Xcode project.

## Run

### App

```bash
open build/锁定中文输入法.app
```

On first launch: dock + menu bar icons appear, settings window opens automatically. Configure the target IME in 设置窗口 → 锁定设置. Subsequent launches skip the settings dialog.

### CLI

```bash
# Status overlay only (no locking) — also lists available input sources then runs
./InputSourceLock/build/InputMethodStatus

# Lock + overlay (recommended)
./InputSourceLock/build/InputMethodStatus com.tencent.inputmethod.wetype.pinyin
```

Exit with `Ctrl+C` or `Cmd+Q`. The no-arg invocation opens a dialog to pick the target IME; the dialog's popup lists every enabled input source.

A standalone helper for listing input sources also exists:

```bash
swift InputSourceLock/list_input_sources.swift
```

## Tests / Lint / CI

None. There is no test target, no SwiftLint config, and no CI workflow. Don't introduce these without asking.

## Architecture

### Source layout

```
LockChineseIME/                            # current focus (App bundle)
├── main.swift                             # entry point (NSApplication.run)
├── AppDelegate.swift                      # NSApplicationDelegate, .regular activation
├── AppCore.swift                          # TIS helpers + InputMethodManager + StatusOverlayWindow
├── StatusBar.swift                        # NSStatusItem + menu (shows "中"/"A" dynamically)
├── Settings.swift                         # NSWindowController (single-page vertical layout)
├── LaunchAtLogin.swift                    # SMAppService.mainApp wrapper
├── Info.plist                             # bundle metadata + NSAccessibilityUsageDescription
└── Resources/                             # AppIcon.png (optional)

InputMethodStatus/main.swift               # legacy CLI single-file (TIS + overlay + lock)
InputSourceLock/InputSourceLock/main.swift # legacy terminal-only lock
InputSourceLock/list_input_sources.swift   # one-shot TIS lister
InputSourceLock/build.sh                   # compiles CLI tools
build-app.sh                               # packages LockChineseIME/ into .app
```

### `LockChineseIME/AppCore.swift` — the App's core

Same modules as the legacy `InputMethodStatus/main.swift`, refactored into a single file with clear sections:

1. **TIS helpers** — `getCurrentInputSourceID`, `tisGetString`, `isChineseCapableInputSource`, `getAvailableInputSources`. `asciiOnlyInputSourceIDs` is the hardcoded `Set<String>` of layout IDs (ABC, US, Dvorak, …) used as the heuristic for "is this a Chinese-capable IME".
2. **`StatusOverlayWindow: NSPanel`** — borderless, non-activating, floating level, click-through (`ignoresMouseEvents = true`), `canJoinAllSpaces` + `stationary` + `fullScreenAuxiliary`. Red 0.88/0.28/0.24 = Chinese, blue 0.22/0.55/0.92 = English, both at α 0.82.
3. **`InputMethodManager: NSObject`** — owns the overlay, the polling timer, and the CGEventTap. Three timers: 0.15 s `pollingTimer`, 0.08 s `cursorTrackTimer`, plus a `DistributedNotificationCenter` observer. Exposes `onStateChange` callback for the menu bar / settings window.

### `LockChineseIME/StatusBar.swift` — menu bar

`NSStatusItem` with a dynamic `attributedTitle` ("中" red / "A" blue) that flips with `isChineseMode`. The dropdown menu shows the current IME / mode / lock state and has an "打开设置…" item (Cmd+,) plus "退出" (Cmd+Q).

### `LockChineseIME/Settings.swift` — settings window

Single-page vertical scroll layout with six sections: 当前状态 / 锁定设置 / 悬浮窗 / 权限 / 开机启动 / 关于. The "辅助功能" status reflects `AXIsProcessTrustedWithOptions` in real time and provides an "打开系统设置" button that jumps to the Accessibility pane.

### `LockChineseIME/AppDelegate.swift`

- Sets `.regular` activation policy (required for Dock visibility; the legacy CLI used `.accessory`).
- First launch shows the settings window automatically. The "hasShownFirstRun_v1" `UserDefaults` key gates this.
- `applicationShouldHandleReopen` returns true so clicking the Dock icon opens the settings window.
- `applicationShouldTerminateAfterLastWindowClosed` returns false so closing the settings window does NOT quit the app — the menu bar icon keeps it alive.

### `LockChineseIME/LaunchAtLogin.swift`

Thin wrapper around `SMAppService.mainApp.register()` / `.unregister()`. Requires the app to be in `/Applications` for reliable behavior.

### Lock + state machine

- **Locking**: `onTick` reads `TISCopyCurrentKeyboardInputSource()` every 0.15 s. If `targetInputSourceID` is set and current ≠ target, calls `selectAndLockSource`, which iterates `TISCreateInputSourceList` (fetched once before the retry loop) and calls `TISSelectInputSource` with up to `maxLockRetry = 3` attempts spaced `lockRetryDelay = 0.02 s` apart.
- **Chinese/English mode** is a boolean `isChineseMode` that is **not** derived from the input source alone — it's toggled by a bare Shift press/release observed via CGEventTap. The state is reassigned on every transition by `start()` / `onTick()` / `selectAndLockSource()` (see Gotchas below). Chinese IMEs (WeChat, etc.) boot into English mode until the user presses Shift, which is why a bare Shift press is the toggle trigger.
- **Shift detection** uses `CGEvent.tapCreate` with `flagsChanged` + `keyDown` masks. The tap tracks `shiftHeld` and `otherKeyUsedWhileShift`; only a Shift press+release with no intervening non-Shift keyDown counts as a mode toggle. Shift keyCodes are 56 (left) and 60 (right).
- **Without Accessibility permission** the CGEvent tap fails to install — the program prints a warning and degrades to "input source change ⇒ reset to English mode" behavior. Shift toggles inside an IME are then invisible.

### `InputSourceLock/InputSourceLock/main.swift` — legacy

Same TIS primitives as the main program but: no overlay, no CGEventTap, `Timer.scheduledTimer` with `target:self`/`selector` style (Objective-C interop), and `RunLoop.current.run()` directly. Validates the target input source ID against `TISCreateInputSourceList` at startup. Don't port new features here — add them to `LockChineseIME/AppCore.swift` (and the legacy CLI in `InputMethodStatus/main.swift` only if the App isn't a fit).

### `InputMethodStatus/main.swift` — the legacy CLI

Single-file Swift program (`.accessory` activation policy) that mirrors `LockChineseIME/AppCore.swift` plus an inline `showInitDialog()` for picking the target IME at launch. Kept as a runnable CLI for terminal users who don't want the App.

## Gotchas (read before changing anything)

- **CGEventTap requires Accessibility permission** for the parent process (Terminal / iTerm). The program does not request it programmatically; the user must enable it in System Settings → Privacy & Security → Accessibility. Without it, the program still runs but Shift detection is silently disabled.
- **`build.sh` invokes `swiftc` directly** with no SPM involvement. The minimum supported macOS is whatever the user's `swiftc` accepts (in practice, anything with the TIS + CGEventTap APIs — effectively 10.6+).
- **Status-detection heuristic is input-source-id based, not character based.** A non-ASCII-capable layout ID is treated as English; anything else is treated as Chinese-capable. Adding a new pure-English layout requires adding its ID to `asciiOnlyInputSourceIDs`. The historical reason for this design is documented in `memory/2026-04-09.md` — earlier character-based and character-classifier approaches were tried and rejected.
- **`isChineseMode` is overwritten on every state transition.** The field declaration default value is unused at runtime — `start()`, `onTick()`, and `selectAndLockSource()` each assign it from scratch based on the current input source. Keep the three override sites consistent: when on the target input source, treat as Chinese; otherwise, treat as English. (The historical "default false" guidance predates the dialog-based initial-state selection — the current declaration defaults to `true`, but `start()` still picks correctly because it reads the actual input source on launch and applies the user-configured initial state.)
- **Overlay tracks the mouse cursor, not the text caret.** macOS does not expose a public API for text-caret position; `NSEvent.mouseLocation` is used as a proxy at 0.08 s intervals. There will be lag when the caret and cursor diverge (e.g. arrow-key navigation).
- **No code signing / notarization.** The binary is unsigned; first launch will require right-click → Open or removal of the quarantine attribute. This is intentional for a personal-utility project.
- **`pyproject.toml` is a stub** (workspace marker, no dependencies) — there is no Python in this project. Don't add Python tooling.
- **`MEMORY.md` and `memory/` are agent-only and gitignored.** They are not part of the codebase and must not be edited from project work.

## Conventions specific to this repo

- Single-file Swift programs; no module splitting. If a file is approaching ~500 lines, prefer a second top-level type in the same file over a new file.
- All user-facing strings are Chinese (Simplified) with emoji prefixes (🔒, 📍, ⌨️, ✅, ⚠️, 👋). Keep this style.
- Print to stdout for lifecycle events; reserve `print` warnings for degraded paths (missing permissions, failed lock retries).
- `unsafeBitCast(CFArrayGetValueAtIndex(...), to: TISInputSource.self)` is the established pattern for iterating `TISCreateInputSourceList` results — don't replace it with bridging casts without testing against the TIS headers.
