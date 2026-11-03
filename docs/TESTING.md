# AirAnki human test sheet

These are manual checks for a disposable practice deck. Development checks build and run offline fixtures only; they do not launch AirAnki, install the add-on, contact Anki, or change Bluetooth or permissions.

## Setup and calibration

1. Build with `scripts/build_app.sh`. Install the bridge yourself if needed and restart Anki. Open a practice deck and launch AirAnki yourself.
2. Turn Automatic Ear Detection off. Hold one AirPod, preferably the left, with the other in its case. Leave experimental stem input off.
3. Start at Medium sensitivity, reversal off, Easy selected and Keep AirPods awake on. Record macOS/AirPods/Anki versions, held bud and output device.
4. With no saved V4 calibration, confirm calibration starts on launch. Capture six RIGHT, six LEFT and six UNDO twists at natural studying strength, about one second apart. No Anki actions should occur during capture.
5. Confirm weak attempts say “A little sharper” without advancing. Return swings within 600 ms must not advance. Deliberately similar left/undo gestures should name those classes and repeat undo while retaining right/left.
6. Complete a distinct calibration. Relaunch to verify persistence. Use Reset to calibration after adaptation; original templates should be restored. Recalibrate after a large grip change.

## A. Labelled recording

Run `build/AirAnki.app/Contents/MacOS/AirAnki --lab-only` yourself. Confirm “Lab only — no Anki calls”. Press Return or Insert marker before each block, with gestures at least two seconds apart.

| Marker | Block | Intended count | Right / left / undo / ambiguous / misses |
| --- | --- | --- | --- |
| 1 | Natural left flicks | 15 | |
| 2 | Natural right flicks | 15 | |
| 3 | Calibrated undo twist/shake | 5 | |
| 4 | Normal handling / typing | 20 s | |
| 5 | End; remain still | 2 s | |

Note grip changes, motion gaps and exact times of intended gestures if trial recall is needed. Marker blocks alone cannot establish matched trial recall. Repeat separately for Low/High and reversal; undo should remain unchanged by reversal.

## B. Offline replay and regressions

```sh
scripts/test.sh
python3 -m unittest discover anki-addon/tests
scripts/build_app.sh
AirAnki/.build/release/AirAnkiReplay research/data/natural-left15-right15-shake5-idle.csv \
  --detector centroid --labels left,right,undo,idle --label-start 1 --calibrate-from-labels 4
AirAnki/.build/release/AirAnkiReplay research/data/labelled-right10-left10-shake5-idle.csv \
  --detector centroid --labels right,left,undo,idle --label-start 1 --calibrate-from-labels 4
```

Add `--trace` for best/runner-up cosines and latency, or `--sweep` for the top five of the 600-setting grid. First N accepted strokes per class train the templates; the full prefix, including weak or return attempts, is excluded from evaluation and adaptation. The remaining stream adapts in timestamp order. Ignored includes weak and refractory candidates; it does not mean a manually annotated missed trial.

Both supplied recordings fail the live pairwise similarity gate. Replay explicitly allows diagnostic evaluation of such recordings, but refuses to export the invalid calibration; live calibration/loading still rejects it. CODEX_REPORT records the actual confusion tables and unmet targets. No per-file threshold overrides are used in the app.

`--detector lda` and `--detector legacy` retain historical comparisons and their existing regressions. LDA supports `--hold` and its original threshold sweep. These detectors never run in the live input path. Label `undo` is treated as `shake` in historical comparisons. Valid centroid JSON supports `--save-calibration` and `--load-calibration`.

## C. Live Anki mapping

Test with Bridge, then available AnkiConnect fallbacks. Establish each starting state manually and wait for each result. Verify actual grades/history, not just card advancement.

| Starting state / gesture | Expected behavior | Result |
| --- | --- | --- |
| Question / right, left or ambiguous | Reveal only | |
| Answer / right with Easy selected | Easy (4) | |
| Answer / right with Good selected | Good (3) | |
| Answer / left | Again (1) | |
| Answer / ambiguous | No mutation; Funk; Last gesture “unclear flick — try again” | |
| Either side / undo twist | Exactly one Undo, no speculative grade | |
| Gesture / return swing | One event | |
| Outside review / any gesture | No mutation | |
| Finished-deck screen / undo | Use Anki's own Undo | |
| Gesture during a busy request | Discarded, no queue or compensation | |
| Timeout / uncertain reply | Error; no duplicate write or transport retry | |
| Bridge unavailable before sending | AnkiConnect fallback | |
| Pause / gesture / resume | No paused or delayed action | |
| Anki restart / Test connection | Link restored, no old gestures | |

Bridge `reveal` checks the current side on Anki's thread. V1 fallback also knows the side. Legacy fallback only calls `guiShowAnswer`, never grades; its API can return true on an already-visible answer, so exact unclear feedback is not guaranteed without Bridge/V1. Undo uses Anki's global history and requires an active reviewer.

## D. Keep-awake audio, watchdog and lifecycle

| Test | Expected behavior | Result |
| --- | --- | --- |
| Normal launch, stems off | Motion and keep-awake audio active; no media-command/Now Playing claim | |
| Keep awake off/on in either UI | Both controls agree; setting persists | |
| Remote paused, Lab/calibration inactive | Motion and keep-awake audio stop | |
| Remote paused, Lab or calibration active | Capture and enabled keep-awake continue | |
| Default output route change / reconnect | Audio engine restarts on the new default route | |
| Hold bud without touching proximity sensor for several minutes | Record whether connection stays awake and whether noise is audible | |
| No motion from launch or after connection loss | After 2 s, “AirPods motion lost — check connection”; one Funk while remote active | |
| Continued outage / stream resumes / second outage | No repeated sound during first outage; warning clears; second outage alerts once | |
| Music, calls and Anki card audio | Record interruptions, audibility, controls and motion continuity | |
| Motion permission denied | Settings path displayed before loss; no permission change by app | |
| Show/hide/reopen/resize window | Calibration, warning, reset and keep-awake controls fit | |
| Invalid/busy port edit | Error, existing port retained | |
| Quit | Audio/motion stop; Lab flushes | |

The signal is approximately −75 dBFS RMS through the default output; effectiveness and perceptual inaudibility need hardware testing. The app does not force output to AirPods. Experimental stems separately claim media commands/Now Playing and retain their original single/double/triple mappings; test those separately if enabled.

## Test F — speed & accuracy

Record new held-out targets: left ≥8/11, right ≥8/11, ≤1 wrong per direction; undo ≥1 and zero left/right; idle zero confident and ≤1 ambiguous. The supplied recordings do not meet all these targets. Segmenter counts include possible return/handling strokes, so annotate trials for stronger recall claims.

All classes decide at about 80 ms from onset at 25/50 Hz. Measure fire→reply from Last latency; measure physical peak→visible card separately with video. Hardware timing, UI layout, real Anki history, audio coexistence and long-term drift are unverified by offline tests.

## Reading the CSV

Existing motion columns and marker format are unchanged. New event names are `flick_right`, `flick_left`, `undo`, `ambiguous`, `flick_rejected`. For centroid traces, legacy columns `sR` and `sL` contain the best and runner-up cosine, respectively; reason names the winning class. Peaks are rad/s, latency is onset→decision. Historical LDA uses centered projection / negative projection in those columns, and legacy retains yaw/angle traces.

`action_latency` records fire→reply, not webview paint. Lab-only, pause, busy state, debounce and reviewer state can prevent an action after a detector event. Logs remain local, flush every second and at markers/quit, and can lose the final second on a forced termination.
