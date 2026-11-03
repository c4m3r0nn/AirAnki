# AirAnki — developer notes

Hold one AirPod and flick your wrist to review Anki cards on your Mac. **Right reveals, then grades Easy; left reveals, then grades Again; your calibrated twist/shake undoes.** AirAnki runs in a status window and the menu bar.

This version uses three calibrated templates (right, left, undo), gradual adaptation and a local Anki bridge. Ambiguous strokes reveal covered cards and request another attempt on the answer side. Both supplied recordings fail the new live calibration similarity check; offline diagnostics also miss several accuracy targets. See [CODEX_REPORT.md](CODEX_REPORT.md) for measured results and limitations.

## Setup

You need macOS 14+, compatible AirPods, Anki Desktop (source APIs checked at 23.10 and 26.09), and Apple's Command Line Tools to build. No extra build dependencies are needed.

1. Build from the repository root:

   ```sh
   ./scripts/build_app.sh
   ```

2. For the fastest connection, **run the installer yourself**, then restart Anki:

   ```sh
   ./scripts/install_addon.sh
   ```

   This symlinks `anki-addon/airanki_bridge` into Anki's `addons21/airanki_bridge` directory. It refuses to replace a non-symlink. Keep this repository at its current location while using the link. The development task does not run this installer or modify Anki's files.

