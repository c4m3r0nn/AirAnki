# AirAnki motion-flick implementation report

Completed 2026-10-31 on `codex/v1-app`.

## Changes

- Added the Foundation-only `FlickDetector`, adapted from the supplied MIT AirClicker `FlickListener`. It projects rotation onto gravity, measures sample intervals with a rolling median, integrates actual elapsed time, rejects wind-ups and return swings, holds every flick for shake detection, and exposes accepted/rejected traces with reasons, peak yaw and angle.
- Added `FlickInput` as the app's sole `CMHeadphoneMotionManager`. Motion runs in normal mode, with connection callbacks, generation guards against queued samples after stop/disconnect, a 1.5-second no-data watchdog checked every 0.25 seconds, and denied/restricted permission guidance. Lab consumes the same raw samples and logs detector decisions as `flick_left`, `flick_right`, `shake` and `flick_rejected`.
- Right flick maps to `showOrGrade(ease: easeForRight)` (default Easy/4, optional Good/3); left maps to `showOrGrade(ease: 1)`; shake maps to Undo. V1 reads the card side and uses offered ratings/state tokens. Legacy attempts `guiAnswerCard(ease)` once and reveals only on a definite false. Neither motion flick uses the old reveal-then-immediately-grade-Again flow. Existing debounce, serialization, reconciliation and no-retry behavior remain shared with stems.
- Stems are opt-in through saved `stemInputEnabled=false`. With stems off, no silent audio or media-command capture starts, and stopping an unused stem input no longer touches Now Playing. Saved experimental stem mappings, including the older combined Again flow, remain available separately.
- Added saved Sensitivity, Reverse left/right, Right flick grades and experimental stem menu controls. The status window shows motion availability, Last gesture with time and actual result, the question/answer mapping, and the one-bud / ear-detection-off setup box. Pausing blocks review actions and clears unfinished gestures; active Lab recording can continue while paused.
- Added `AirAnkiReplay`, header-based CSV parsing including quoted fields, chronological marker association, event times and segment summaries. Replay uses the production detector, ignores recorded detector rows, and does not fabricate trailing samples to finish a held event at EOF.
- Updated README, `docs/TESTING.md`, motion usage text and third-party attribution. The test sheet includes labelled blocks of 10 right flicks, 10 left flicks, 5 shakes and 30 seconds of normal hand movement/typing, with replay instructions.

## Replay output

These are the complete normal outputs from the final release executable at default Medium sensitivity, reversal off. `t` is monotonic delivery time after the hold; marker numbers identify the segment at delivery.

```sh
AirAnki/.build/release/AirAnkiReplay research/data/two-buds-left-right-both.csv
```

```text
two-buds-left-right-both.csv sensitivity=medium motion_rows=1065
t=2632784.716 marker=1 left
t=2632786.196 marker=1 left
t=2632788.516 marker=1 left
t=2632803.716 marker=3 left
t=2632805.596 marker=3 left
t=2632807.596 marker=3 left
t=2632812.436 marker=3 left
segment 0: left=0 right=0 shake=0
segment 1: left=3 right=0 shake=0
segment 2: left=0 right=0 shake=0
segment 3: left=4 right=0 shake=0
segment 4: left=0 right=0 shake=0
```

```sh
AirAnki/.build/release/AirAnkiReplay research/data/handheld-free-flicks.csv
```

```text
handheld-free-flicks.csv sensitivity=medium motion_rows=1140
t=2632474.693 marker=0 right
t=2632477.213 marker=0 left
segment 0: left=1 right=1 shake=0
```

The structured recording gives **3 events in segment 1 and 4 in segment 3**, meeting the required combined minimum of seven. Segment 2, where only the non-reporting right bud moved, has **zero**; idle segments 0 and 4 also have zero. This is below the approximate five intended flicks per active segment. All detected yaw projections in this file are negative and therefore named left; the user's physical flick directions are unknown, so this is not a direction-accuracy result. The free-movement file has no markers/labels; its two detections cannot be classified as correct or false positives.

Both files also ran successfully with `--trace`. Low/High sensitivity options ran successfully on the structured file: Low produced 1 + 3 active-segment events, High 3 + 3, with zero elsewhere. High can also make a return/wind-up sharp enough to suppress a pending short flick, so increasing sensitivity need not increase the count.

## Tuning and differences from AirClicker

The initial literal angle path detected **zero** events in either file, despite the requested one-fast-sample adaptation at 25 Hz. Trace inspection showed that these handheld flicks were much shorter than the reference detector's 80–130° turns, and the reference integration discarded the first burst sample's entire interval.

