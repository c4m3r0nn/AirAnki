# AirAnki v2 implementation report

2026-11-01 · local branch `codex/v1-app`

The bridge, calibrated detector, calibration UI, faster fallback, replay tooling and documentation are implemented. **The accuracy targets are not all achieved.** The final default replay finds 6/7 intended held-out right flicks, 1/7 left flicks and 1/5 shakes, with 4 idle false positives. The new detector's flick decision latency is 40 ms from onset in this recording, versus 880 ms median for legacy. Live peak-to-card latency remains unmeasured because the app and Anki were not launched.

## Changes

- Added `anki-addon/airanki_bridge`: owner-only QLocalServer socket at `~/Library/Application Support/AirAnki/bridge.sock`, persistent newline JSON, request IDs, right/left/reveal/grade, bounded multi-undo, state and ping. Directory creation uses 0700 and the socket uses Qt UserAccessOption. Server starts at main-window initialization/import, restarts on profile open and closes on profile close/app exit. Requests and errors are handled on Qt's main thread; logging is confined to the add-on logger.
- Factored Qt-free `handle(cmd, mw)` into `commands.py`. Real Anki grading and undo are asynchronous: `runner.py` acknowledges through completion hooks and issues each subsequent undo only after the previous one finishes, rechecking history. A 250 ms deadline returns an uncertain-outcome error; it is a one-shot deadline, not a servicing/polling timer. The pending lock remains until completion, with remaining undo steps cancelled after timeout.
- Added `scripts/install_addon.sh`, with refusal to overwrite a non-symlink. **It was not run.** No Anki installation/profile files were accessed.
- Added `BridgeClient` in AirAnkiCore: one persistent nonblocking Unix descriptor, serial worker queue, partial-frame handling, bounded input, monotonically increasing IDs, 300 ms total connect/write/read deadline, SIGPIPE protection and 100 ms–2 s reconnect backoff. Only failures before connection permit fallback; uncertain sends/replies never cause another mutation.
- ReviewController uses Bridge first and takes result/side from its one reply. AnkiConnect's common flick path now prefers legacy `guiAnswerCard` then, only on definite false, `guiShowAnswer`, even when V1 is present. No pre/post state reads occur on this common path. V1 is used for status; if legacy is unavailable its exceptional action path remains, with operation polling reduced to 15 ms.
- Preserved the old detector as `LegacyFlickDetector`, including its existing regression tests. Added a Foundation-only calibrated device-frame detector, unit-mean templates, median peak scale, first-run five-right/five-left calibration, progress/Tink feedback, saved calibration, Recalibrate menu action, reverse and sensitivity controls, and saved Instant flicks (default on).
- Default constants match the brief: quiet 2 rad/s for at least 60 ms; onset 3.5 uncalibrated or 0.45×median calibrated; classify when rising stops or after two above-onset samples, within the first three samples; cosine ≥0.55, score margin ≥0.25 and peak ≥0.5×median; 220 ms refractory, 300 ms same-direction spacing; three alternating axis lobes of ≥0.4×median within 600 ms; 600 ms shake cooldown. Low/Medium/High scale magnitude and cosine thresholds by 1.35/1/0.75. Calibration ignores return captures for 600 ms. Stream gaps above 200 ms cancel unfinished work, retaining cooldown/refractory protection.
- The first flick can act speculatively. Shake carries its exact flick timestamp; the controller waits for that result and requests undo count=2 after a grade, count=1 after a reveal/no action. Uncertain results stop compensation. A possible shake's second stroke cannot launch a second speculative action, even when separated by more than 220 ms. Non-instant mode holds for 300 ms; a later shake also compensates an already delivered held action.
- Shared debounce is now 120 ms. Sound is preloaded and played on gesture delivery. Motion/detection run on a dedicated serial OperationQueue; immutable Lab snapshots go to a separate formatting/buffering/writing queue. Normal motion does no string formatting and only posts UI liveness at 10 Hz or on events. Window updates are coalesced to 10 Hz. Last latency uses live host fire time through the action reply and is logged as `action_latency`.
- README and TESTING describe installation, calibration, modes, compensation, latency and the single-stream hardware limit. Test F covers recalibration, marked accuracy/idle blocks, then a practice Anki deck. No dual-bud code was added.

## Replay evaluation

Commands, run using the final release executable:

```sh
AirAnki/.build/release/AirAnkiReplay research/data/labelled-right10-left10-shake5-idle.csv \
  --labels right,left,shake,idle --label-start 1 --calibrate-from-labels 3 \
  --expected 10,10,5,0 --detector new
# Same command with --detector legacy for comparison.
```

