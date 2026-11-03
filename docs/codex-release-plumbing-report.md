# AirAnki 1.0 release plumbing report

2026-11-03 · local branch `codex/release-plumbing-2026-11-03`

All six tasks in `CODEX_BRIEF.md` are complete. The release build succeeded for
**both arm64 and x86_64**, and the local artifacts are ad-hoc signed. Nothing was
published. The historical report is preserved verbatim below this report.

## Changes by task

1. **Diagnostic logging removed** (`07d7458`). Removed the temporary bridge
   FileHandler and startup/stop diagnostics. The logger retains its NullHandler
   and disabled propagation. Python tests import the command module directly.
2. **Version handshake** (`65049bb`). Bridge version `1.0.0` is present in command,
   busy, timeout, and socket parse-error replies and in the manifest's
   `human_version`. Swift accepts older replies without a version, exposes
   main-actor-isolated `BridgeClient.lastVersion`, and passes it through as
   `ReviewController.bridgeVersion`. Successful replies update or clear the
   cached version; unsuccessful replies leave it unchanged.
3. **Add-on installer** (`c491809`). Added the specified `AddonInstallState` and
   `AddonInstaller` APIs. Installs stage a filtered sibling folder and use
   `replaceItemAt` for existing destinations. Existing `meta.json` survives an
   upgrade, obsolete files disappear, and staging is cleaned up on failure.
   Valid and dangling developer symlinks are detected and never replaced.
   Numeric comparison accepts installed versions at least as new as the bundle.
   Nine new tests use temporary directories exclusively.
4. **App helpers** (`5a2bb16`). Added `AnkiApp`, `LoginItem`, and `SystemSettings`
   with the requested discovery, polite restart, resource lookup, login-item,
   and settings URLs. Restart polls every 250 ms for at most 10 seconds and
   returns without reopening if termination is refused, times out, or the task
   is cancelled. The development resource fallback searches ancestors of the
   executable. Helpers compile but are deliberately not wired into the UI.
5. **Packaging** (`6919723`). Updated Info.plist, added optional icon copying and
   filtered add-on bundling, architecture-specific build paths, universal
   assembly, the release DMG/archive/checksums script, and ignored `dist/`.
   Intel compilation failure has a distinct exit status (20); the release
   script alone handles the arm64 fallback. The optional Developer ID /
   notarization path is implemented but was not run. The app and add-on archive
   include the MIT license. `scripts/test.sh` now also runs the Python tests,
   correcting its previous Swift-only behavior.
6. **Public docs** (`e2d5d72`). Added the requested MIT license and
   `docs/RELEASING.md`, covering version bumps, checks, architectures, optional
   notarization, Gatekeeper, and the remaining UI integration. README and old
   documents were not rewritten.

## Verification

- `./scripts/test.sh`: **141 Swift tests, zero failures; 16 Python tests, all
  passed**. The CLT-only environment used `AirAnkiCoreSelfTest` after detecting
  the unavailable XCTest module. All 141 Swift test methods are registered
  exactly once. Logs: `build/final-tests.log`.
- `./scripts/build_app.sh`: passed for the host arm64 architecture; strict
  signature verification passed. The helpers compiled without warnings.
  Log: `build/app-build.log`.
- `env -u NOTARY_PROFILE -u DEVELOPER_ID ./scripts/build_release.sh`: passed.
  Both arm64 and x86_64 compiled; `lipo -archs` reports `x86_64 arm64`.
  `codesign --verify --strict --all-architectures build/AirAnki.app` passed;
  signature inspection reports `adhoc`, with no TeamIdentifier.
  Log: `build/release-build.log`.
- `unzip -l` and ZIP CRC checks passed. The `.ankiaddon` has eight root files:
  `__init__.py`, `commands.py`, `runner.py`, `flash.py`, `manifest.json`,
  `config.json`, `config.md`, and `LICENSE`. No enclosing folder, pycache,
  tests, `meta.json`, or `.DS_Store`; the bundled copy has the same exclusions.
- `hdiutil verify dist/AirAnki-1.0.0.dmg`: valid. Both SHA-256 entries match.
  App, manifest, and bridge versions agree at `1.0.0`; the build tolerates the
  absent `Resources/AppIcon.icns`.
- Three additional temporary-fixture packaging checks passed using mocked
  compiler/disk-image tools: Intel failure triggers arm64 fallback; arm64
  failure stops; signing failure stops. The fallback fixture also checks nested
  exclusions and staging cleanup. Local harness: `build/check_packaging_failures.py`.
  These are separate from the automated suite counts above.
- Shell syntax checks and `git diff --check` passed. Changes are limited to
  intended plumbing, tests, packaging, license, release docs, and this report.

## Artifacts

| Path | Size |
| --- | ---: |
| `dist/AirAnki-1.0.0.dmg` | 1,232,360 bytes |
| `dist/AirAnki-Bridge-1.0.0.ankiaddon` | 8,781 bytes |
| `dist/SHA256SUMS.txt` | 181 bytes |
| `build/AirAnki.app` | 2,710,965 bytes across 13 files |

