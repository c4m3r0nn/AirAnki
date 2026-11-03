# Codex brief — release plumbing for AirAnki 1.0

## Context
AirAnki is a macOS 14+ menu-bar app (SwiftPM package in `AirAnki/`, Command Line Tools only — **no Xcode, no XCTest**) that turns a hand-held AirPod into an Anki remote. A companion Anki add-on lives in `anki-addon/airanki_bridge/` (Unix-socket bridge, Python, Qt via `aqt.qt`).

The owner wants to release AirAnki **for free to the public**. Claude is redesigning the whole UI in SwiftUI in parallel (in the main checkout). You do the non-UI plumbing below. Your work merges into Claude's branch afterwards, so stay strictly inside the files you are allowed to touch.

Tests: `./scripts/test.sh` (Swift self-test runner + Python add-on tests). Build: `./scripts/build_app.sh` → `build/AirAnki.app`. Read both scripts first.

## Hard rules
- Never `git push`, `git remote`, `git fetch`, `git pull`. Commit locally only.
- No hosted/production services. No signing up, logging in, paying, posting, contacting anyone. No CAPTCHA bypass, no Google automation.
- Never edit `.env*` files. No `sudo`, no `brew install`, no global installs (`pip install` included).
- Do not touch `~/Library/Application Support/Anki2`, do not launch/quit Anki, do not touch TCC, Bluetooth, or other running processes. Do not run the installer you write against the real Anki folder — test it only against temp directories.
- Do not run notarization or `codesign` with any identity other than ad-hoc (`-`).
- **Do NOT modify these files** (Claude is editing them): `AirAnki/Sources/AirAnki/AppDelegate.swift`, `StatusWindow.swift`, `MenuBar.swift`, `main.swift`, `FlickInput.swift`, anything under `AirAnki/Sources/AirAnki/UI/`, `AirAnki/Sources/AirAnkiCore/CentroidDetector.swift`, `anki-addon/airanki_bridge/flash.py`, `Resources/AppIcon*`. Do not edit `research/`.
- Keep the existing code style: terse Swift, small types, short comments only where non-obvious.

## Tasks

### 1. Remove the temporary bridge diagnostic log
In `anki-addon/airanki_bridge/commands.py`, delete the `try:` block that adds a `FileHandler` writing `~/Library/Logs/AirAnki/bridge.log` (keep `logger = logging.getLogger("airanki_bridge")`, the `NullHandler`, and `propagate = False`). In `__init__.py` remove the two `logger.info(...)` diagnostic lines ("Bridge listening on", "Bridge stop called"). Update `anki-addon/tests/test_bridge.py` so it no longer patches `os.makedirs`/`FileHandler` around the import.

### 2. Bridge version handshake
- `commands.py`: add `BRIDGE_VERSION = "1.0.0"` and include `"version": BRIDGE_VERSION` in **every** reply dict built by `handle` (and in the error replies built in `runner.py` and `__init__.py`). Add a test.
- `manifest.json`: add `"human_version": "1.0.0"`, keep `package` and `name`. Add `"homepage": ""` is NOT wanted — leave it out.
- Swift `AirAnkiCore/BridgeClient.swift`: add optional `version: String?` to `BridgeReply` (decoding must still accept replies without it). On `BridgeClient`, expose `public private(set) var lastVersion: String?` updated from each successful reply (thread-safety: follow whatever pattern the file already uses for shared state). Add to `BridgeServing` only if needed. Add a self-test.
- `ReviewController`: expose a read-only `bridgeVersion: String?` passthrough if the controller holds the bridge; keep it minimal.

### 3. Add-on installer logic (testable, in AirAnkiCore)
New file `AirAnki/Sources/AirAnkiCore/AddonInstall.swift`:
```swift
public enum AddonInstallState: Equatable, Sendable {
    case ankiNotFound                 // no Anki2/addons21 directory
    case notInstalled
    case installed(version: String)   // up to date (== bundled)
    case outdated(installed: String?, bundled: String)
    case developmentLink(target: String) // airanki_bridge is a symlink (developer setup) — never replace it
}
public struct AddonInstaller {
    public init(bundledAddon: URL, addonsDirectory: URL = AddonInstaller.defaultAddonsDirectory, fileManager: FileManager = .default)
    public static var defaultAddonsDirectory: URL   // ~/Library/Application Support/Anki2/addons21
    public static let folderName = "airanki_bridge"
    public var bundledVersion: String? { get }      // from bundled manifest.json "human_version"
    public func state() -> AddonInstallState
    public func install() throws                    // copy bundled add-on into addons21/airanki_bridge
}
```
Rules for `install()`:
- If `addons21` doesn't exist → throw a clear `AnkiError.message("Anki's add-ons folder wasn't found. Open Anki once, then try again.")` (use the existing error type in Core).
- If the destination is a symlink → do nothing and throw a message saying a developer link is installed.
- Otherwise copy to a temporary sibling (`.airanki_bridge.tmp-<uuid>`), then replace atomically (`replaceItemAt` or remove+move). **Preserve an existing `meta.json`** in the destination (Anki stores user config there) by copying it into the new folder before swapping. Never copy `__pycache__`, `tests`, `.DS_Store`, or `meta.json` from the bundle.
- Installed version = `human_version` in the installed `manifest.json` (nil if missing → `.outdated(installed: nil, …)`).
- Version comparison: dotted numeric (`1.0.10 > 1.0.9`); treat installed ≥ bundled as `.installed`.
Self-tests (in `AirAnki/Tests/AirAnkiCoreTests/`, registered in `SelfTestMain.swift` like the existing ones) using temp directories: not found, not installed, install fresh, outdated → install upgrades and keeps meta.json, symlink detected and never replaced, pycache/tests excluded, version comparison.