3. Open a disposable practice deck in Anki. Open `build/AirAnki.app` yourself. The window should say **Anki link: Bridge (instant)**. AnkiConnect is optional when Bridge works. Without Bridge, install/update AnkiConnect using add-on code **2055492159** and restart Anki; the window reports **AnkiConnect (slower)**. [Official listing](https://ankiweb.net/shared/info/2055492159).
4. Connect AirPods and turn **Automatic Ear Detection OFF** in System Settings → AirPods. Hold the **left bud**, with the other in its case. Allow Motion & Fitness access if prompted. Check **Motion: receiving ●**.
5. Calibration starts automatically without a valid V4 calibration. Follow **Flick RIGHT 6×**, **Flick LEFT 6×**, then **Do your UNDO gesture 6× (a quick twist/shake)**. Flick the way you would while studying, not extra hard. Return gently to rest and leave about one second between captures. Calibration never sends Anki actions.

Use **Calibrate flicks** in the window or **Recalibrate** in the menu whenever the grip changes substantially. Captures below 3.5 rad/s prompt “A little sharper” without advancing; accepted captures suppress return swings for 600 ms. If two templates have cosine similarity above 0.5, the current step is repeated with the conflicting classes named. Unit templates, median peaks and adapted directions are saved locally as `flickCalibrationV4`; older calibrations require the three-step flow. **Reset to calibration** restores the original directions without repeating capture.

Denied/restricted motion permission displays the Motion & Fitness settings path. AirAnki never changes Bluetooth, ear detection or permissions for you. Accessibility permission is unnecessary. The motion rate is approximately 25 Hz in the supplied recordings; AirAnki does not attempt to increase it.

## Gestures and settings

| Gesture | Question side | Answer side |
| --- | --- | --- |
| Right flick | Show answer only | Easy (4), or Good (3) if selected |
| Left flick | Show answer only | Again (1) |
| Calibrated undo twist/shake | One Undo | One Undo |
| Ambiguous stroke | Show answer only | No action; Funk sound and “unclear flick — try again” |

All three classes decide about 80 ms after onset using the time-integrated three-sample sum. Arming requires 150 ms of quiet below 3 rad/s and onset above 3.5 rad/s. A confident classification requires cosine ≥0.70, a lead over the runner-up ≥0.20, and peak ≥`max(3.5, 0.55 × smallest class median peak)`. Stronger ambiguous strokes still emit an event; weaker strokes are ignored. The next onset must be at least 220 ms after any emitted stroke; the same class must have at least 300 ms between deliveries. Undo requires an active reviewer; use Anki's Undo at the finished-deck screen.

Confident strokes with cosine ≥0.80 move their template 15% toward the new unit feature. Adaptation persists at most every 30 seconds; the original calibration stays available for reset. Large abrupt grip changes may need recalibration.

- **Sensitivity → Low / Medium / High** multiplies the peak gate by 1.3 / 1 / 0.8, with an absolute 3 rad/s floor. Cosine and margin stay fixed.
- **Reverse left/right** exchanges only the recognized left/right actions.
- **Right flick grades → Easy / Good** selects the grade; Bridge clamps it to available scheduler buttons.
- **Click sound** controls preloaded Tink feedback. The distinct unclear-stroke and motion-loss sounds work independently of this setting.
- **Keep AirPods awake** defaults on in both menu and window. While remote, Lab or calibration is active, an AVAudioEngine loops very low noise (about −75 dBFS RMS) through the default output and restarts on configuration changes. It registers no media commands or Now Playing metadata. Its audibility, device wake behavior and music coexistence need hardware verification.
- **Use stem presses (experimental)** is off by default. Turning it on additionally claims media controls; keep-awake audio is independent.

After two seconds without samples the window reports **AirPods motion lost — check connection**, with one Funk sound per outage while remote is active. Samples clear the warning when they resume.

**Pause remote** blocks new actions. Lab recording can continue while paused; calibration can also continue. Resume clears unfinished gestures. An accepted Anki operation may still finish. **Hide window** leaves AirAnki running; reopen it or choose **Show AirAnki window** to bring it back.

## Connection and latency

Bridge uses a persistent Unix socket at `~/Library/Application Support/AirAnki/bridge.sock`. The directory is owner-only (0700); Qt restricts the socket to the current user. Newline JSON requests wake Qt directly, without a polling timer. Bridge acknowledges committed grading/undo through Anki's completion hooks and returns the reviewer side with the result. A side of `none` can briefly mean the next card is still loading.

**Last latency: N ms** measures the live detector's fire time to the action's reply, including main-thread handoff and transport. It does **not** measure the physical motion before detection or the time until Anki's webview paints the next card. The under-120-ms peak-to-card target needs live measurement; it has not been established by offline replay. Lab writes the same duration as `action_latency` / `fire_to_reply`.

If the socket cannot be connected, AirAnki falls back to loopback AnkiConnect. Motion uses `guiAnswerCard`, followed by `guiShowAnswer` only on a definite false: one call for grading, two for revealing. Ambiguous strokes send Bridge `reveal`, which never grades. Fallback reveal uses V1 side checks when available or legacy `guiShowAnswer` without a grade request. Legacy cannot reliably distinguish an already-visible answer when that call returns true, so unclear feedback requires Bridge/V1. V1 remains preferred for state display when available. The exceptional V1 action path polls operation completion every 15 ms. Background status refreshes every two seconds while the window is open.

Set **AnkiConnect port** in the window to match AnkiConnect's `webBindPort` (default 8765); keep `webBindAddress` on `127.0.0.1`. The app accepts ports 1–65535. Existing `ankiConnectAPIKey` in the app's `com.camerondent.AirAnki` UserDefaults domain is supported. **Test connection** re-detects the link/API. Do not stop unrelated applications to resolve port clashes.

Motion and stems share a **120 ms sliding debounce** and an action lock. Ordinary gestures during a request are discarded, never queued. Socket requests have a 300 ms deadline and reconnect backoff (100 ms to 2 s). A request that may have been sent is never automatically repeated through either transport. After an uncertain result, inspect Anki before trying again. Undo uses Anki's global history.

## Lab and offline replay

Use **Lab mode (record data)** or launch one of these modes yourself:

```sh
build/AirAnki.app/Contents/MacOS/AirAnki --lab       # record while reviewing
build/AirAnki.app/Contents/MacOS/AirAnki --lab-only  # no Anki calls
```

Logs stay at `~/Library/Logs/AirAnki/lab-YYYYMMDD-HHMMSS.csv`. The detector runs on a dedicated serial motion queue. CSV formatting, buffering and disk writes run on another queue; UI updates are limited to 10 Hz. Logs flush every second, at markers and on normal quit. `detail` includes `sR`, `sL`, peak magnitude and onset-to-decision latency. A recognized gesture is not proof that Anki acted: check **Last gesture**.

After calibration, press Return or choose **Insert marker** before each block: **10 right flicks**, **10 left flicks**, **5 shakes**, **30 seconds of normal hand movement/typing**, then an end marker and two seconds still. Keep intended gestures two seconds apart. See [Test F in docs/TESTING.md](docs/TESTING.md#test-f--speed--accuracy).

```sh
./scripts/test.sh
python3 -m unittest discover anki-addon/tests
./scripts/build_app.sh
AirAnki/.build/release/AirAnkiReplay research/data/natural-left15-right15-shake5-idle.csv \
  --detector centroid --labels left,right,undo,idle --label-start 1 --calibrate-from-labels 4
AirAnki/.build/release/AirAnkiReplay research/data/labelled-right10-left10-shake5-idle.csv \
  --detector centroid --labels right,left,undo,idle --label-start 1 --calibrate-from-labels 4
# Add --sweep to print the top five and evaluate that recording's winner.
# --detector lda and --detector legacy retain the historical comparison paths.
```

Centroid is the default. Training uses the first N accepted captures per class (peak ≥3.5, with 600 ms return suppression) and excludes the whole training prefix. Training strokes never enter adaptation. Held-out strokes adapt in chronological order. Tables show right / left / undo / ambiguous / ignored per segment; they count segmented strokes, not matched intended trials. Failed template similarity checks are prominently reported; replay can still diagnose them but cannot export them for live use. Valid calibrations support `--save-calibration` / `--load-calibration`.

`--sweep` evaluates 600 settings: gate multiplier 0.45–0.70 by 0.05, cosine 0.60–0.80 by 0.05, margin 0.10–0.30 by 0.05, adaptation 0 / 0.10 / 0.15 / 0.25. Score is correct −3×wrong confident classes −3×idle confident −idle ambiguous. Ties prefer proximity to the brief defaults, then grid order. The production constants were selected on the new file; the old file's independent sweep does not change production settings. LDA alone retains `--hold` and the old threshold sweep. `--expected` is a historical comparison option, unavailable for centroid.

Tests use synthetic streams, supplied CSVs, mock Anki clients and temporary local fake sockets. They never contact Anki. On a Command Line Tools installation without XCTest, `scripts/test.sh` runs the same bodies with `AirAnkiCoreSelfTest`. Build caches and binaries stay in the repository; the app is locally ad-hoc signed.

## Hardware limits and experimental stems

`CMHeadphoneMotionManager` exposes one motion stream, not independently selectable left/right streams. In the user's two-bud test the right bud never reported; moving only that bud produced no detections. **Dual-AirPod control is not implemented.** This does not establish that every AirPods model always chooses the left bud.

Optional stems start silent audio and media-command capture and can compete with music or calls. Saved stem mappings remain separate: Single reveals/grades, Double retains the older show-then-Again flow, Triple undoes. `easeForSingle` is retained separately from right-flick grading. Explicit play/pause callbacks are ignored by default because ear detection can generate them; test **Treat play/pause as press…** in Lab-only mode before enabling it for review.

Hardware accuracy, live latency, audio coexistence, window layout and real Anki integration remain manual checks. [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) retains attribution for the legacy detector and research; [research/FINDINGS.md](research/FINDINGS.md) contains the historical findings.