Training uses only the first three quiet-armed captures per labelled direction; their return tails through 600 ms are excluded from evaluation on both detectors. No later samples enter the templates. These are **segment-level counts**, not individually annotated trial matches; `nothing` is intended count minus net emitted gestures, so wrong-direction events are separate from missing events. Raw speculative flicks are printed but removed from net counts when compensated by a shake.

| Label / intended held-out count | New right / left / shake / nothing | Legacy right / left / shake / nothing |
| --- | --- | --- |
| Right / 7 | 6 / 0 / 0 / 1 | 0 / 0 / 0 / 7 |
| Left / 7 | 0 / 1 / 0 / 6 | 1 / 2 / 0 / 4 |
| Shake / 5 | 0 / 1 / 1 / 3 | 0 / 2 / 2 / 1 |
| Idle / 0 | 4 / 0 / 0 / 0 (4 extra) | 0 / 1 / 0 / 0 (1 extra) |

| Target | New result |
| --- | --- |
| Right ≥6/7 | 6, meets count target |
| Left ≥6/7 | 1, below target |
| Shake ≥4/5 | 1, below target; also one uncompensated left event |
| Idle false positives ≤1 | 4, above target |
| two-buds-left-right-both segment 2 =0 | 0, passes with the labelled calibration |

Full new output:

```text
labelled-right10-left10-shake5-idle.csv detector=new feature=device sensitivity=medium motion_rows=2759 calibration_per_direction=3
cR=Vector3(x: 0.5501455933091092, y: 0.4838154164810021, z: 0.6806338728992869) cL=Vector3(x: -0.3333902630263194, y: 0.4216541657466035, z: -0.843242964410482) mPeak=8.420486950852819
t=2757801.847 marker=1 right
t=2757804.087 marker=1 right
t=2757806.527 marker=1 right
t=2757808.447 marker=1 right
t=2757811.047 marker=1 right
t=2757816.167 marker=1 right
t=2757839.240 marker=2 left
t=2757847.440 marker=3 left
t=2757861.320 marker=3 left
t=2757861.520 marker=3 shake compensates=2757861.320261
t=2757867.760 marker=4 right
t=2757868.720 marker=4 right
t=2757873.560 marker=4 right
t=2757886.480 marker=4 right
segment label right left shake nothing extra (net of speculative flicks)
0 unlabelled 0 0 0 ? ?
1 right 6 0 0 1 0
2 left 0 1 0 6 0
3 shake 0 1 1 3 0
4 idle 4 0 0 0 4
5 unlabelled 0 0 0 ? ?
idle false positives: 4
flick onset latency median=40.0 ms max=40.0 ms n=13
shake onset latency median=200.0 ms max=200.0 ms n=1
Counts are segment totals, not per-trial matching; nothing/extra require --expected ground-truth counts.
```

Full legacy output:

```text
labelled-right10-left10-shake5-idle.csv detector=legacy feature=device sensitivity=medium motion_rows=2759 calibration_per_direction=3
cR=Vector3(x: 0.5501455933091092, y: 0.4838154164810021, z: 0.6806338728992869) cL=Vector3(x: -0.3333902630263194, y: 0.4216541657466035, z: -0.843242964410482) mPeak=8.420486950852819
t=2757834.040 marker=2 left
t=2757836.320 marker=2 left
t=2757842.400 marker=2 right
t=2757847.760 marker=3 shake
t=2757851.160 marker=3 left
t=2757853.640 marker=3 shake
t=2757859.240 marker=3 left
t=2757870.920 marker=4 left
segment label right left shake nothing extra (net of speculative flicks)
0 unlabelled 0 0 0 ? ?
1 right 0 0 0 7 0
2 left 1 2 0 4 0
3 shake 0 2 2 1 0
4 idle 0 1 0 0 1
5 unlabelled 0 0 0 ? ?
idle false positives: 1
flick onset latency median=880.0 ms max=960.0 ms n=6
shake onset latency median=300.0 ms max=320.0 ms n=2
Counts are segment totals, not per-trial matching; nothing/extra require --expected ground-truth counts.
```

## Feature experiments and tuning

All experiments retain the same three-capture training split, default Medium sensitivity unless stated, and no filename/marker/timestamp rules in the detector.

| Variant | Correct right | Correct left | Shake detections in shake block | Idle events |
| --- | --- | --- | --- | --- |
| Device-frame default | 6 | 1 | 1 | 4 |
| Add gravity: `(rotation cosine + 0.25 × gravity cosine) / 1.25` | 6 | 2 | 1 | 5 |
| Yaw-invariant descriptor: signed vertical + unsigned horizontal rotation, averaged in feature space | 0 | 0 | 1 | 0 |
| Low sensitivity (1.35×) | 5 | 0 | 1 | 2 |
| High sensitivity (0.75×) | 6 | 2 | 1 | 9 |
| 300 ms hold | 6 | 1 | 1 | 4 |

