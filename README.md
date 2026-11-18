# Mistral Vibe for macOS — dannmi fork

A native macOS desktop app for [Mistral Vibe](https://chat.mistral.ai/) (formerly Le Chat), built without Electron. This is a personal fork of [Alyetama/mistral-vibe-desktop](https://github.com/Alyetama/mistral-vibe-desktop) with additional fixes and features. Current version: **1.3.0 (6)**, maintained on the `versie-2` branch.

It wraps the Vibe web app in the system `WKWebView`, so it uses macOS's built-in WebKit instead of shipping a copy of Chromium. The result is a real `.app` that launches instantly, keeps you signed in, and weighs a fraction of a typical web wrapper.

|                  |                                                  |
| ---------------- | ------------------------------------------------ |
| **Engine**       | System WebKit (`WKWebView`) — no bundled browser |
| **Architecture** | Universal — Apple Silicon and Intel              |
| **Minimum OS**   | macOS 12 (Monterey)                              |
| **Version**      | 1.3.0 (6)                                        |

## What this fork adds

The upstream app is a minimal, clean wrapper (see [security notes](#notes) below). This fork adds the following on top.

### Reliable microphone access — v1.2.0

WKWebView has a known issue where `getUserMedia()` silently hangs and no permission prompt ever appears. This fork implements the `requestMediaCapturePermissionFor` delegate so the standard macOS system prompt appears reliably when a site requests the microphone or camera; the OS itself remains the gatekeeper. There is also a **Vibe → Enable Microphone Access…** menu item to pre-authorize the microphone before using voice features.

### Web notifications — v1.2.0

The app registers itself with the macOS notification center (via `UNUserNotificationCenter`) and requests notification authorization at launch, so web notifications can appear as banners even while the app is in the foreground. Best effort: exact delivery of web notifications depends on the macOS version.

### Find in page — v1.2.0

**⌘F** opens a search dialog that highlights all matches in the page (yellow, case-insensitive) and scrolls to the first one. Repeat **⌘F** with the same term to jump to the next match; clear the field to remove all highlights. macOS exposes no public find API on `WKWebView` (`findString`/`WKFindConfiguration` are iOS-only and `window.find()` is non-functional in WKWebView), so this uses a self-contained JavaScript highlighter.

### External links open in your browser — v1.3.0

Every link in an answer — whether a normal click or a link the web app opens through JavaScript — opens in a new tab of your default browser when it points outside the Vibe app itself. This includes `mistral.ai` subdomains such as `docs.mistral.ai` and normal `github.com` links, which stayed inside the app in earlier versions. Only the Vibe web app (`chat.mistral.ai`), its login flow, the auth providers and GitHub's OAuth connect flow used by Code Mode stay in the app; **⇧⌘B** still opens the current page in your browser.

### Open in browser / copy link — v1.2.0

**⇧⌘B** opens the current page in your default browser; **Go → Copy Page Link** copies the current URL to the clipboard.

### Canvas download fix — v1.1.0

Canvas exports arrive as `data:` URLs, which WebKit tries to *display* instead of downloading — so no file ever lands in `~/Downloads`. This fork intercepts `data:` navigations, decodes the file, saves it to `~/Downloads` as `Vibe-download <date>.<ext>` and reveals it in Finder. Server-suggested download filenames are also sanitized to their last path component (no `../` path traversal).

### Downloads menu — v1.1.0

**⌘J** shows the 10 most recent downloads in Finder; with no downloads yet it opens `~/Downloads`.

### Page zoom — v1.1.0

**⌘+** / **⌘−** / **⌘0** zoom in, out and reset. *Home* moved to **⇧⌘H**.

## Keyboard shortcuts

| Shortcut   | Action                        |
| ---------- | ----------------------------- |
| ⌘R         | Reload                        |
| ⇧⌘H        | Home                          |
| ⌘[ / ⌘]    | Back / Forward                |
| ⌃⌘F        | Enter Full Screen             |
| ⌘+ / ⌘− / ⌘0 | Zoom in / out / reset size |
| ⌘F         | Find in page                  |
| ⌘J         | Downloads                     |
| ⇧⌘B        | Open current page in browser  |

## Features (inherited from upstream)

- Stays signed in across launches (persistent cookie and local storage).
- Native menu bar with the shortcuts you expect — reload, history, full screen, and standard editing commands.
- File uploads through the native open panel; downloads land in `~/Downloads`.
- Links to Vibe and its sign-in providers stay in the app; everything else opens in your default browser (see v1.3.0 above).
- Closing the window keeps the app running in the Dock with your session intact; reopen it from the Dock icon, or quit with Command-Q.
- Window size and position are remembered between sessions.

## Build from source

This fork does not publish prebuilt, signed binaries — build it yourself so the binary matches the code you can read.

Requires the Swift toolchain that ships with Xcode or the Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/dannmi/mistral-vibe-desktop.git -b versie-2
cd mistral-vibe-desktop
./scripts/build.sh
open build/Vibe.app
```

Because you built it locally, macOS applies no quarantine flag and no Gatekeeper override is needed.

Build the styled drag-to-install installer (`dist/Vibe-<version>.dmg`):

```bash
./scripts/make-dmg.sh
```

Both scripts produce a universal binary by default. To target a single architecture, set `ARCHS`:

```bash
ARCHS="arm64"  ./scripts/build.sh    # Apple Silicon only
ARCHS="x86_64" ./scripts/build.sh    # Intel only
```

## Project layout

```
Sources/main.swift             The entire app — window, web view, menus, downloads, permissions
Resources/Info.plist           Bundle metadata (identifier, version, icon, usage descriptions)
scripts/build.sh               Compile and assemble Vibe.app
scripts/make-dmg.sh            Build the app and package it into a styled .dmg
scripts/make-icon.sh           Generate the app icon (Resources/AppIcon.icns)
```

## Configuration

Common adjustments live at the top of `Sources/main.swift`:

- **Home URL and in-app hosts** — the `Config` enum.
- **Default window size** — the `1100 × 760` values in `loadView` and `applicationDidFinishLaunching`.

The app version shown in **About Vibe** lives in `Resources/Info.plist` (`CFBundleShortVersionString` / `CFBundleVersion`); `make-dmg.sh` reads it to name the installer.

## Notes

This is an unofficial wrapper. It loads the Vibe website and nothing more — all functionality, accounts, and terms of service belong to Mistral. The code contains no telemetry, no analytics and no injected JavaScript; the only network activity is loading `https://chat.mistral.ai/` in the system web view.

## License

MIT
