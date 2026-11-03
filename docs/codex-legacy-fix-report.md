# Legacy AnkiConnect fix report

Completed 2026-10-30 on `codex/v1-app`. This replaces the legacy compatibility limitation in the [original build report](docs/codex-v1-build-report.md).

## Changes

- Legacy API v6 now supports all three actions. Single tries the selected Easy/Good grade and shows the answer only after a definite `false`. Double tries Again, then, if refused, shows the answer, verifies the same card ID, and attempts Again once. A refused final grade produces error feedback.
- `guiCurrentCard` detects active review; null or the known inactive-review errors suppress all mutations, including Undo. Legacy status displays “Anki: reviewing” without inferring the card side.
- Removed legacy upgrade errors. V1 remains preferred, with its existing state-token and operation handling. The controller retains debounce, serialization, and read-only error reconciliation. Timeouts never trigger another mutation.
- Updated README and the human test sheet for Anki 23.10+ with the AnkiWeb legacy package, including Anki 26.5, and V1 on 26.08+.

Inspected the [AnkiWeb package for Anki 26.5](https://ankiweb.net/shared/download/2055492159?v=2.1&p=260500) in memory: 25,659 bytes. Its `guiCurrentCard` raises `Gui review is not currently active.` outside review; `guiAnswerCard` checks the answer side before grading. No add-on was installed or executed.

## Verification

- `./scripts/test.sh`: **42 tests, 0 failures** (0.124 seconds). XCTest is unavailable in this Command Line Tools installation; the script successfully ran the same test bodies through `AirAnkiCoreSelfTest`.
- Added 11 tests covering legacy question/answer flows, Easy/Good, card changes or disappearance, Undo, inactive review, refused/malformed results, and timeouts at every mutation stage. Updated the obsolete fail-closed test to verify successful legacy autodetection and grading. All tests are registered in the fallback runner; existing V1/controller/HTTP tests pass.
- `./scripts/build_app.sh`: **succeeded**, with no compiler warnings. Produced `build/AirAnki.app`; plist validation and ad-hoc signature verification passed.
- `git diff --check`: passed. Generated build files remain ignored.

## Unverified and constraints

Live Anki grading/Undo, AirPods input, UI, and audio remain unverified. The app was not launched; tests used mocks/intercepted HTTP and made no live Anki calls. Legacy cannot atomically guard against a card change between its final identity check and grading; this limitation is documented.

No Anki/add-on folders, Bluetooth, TCC, accounts, .env files, or system installations were touched. No hosted service was deployed or used for testing. Git operations are local only; no push, remote, fetch, or pull was performed.