The original constants remain: left/right peak thresholds **6.5 / 5.5 rad/s**, full angle **75°**, short angle **55°**, wind-up wait **0.35 s**, burst start/end **2.0 / 1.5 rad/s**, horizontal share **0.5**, repeat gap **0.35 s**, return gap **0.6 s**, and Low/Medium/High scales **1.35 / 1 / 0.75**. Angles are not sensitivity-scaled.

Changes and rationale:

1. **Measured-rate sharpness:** a rolling median of the last 31 valid intervals chooses one consecutive fast sample when the interval exceeds 30 ms, otherwise two. The actual sensor dt is used for angle integration; no fixed 50 Hz assumption remains.
2. **First-sample integration:** include the first burst sample's actual interval in the rectangle integral. A single sampled impulse previously integrated to zero. The seven accepted structured-recording bursts measure approximately **18.7–59.1°**, with peak magnitudes **7.35–16.42 rad/s**; measured angles are never artificially multiplied to reach 75°.
3. **Narrow compact-impulse extension:** preserve the original 75°/55° paths, but also admit a sharp, horizontal burst with angle **at least 15°** and **at most 160 ms between its first and last samples** as a short candidate. It must pass the same 350 ms wind-up wait and subsequent 450 ms shake hold. Five of the seven structured-recording detections use this extension; two use the original 55° short-angle path. This captures brief handheld wrist motions while retaining the original speed/horizontal checks. It is applied at both 25 and 50 Hz and tested at both rates; it is not conditional on filenames, marker ranges or direction.
4. **Shake arbitration:** three alternating yaw bursts above **4.0 rad/s × sensitivity** within one second emit Shake. Every candidate waits **450 ms**; a shake completing during that hold cancels all held/pending flicks. Motion is ignored for **800 ms** afterward. Return suppression starts at candidate qualification, before delivery, so delaying a flick does not allow its return to fire.
5. **Stream gaps:** a gap over **200 ms** discards unfinished/held work instead of integrating across missing data or delivering a stale action. The previous return-swing guard and shake cooldown survive such gaps. Non-finite and duplicate/out-of-order samples are ignored. Explicit stop/restart and configuration changes reset the detector.

The weaker recorded movements were not rescued by lowering the yaw peak thresholds: some resemble ordinary motion or lack a strong horizontal projection. The compact-impulse threshold still needs the labelled idle/typing and direction data to assess precision and recall. No changes were made to `research/data/`.

## Verification

- `./scripts/test.sh`: **89 tests, 0 failures** (67 existing + 22 new). XCTest is absent from this Command Line Tools installation, so the script ran the same test bodies through `AirAnkiCoreSelfTest`. All 89 test bodies are registered in the fallback runner.
- Synthetic streams exercise both **25 Hz and 50 Hz**: left/right, delayed delivery, short turns and compact impulses, wind-up cancellation, slow/non-horizontal rejection, late-peaking return swings, three-stroke shake without a flick, cooldown, same/opposite flicks one second apart, reversal, all sensitivity settings, adaptive fast-sample counts, sample gaps, reset and invalid timestamps. The recording regression asserts segment 2 is zero, segments 1+3 total at least seven, and idle segments are zero. CSV tests cover quoted fields and malformed input.
- Controller tests cover `showOrGrade(1)`, `(3)` and `(4)` on questions/answers through actual V1 and legacy clients with scripted transports; Undo on both APIs; unavailable ratings; legacy timeout without fallback/retry; shared stem/motion quiet period and busy lock; and no mutations outside review. Existing HTTP tests use intercepted requests, never live Anki sockets.
- `./scripts/build_app.sh`: **passed with no warnings**, producing local `build/AirAnki.app` and `AirAnki/.build/release/AirAnkiReplay`.
- Both final release replays, including `--trace`, passed. The equivalent repo-local `swift run ... AirAnkiReplay` path also built and ran during development.
- Source/bundled plist lint, `codesign --verify --strict --verbose=2`, documentation file-link checks, and `git diff --check` passed. The research data has no diff. Generated binaries, caches and logs remain ignored under local build directories.

## Unverified items and constraints

The app was **not launched**. Hardware left/right accuracy, live shake reliability, continuous motion with silent audio disabled, disconnect/reconnect and permission behavior, window layout/activation, live Anki grading/Undo, and audio coexistence remain manual checks in `docs/TESTING.md`. The supplied recordings contain no labelled shakes or known flick directions. A shake spread beyond the first flick's hold can allow that flick to be delivered before the third stroke; the UI/docs instruct a quick shake.

No Anki/add-on files, Bluetooth settings, TCC, other running applications, accounts, `.env` files or global installations were touched. No hosted service or network operation was used. Git work is local on `codex/v1-app`: no push, remote, fetch or pull. This report is included in the implementation commit; the final working-tree check follows the commit.