The app size sums file lengths. `build/` and `dist/` are intentionally ignored;
the release scripts and this report are committed, not the generated binaries.

## API decisions and remaining integration

- The requested installer API is unchanged. `BridgeServing` gained the
  read-only `lastVersion` requirement because `ReviewController` holds the
  protocol rather than a concrete `BridgeClient`; its existing test fake was
  updated accordingly. `BridgeReply`'s new initializer argument defaults to nil.
- If a bundled manifest has no version, an existing install reports
  `.outdated(installed: ..., bundled: "unknown")`; installation rejects missing
  or invalid bundled numeric versions with a clear error before replacement.
- No unresolved question blocks the assigned plumbing work. Claude's separate
  UI work must call the installer and helpers for first-launch installation,
  restart, login-item controls, and settings links. The requested DMG text
  promises automatic installation, so that integration must land before public
  distribution. Actual Anki behavior, settings navigation, login registration,
  Intel execution, Developer ID signing, and notarization were not exercised.
- All installer tests used temporary directories. No real Anki profile/add-ons
  directory, Anki process, Bluetooth/TCC setting, protected UI file, icon, or
  research file was modified. No remote Git operation or publication occurred.

---

# Three-class calibrated remote report

2026-11-02 · local branch `codex/v1-app`

Implemented centroid recognition, reveal-only ambiguous events, V4 three-step calibration, adaptive templates/reset, keep-awake audio and the motion watchdog. **The requested replay accuracy targets are not all met.** Both recordings also fail the prescribed live template-similarity check. Diagnostic replay results below must not be treated as validated live calibrations.

## Constants and behavior

| Parameter | Production value |
| --- | --- |
| Feature / arming | Existing time-integrated 80 ms sum; quiet below 3 rad/s for 150 ms; onset above 3.5 |
| Template | Normalize the mean of unit stroke sums; store each class's median peak |
| Confidence | Best cosine ≥0.70 and best−runner-up ≥0.20 |
| Peak gate | `max(3.5, 0.55 × minimum class median peak)` |
| Sensitivity | Low/Medium/High multiply gate by 1.3/1/0.8; absolute floor 3 rad/s |
| Adaptation | Only confident cosine ≥0.80: normalize `0.85*u + 0.15*unit(s)` |
| Persistence / reset | Adapted V4 snapshots no faster than 30 s; reset restores saved original templates |
| Refractory | Onset ≥220 ms after any delivery; same-class deliveries ≥300 ms apart |
| Calibration | Six right, six left, six undo; peak ≥3.5; ignore 600 ms after each accepted capture |
| Quality | Every original pair cosine ≤0.5; redo only the current conflicting step |
| Keep awake | Default ON; AVAudioEngine loop of uniform noise ≈−75 dBFS RMS on default output |
| Watchdog | No samples for 2 s, checked every 250 ms; one Funk per outage while active; recovery clears warning |

Right/left/ambiguous reveal a covered card. Answer-side right grades Easy/Good, left Again, ambiguous sends `reveal` and receives no mutation plus Funk/“unclear flick — try again”. Undo sends one Undo on either side. Live input contains no shake detector or speculative compensation; historical LDA/legacy paths and their tests remain for comparison. BridgeClient is unchanged; bridge diagnostics in commands.py are preserved.

Calibration prompts request natural studying strength. Missing/invalid `flickCalibrationV4` triggers calibration. Both UI surfaces expose Keep AirPods awake and Reset to calibration. Audio runs during remote, Lab or calibration activity, restarts on engine configuration changes, and registers no media commands/Now Playing metadata. Experimental stems retain their separate existing behavior.

## Sweep

600 combinations per recording: gate multiplier `{.45,.50,.55,.60,.65,.70}`, best cosine `{.60,.65,.70,.75,.80}`, margin `{.10,.15,.20,.25,.30}`, adaptation `{0,.10,.15,.25}`. Score = correct −3×wrong confident class −3×idle confident −idle ambiguous. Wrong includes left→undo and undo→left/right. Ties prefer smallest total distance from the brief's defaults, then grid order. Production is selected on the new recording; the old sweep is diagnostic only.

| New rank | Gate | Cosine | Margin | Adapt | Correct | Wrong | Idle confident / ambiguous | Score |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 chosen | .55 | .70 | .20 | .15 | 13 | 1 | 0 / 2 | 8 |
| 2 | .50 | .70 | .20 | .15 | 13 | 1 | 0 / 2 | 8 |
| 3 | .55 | .65 | .20 | .15 | 13 | 1 | 0 / 2 | 8 |
| 4 | .55 | .70 | .15 | .15 | 13 | 1 | 0 / 2 | 8 |
| 5 | .60 | .70 | .20 | .15 | 13 | 1 | 0 / 2 | 8 |