Gravity gains one left event while adding an idle false positive. The yaw-invariant descriptor cannot separate these calibrated directions at the required score margin; losing horizontal orientation removes the useful right/left distinction. Device-frame features remain the default. The hold changes timing (360 ms observed onset-to-delivery due to 40 ms sample quantization), not net accuracy.

I also tested every combination of quiet arming duration 60/120/200/300 ms and shake projection scale 0.40/0.30/0.20/0.15. The full tuning output below includes the `right left shake nothing extra` columns for each segment:

```text
quiet shakeScale | right-segment | left-segment | shake-segment | idle-segment
0.06 0.4 | 1 right 6 0 0 1 0 | 2 left 0 1 0 6 0 | 3 shake 0 1 1 3 0 | 4 idle 4 0 0 0 4
0.06 0.3 | 1 right 6 0 0 1 0 | 2 left 0 1 1 5 0 | 3 shake 0 1 2 2 0 | 4 idle 4 0 0 0 4
0.06 0.2 | 1 right 6 0 0 1 0 | 2 left 0 1 3 3 0 | 3 shake 0 1 3 1 0 | 4 idle 1 0 2 0 3
0.06 0.15 | 1 right 5 0 1 1 0 | 2 left 0 1 5 1 0 | 3 shake 0 0 4 1 0 | 4 idle 1 0 3 0 4
0.12 0.4 | 1 right 6 0 0 1 0 | 2 left 0 1 0 6 0 | 3 shake 0 1 1 3 0 | 4 idle 4 0 0 0 4
0.12 0.3 | 1 right 6 0 0 1 0 | 2 left 0 1 1 5 0 | 3 shake 0 1 2 2 0 | 4 idle 4 0 0 0 4
0.12 0.2 | 1 right 6 0 0 1 0 | 2 left 0 1 3 3 0 | 3 shake 0 1 3 1 0 | 4 idle 1 0 2 0 3
0.12 0.15 | 1 right 5 0 1 1 0 | 2 left 0 1 5 1 0 | 3 shake 0 0 4 1 0 | 4 idle 1 0 3 0 4
0.2 0.4 | 1 right 6 0 0 1 0 | 2 left 0 1 0 6 0 | 3 shake 0 1 1 3 0 | 4 idle 3 0 0 0 3
0.2 0.3 | 1 right 6 0 0 1 0 | 2 left 0 1 1 5 0 | 3 shake 0 1 2 2 0 | 4 idle 3 0 0 0 3
0.2 0.2 | 1 right 6 0 0 1 0 | 2 left 0 1 3 3 0 | 3 shake 0 1 3 1 0 | 4 idle 1 0 2 0 3
0.2 0.15 | 1 right 5 0 1 1 0 | 2 left 0 1 5 1 0 | 3 shake 0 0 4 1 0 | 4 idle 1 0 3 0 4
0.3 0.4 | 1 right 6 0 0 1 0 | 2 left 0 1 0 6 0 | 3 shake 0 1 1 3 0 | 4 idle 3 0 0 0 3
0.3 0.3 | 1 right 6 0 0 1 0 | 2 left 0 1 1 5 0 | 3 shake 0 1 2 2 0 | 4 idle 3 0 0 0 3
0.3 0.2 | 1 right 6 0 0 1 0 | 2 left 0 1 3 3 0 | 3 shake 0 1 3 1 0 | 4 idle 1 0 2 0 3
0.3 0.15 | 1 right 5 0 1 1 0 | 2 left 0 1 5 1 0 | 3 shake 0 0 4 1 0 | 4 idle 1 0 3 0 4
```

These experiments are reproducible with `--quiet-seconds` and `--shake-scale`. Lowering the shake scale to 0.15 reaches four shake-block detections but creates five false shakes in the left block, one in the right block and three in idle. Increasing quiet duration to 200/300 ms reduces idle flicks somewhat but does not solve direction accuracy. None of these changes was adopted as an app default. The only detector refinements beyond the specified rules are 600 ms calibration return suppression, the inherited 200 ms stream-gap guard, expiry of old shake lobes, and prevention of multiple speculative actions in one potential shake. A speculative delivery is associated with a shake only within its 600 ms window, allowing 120 ms between the first qualifying axis lobe and the flick's decision.