### 4. App-side helpers (new files in `AirAnki/Sources/AirAnki/`, AppKit allowed)
- `AnkiApp.swift`: `@MainActor enum AnkiApp` with `static let bundleIdentifier = "net.ankiweb.dtop"`, `static var isInstalled: Bool` (NSWorkspace urlForApplication), `static var isRunning: Bool`, `static func open()`, `static func restart() async` (terminate politely via `NSRunningApplication.terminate()`, wait up to 10 s for exit polling every 0.25 s, then open; never force-terminate). Also `static var bundledAddonURL: URL?` → `Bundle.main.resourceURL/AnkiAddon/airanki_bridge` if it exists, else (dev fallback) the repo's `anki-addon/airanki_bridge` resolved relative to the executable only if present.
- `LoginItem.swift`: `@MainActor enum LoginItem { static var isEnabled: Bool; static func setEnabled(_:) throws }` using `ServiceManagement.SMAppService.mainApp`. Note in a comment that it only works from an app bundle.
- `SystemSettings.swift`: `enum SystemSettings { static func openBluetooth(); static func openMotionPrivacy(); static func openSoundOutput() }` using `x-apple.systempreferences:` URLs (Bluetooth: `com.apple.BluetoothSettings`; Motion & Fitness privacy: `com.apple.preference.security?Privacy_Motion`; Sound: `com.apple.Sound-Settings.extension`). Fall back to opening System Settings app if a URL fails.
These are not wired into the UI by you — Claude will call them.

### 5. Packaging
- `Resources/Info.plist`: `CFBundleShortVersionString` 1.0.0, `CFBundleVersion` 1, add `CFBundleIconFile` = `AppIcon`, `NSHumanReadableCopyright` = "Free and open source. Not affiliated with Apple or Anki.", keep `LSUIElement`, keep bundle id. Rewrite `NSMotionUsageDescription` to: "AirAnki reads the motion of the AirPod in your hand so a flick can answer your Anki cards. Motion data stays on your Mac."
- `scripts/build_app.sh`: additionally copy `Resources/AppIcon.icns` into `Contents/Resources/` **if it exists**, and copy the add-on into `Contents/Resources/AnkiAddon/airanki_bridge/` (rsync or ditto, excluding `__pycache__`, `tests`, `meta.json`, `.DS_Store`). Accept an optional `ARCHS` env (default host arch). For multiple archs, build each with `swift build ... --triple <arch>-apple-macosx14.0` into separate build paths and `lipo -create`. If an arch fails to build, fail loudly (no silent fallback) — but `build_release.sh` decides what to pass.
- New `scripts/build_release.sh`: reads the version from Info.plist; tries `ARCHS="arm64 x86_64"`, and if the x86_64 build fails prints a clear warning and rebuilds arm64-only; then creates in `dist/`:
  - `AirAnki-<version>.dmg` — `hdiutil create -volname AirAnki -srcfolder <staging> -ov -format UDZO`, staging contains `AirAnki.app` + `Applications` symlink + `Install the Anki add-on.txt` (short: "AirAnki installs its Anki add-on for you on first launch. If you prefer, double-click AirAnki-Bridge-<v>.ankiaddon.").
  - `AirAnki-Bridge-<version>.ankiaddon` — a zip whose **root** contains the add-on files (`__init__.py`, `manifest.json`, …), excluding pycache/tests/meta.json.
  - `SHA256SUMS.txt`.
  - Optional notarization block that runs only if `NOTARY_PROFILE` and `DEVELOPER_ID` are set (`codesign --options runtime --timestamp -s "$DEVELOPER_ID"`, `xcrun notarytool submit --keychain-profile`, `xcrun stapler staple`). **Do not set these or run that path.** Otherwise ad-hoc sign.
  - Add `dist/` to `.gitignore`.
- Run `scripts/build_release.sh` once to prove it works (no icon file exists yet — that's fine; the script must tolerate it). Report artefact sizes and whether x86_64 built.

### 6. Public docs
- `LICENSE`: MIT, copyright line `Copyright (c) 2026 AirAnki contributors`.
- `docs/RELEASING.md`: how to cut a release (bump version in Info.plist + `BRIDGE_VERSION` + manifest `human_version`, run tests, run build_release.sh, optional notarization with a Developer ID, Gatekeeper note for unsigned builds: right-click → Open, or System Settings → Privacy & Security → Open Anyway).
- Do **not** rewrite README.md — Claude will write user-facing copy. Do not touch CODEX_REPORT/old docs.

## Checks before committing
- `./scripts/test.sh` passes (Swift self-tests + Python tests). Report counts.
- `./scripts/build_app.sh` passes; `codesign --verify --strict build/AirAnki.app`.
- `scripts/build_release.sh` produces the dist artefacts; `unzip -l` the .ankiaddon shows files at root and no pycache/tests.
- `git status` clean except intended files.

## Deliverables
Small, logically separated local commits (e.g. "Remove bridge diagnostic log", "Add bridge version handshake", "Add AddonInstaller", "App helpers", "Release packaging", "License and release docs"). Then `CODEX_REPORT.md` at the repo root: what changed per task, test counts, artefact list/sizes, whether universal build worked, any API you had to deviate from (and why), open questions.
