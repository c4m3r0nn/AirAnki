# AirAnki hardware-test fixes

Completed 2026-10-30 on `codex/v1-app`.

## Changes

- Added the AppKit **AirAnki** launch/status window, live connection/API/reviewer state, Listening/Paused status, last gesture/raw command/time/result, gesture table, Test connection, Pause/Resume, Hide and Quit. It starts around 420×300 and grows to fit wrapped text. Opening/reopening uses regular activation; closing returns to accessory mode and keeps the remote running. The menu can reopen the window.
- Added saved `ankiConnectPort` (default 8765, range 1–65535), configuration instructions and reconnection on committed edits. Busy actions/checks reject port changes with a retry instruction. Both API paths remain loopback-only. Legacy `version` and V1 `api.describe` probes distinguish unrelated listeners from network/authentication failures. Legacy and V1 reviewing remain supported; re-detection cannot bypass a pending V1 operation.
- Added `ignoreExplicitPlayPause=true` by default and the saved menu/window fallback toggle. Filtered play/pause events produce no gesture, display **ignored (ear detection?)**, and retain raw command/time in Lab CSV and unified logs with `detail=ignored-ear-detection`. Core mapping and event tracking are tested; late action completion cannot overwrite a newer ignored event.
- Updated README launch, port-clash and ear-detection guidance, with the attributed [AirKursor handheld setup](https://github.com/DinglyCoder/AirKursor#airpod-setup). Added **Test E — ear detection OFF**, ten raw-command trials, the one-bud open-case experiment and manual window/port checks in [docs/TESTING.md](docs/TESTING.md).

## Verification

- `./scripts/test.sh`: **67 tests, 0 failures**, including 25 new tests. XCTest is unavailable in this Command Line Tools installation; the script ran the same test bodies through `AirAnkiCoreSelfTest`. All tests are registered. HTTP tests use intercepted requests, never live Anki sockets.
- `./scripts/build_app.sh`: **passed with no warnings**; produced ignored local `build/AirAnki.app`.
- Source/bundled plist lint, `codesign --verify --strict --verbose=2`, `git diff --check`, and changed documentation file-link checks passed.

## Unverified and constraints

The app was **not launched**. Window layout, activation/Dock/reopen behaviour, hardware input, live Anki grading, audio and motion remain manual checks. The deliberate single-press raw command and handheld/open-case streaming with ear detection disabled are still unknown. AirKursor reports handheld motion setup; it does not establish AirAnki stem reliability.

No Anki/add-on files, Bluetooth settings, TCC, other running processes, accounts, `.env` files or system installations were touched. Public documentation access was read-only; no service was deployed or used for testing. Git work is local only: no push, remote, fetch or pull.