Raw-data inspection explains why the requested two-template strategy struggles. Early left peaks are predominantly negative z; later peaks include approximately `(9.5,-6.0,0.6)` and `(9.4,-8.0,0.2)`, with gravity still broadly similar. This is a change of rotation axis, not evidence by itself of a particular grip change. The second left motion has a primary magnitude below 3.5 rad/s (about 2.86), followed by a return near 3.81, so first-three-thresholded-stroke calibration can capture a return as a labelled left example. The final left mean is consequently `(-0.333,0.422,-0.843)`, which poorly represents the later positive-x/negative-y strokes. Idle also contains peaks above 10 rad/s. Lowering magnitude thresholds alone is insufficient. These results do not prove the targets impossible, but the tested settings do not meet them. Additional representative calibration/trial labels or a different classifier are still needed; training on the held-out strokes would invalidate this evaluation.

The supplied idle segment spans approximately **26.48 s**, despite the requested 30 s block, and the shake segment contains six separated high-energy motion clusters despite the label saying five intended shakes. The report uses the supplied intended counts without silently relabelling data. Neither segment labels nor counts establish exact per-trial recall.

## Latency

| Stage | Evidence / estimate |
| --- | --- |
| Motion delivery | Fixed ~25 Hz, ~40 ms sample interval; hardware batching and physical-peak sampling delay unmeasured |
| New flick onset → decision | **40 ms median / 40 ms max** for 13 held-out raw flick deliveries in this file |
| Selected peak sample → new decision | 0–40 ms by the decision rule in this replay; physical peak time may fall between samples |
| New shake first qualifying lobe → decision | **200 / 200 ms**, one recognized shake |
| Legacy flick onset → delivery | **880 / 960 ms**, six held-out flick deliveries |
| Legacy shake onset → delivery | **300 / 320 ms**, two shakes |
| Main-thread handoff + Bridge | No imposed timer delay; one write/reply over a persistent local socket. Budget ≲10 ms under light load, **not measured in Anki** |
| Anki scheduling + webview paint | Not measured; to meet a 120 ms target after a sampled peak, roughly 70 ms remains after a 40 ms detector delay and 10 ms handoff/bridge budget |
| AnkiConnect fallback grade / reveal | Estimated 30–45 / 60–90 ms transport from the brief's per-call observation; plus detector, scheduling and paint |
| Shared debounce | 120 ms rejection window, no added wait for an accepted gesture |
| Optional hold | 300 ms configured after decision; 360 ms total onset→delivery observed |

The bridge reply waits for grade/undo completion hooks but is not a paint acknowledgment. The window's **Last latency** is detector host fire → reply, excluding earlier physical motion and later webview rendering. The under-120-ms physical peak-to-card target is **unverified**, not a benchmark claim. Temporary fake-socket tests verify framing/deadlines/reconnect, not live Qt/render speed.

## Anki source compatibility

Read-only GitHub source inspection covered both Anki **23.10** and **26.09**, plus main for comparison. No installed Anki was inspected or contacted.