| Old rank | Gate | Cosine | Margin | Adapt | Correct | Wrong | Idle confident / ambiguous | Score |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | .65 | .70 | .20 | .15 | 4 | 0 | 1 / 1 | 0 |
| 2 | .65 | .65 | .20 | .15 | 4 | 0 | 1 / 1 | 0 |
| 3 | .65 | .70 | .15 | .15 | 4 | 0 | 1 / 1 | 0 |
| 4 | .65 | .70 | .20 | .10 | 4 | 0 | 1 / 1 | 0 |
| 5 | .65 | .70 | .25 | .15 | 4 | 0 | 1 / 1 | 0 |

## Held-out confusion at the production constants

Training takes the first four accepted strokes per labelled class, applying the live 3.5 floor and 600 ms capture suppression. The whole training prefix is excluded from both evaluation and adaptation. Evaluation uses the same classifier and adapts in timestamp order. These are segmented-stroke counts, not individually matched trials; ignored includes weak/refractory candidates.

| File / segment | Total / excluded prefix | Right | Left | Undo | Ambiguous | Ignored |
| --- | --- | --- | --- | --- | --- | --- |
| New / 1 left | 15 / 4 | 0 | 6 | 1 | 3 | 1 |
| New / 2 right | 15 / 4 | 6 | 0 | 0 | 5 | 0 |
| New / 3 undo | 7 / 6 | 0 | 0 | 1 | 0 | 0 |
| New / 4 idle | 2 / 0 | 0 | 0 | 0 | 2 | 0 |
| Old / 1 right | 8 / 4 | 4 | 0 | 0 | 0 | 0 |
| Old / 2 left | 9 / 4 | 0 | 0 | 0 | 4 | 1 |
| Old / 3 undo | 6 / 4 | 0 | 0 | 0 | 2 | 0 |
| Old / 4 idle | 8 / 0 | 3 | 0 | 0 | 4 | 1 |

New score 8; old score −9. Both base gates are 3.5 rad/s. The new unlabelled prefix has one ambiguous event, excluded from scoring. The new undo prefix includes four accepted captures and two suppressed return candidates. At the old file's own sweep winner (gate .65, effective 4.082), right/left rows are unchanged; undo becomes 0/0/0/1/1 and idle 1/0/0/1/6.

New targets: left **6/11 <8/11**, right **6/11 <8/11**; zero left↔right errors, but one left→undo. Undo **1 correct, zero left/right** passes. Idle **0 confident** passes; **2 ambiguous >1** fails. No higher-scoring configuration exists in the stated grid. The last five right stroke sums turn mainly toward +y, away from the early template; confidence-gated adaptation cannot follow that abrupt change. Summed-window directions differ from the instantaneous peak vectors quoted in the brief.

Training similarity is **0.68 right/undo on new**, **1.00 rounded left/undo on old**, above the required 0.5. Replay explicitly permits structurally valid but similar templates for offline diagnosis and prints a warning; live construction/loading/detection and replay export reject them. No per-file exceptions or hand-selected training strokes were added. New data with more distinct gestures is needed to validate usable V4 calibration. Hyperparameters were selected using these held-out strokes, so this is not an independent hyperparameter test set.

## Reproduction

```sh
scripts/test.sh
python3 -m unittest discover anki-addon/tests
scripts/build_app.sh
AirAnki/.build/release/AirAnkiReplay research/data/natural-left15-right15-shake5-idle.csv --detector centroid --labels left,right,undo,idle --label-start 1 --calibrate-from-labels 4
AirAnki/.build/release/AirAnkiReplay research/data/labelled-right10-left10-shake5-idle.csv --detector centroid --labels right,left,undo,idle --label-start 1 --calibrate-from-labels 4
# Append --sweep to either replay command for its top five and winning configuration.
```

## Checks and unverified items

- `scripts/test.sh`: **128 tests, 0 failures** (CLT lacks XCTest; same test bodies run via AirAnkiCoreSelfTest; all 128 registered exactly once). Includes three-class decisions, reveal-only mapping on both sides, single undo/busy behavior, adaptation/reset/throttling, gate scaling, capture quality/return suppression, V4 persistence, watchdog recovery, 25/50 Hz timing and exact recording/sweep regressions. Existing LDA/legacy regressions pass.
- `python3 -m unittest discover anki-addon/tests`: 11 passed, including reveal on question/answer/outside review. Tests suppress only diagnostic file I/O; production logging remains intact.
- `scripts/build_app.sh`: **passed without warnings**, including plist validation, ad-hoc signing and strict signature verification. App not launched. `git diff --check` passed. Historical `--detector lda|legacy` comparison commands checked.
- Unverified: physical connection retention/inaudibility, output-route recovery, music/call coexistence, live calibration/UI layout, sustained grip drift, real Anki behavior and peak-to-visible-card latency. Legacy AnkiConnect lacks reliable answer-side state and may report an already-visible reveal as successful; exact unclear feedback needs Bridge or V1.
- No push/remote/fetch/pull, hosted services, accounts, `.env`, global installs, installer/app launches, Anki/Anki2 access, Bluetooth/TCC changes or unrelated process manipulation. `research/data/` is unchanged. This report and implementation are committed locally on `codex/v1-app`.