- Reviewer `_showAnswer()` and `_answerCard(ease)` exist in [23.10 reviewer.py](https://github.com/ankitects/anki/blob/23.10/qt/aqt/reviewer.py) and [26.09 reviewer.py](https://github.com/ankitects/anki/blob/26.09/qt/aqt/reviewer.py). Answering sets a transition state and schedules an asynchronous collection operation. Completion emits `reviewer_did_answer_card`. The bridge uses that hook, detects a synchronous hook veto, and provides guarded snake-case method alternatives.
- `mw.undo()` delegates to the collection undo operation, and `onUndo` is an alias in [23.10 main.py](https://github.com/ankitects/anki/blob/23.10/qt/aqt/main.py) and [26.09 main.py](https://github.com/ankitects/anki/blob/26.09/qt/aqt/main.py). A tight loop of real `mw.undo()` calls would race the undo stack. The runtime sequences them instead.
- `Collection.undo_status().undo` and `Collection.undo()` are present in [23.10 collection.py](https://github.com/ankitects/anki/blob/23.10/pylib/anki/collection.py) and [26.09 collection.py](https://github.com/ankitects/anki/blob/26.09/pylib/anki/collection.py). A guarded `undoName` fallback supports older naming; absence of both checks prevents a blind undo.
- `state_did_undo` fires on successful asynchronous undo in [23.10 operations/collection.py](https://github.com/ankitects/anki/blob/23.10/qt/aqt/operations/collection.py) and [26.09 operations/collection.py](https://github.com/ankitects/anki/blob/26.09/qt/aqt/operations/collection.py). The next step is deferred to Qt's next event-loop turn so the current hook stack can unwind; no polling loop is used.
- QLocalServer/QLocalSocket are exported by `aqt.qt` in [23.10 qt6.py](https://github.com/ankitects/anki/blob/23.10/qt/aqt/qt/qt6.py) and [26.09 qt6.py](https://github.com/ankitects/anki/blob/26.09/qt/aqt/qt/qt6.py). The enum lookup supports scoped and older Qt enum names.
- `answerButtons(card)` is inherited from SchedulerBaseWithLegacy in [23.10 scheduler/legacy.py](https://github.com/ankitects/anki/blob/23.10/pylib/anki/scheduler/legacy.py) and [26.09 scheduler/legacy.py](https://github.com/ankitects/anki/blob/26.09/pylib/anki/scheduler/legacy.py); the V3 helper currently returns four. The bridge still queries it and supports a guarded `answer_buttons` alternative.
- [AnkiConnect's legacy guiAnswerCard](https://github.com/FooSoft/anki-connect/blob/master/plugin/__init__.py) checks reviewer state and scheduler `answerButtons(card)`. Its implementation rejects an out-of-range ease; the brief explicitly asks the bridge to **clamp** to that range, which the bridge does. It never assumes four buttons are available when the scheduler API is missing.

These are source-level compatibility checks, not runtime certification of every intervening release or third-party add-on interaction.

## Verification

- `scripts/test.sh`: **107 tests, 0 failures**. XCTest is unavailable on this CLT installation, so the script uses the same bodies in AirAnkiCoreSelfTest. Every test body is registered.
- New Swift tests cover 25/50 Hz classification/latency, return suppression, speculative/held shakes, longer second-stroke gaps, cooldown, expired lobes, invalid/uncalibrated streams, stream gaps/reset, reversal, template validation, peak capture, held-out recording metrics and silent right-bud segment 2. Existing legacy detector tests remain.
- Controller/transport tests verify Bridge's no-read action path, state from replies, unavailable-only fallback, uncertain-result no-retry, correct one/two undo counts, compensation waiting for an in-flight grade, busy blocking, legacy fast actions even when V1 exists, and timeout reconciliation without a second mutation. Temporary Unix servers test persistent IDs, split frames, wrong IDs, 300 ms timeout, absent sockets, backoff and successful reconnect. No test uses a live Anki endpoint.
- `python3 -m unittest discover anki-addon/tests`: **10 tests, passed**, with synchronous and asynchronous fake reviewers/collections. Includes inactive review, count limits/empty history, clamping, version aliases, exceptions/veto, ordered undo, timeout/no continuation, and committed-grade acknowledgment.
- `scripts/build_app.sh`: **passed without warnings**, including plist lint and ad-hoc signing/strict signature verification. No interactive app launch.
- Final new/legacy replays, gravity/invariant variants, Low/High, 300 ms hold, all 16 tuning combinations and `--trace` ran successfully.
- `bash -n scripts/install_addon.sh`, `git diff --check`, test-runner registration audit and unchanged `research/data/` diff passed. Installer was syntax-checked only, never executed.

## Remaining limitations and unverified work

1. **Accuracy:** left/shake/idle targets are not met. The regression deliberately asserts measured results (right=6, left=1, shake=1, idle≤4), not the requested unattained thresholds. This version is not signed off for unattended real-deck use.
2. **Live integration:** real Qt socket lifecycle, Anki scheduling/undo/rendering, API behavior with other add-ons, permissions, AirPods reconnection, sound/audio coexistence and window layout require the manual test sheet. Neither Anki nor AirAnki was launched. No installation occurred.
3. **Undo boundary:** the requested outside-review guard applies to undo too. If the speculative grade finishes the deck, the following remote undo is a no-op; use Anki's Undo. Thus exact compensation is limited to an active reviewer. Concurrent keyboard/other-add-on edits can also change the global undo history. The slower legacy fallback does not offer Bridge's per-undo completion acknowledgment.
4. **Uncertain operation:** a timed-out bridge action is never retried. If Anki never emits its completion hook (for example, an asynchronous backend failure), the bridge remains busy until profile reopen/restart; this is safer than accepting further uncertain mutations. Runtime failure/recovery still needs manual testing.
5. **Latency:** only offline recognition latency is measured. Physical peak → visible card under 120 ms remains unverified. A fast acknowledgment is not proof of a painted card.

All work and commits are local to `codex/v1-app`. No push, remote, fetch or pull was run; no hosted deployment/service was created, no .env/account/posting/global install was used, and no Anki2 directory, Bluetooth/TCC settings or other application process was touched. The only external reads were the explicitly requested public source checks. This report is included in the implementation commit; the final working-tree check follows that commit.
