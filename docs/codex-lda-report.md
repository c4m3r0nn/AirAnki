# Summed-vector classifier report

2026-11-01 · local branch `codex/v1-app`

Implemented the linear discriminant, projection shake detector, six-per-direction calibration, replay sweep and regressions. **Accuracy targets are not all met.** Best N=3 result: 5 right, 2 left, 3 shakes, zero idle false positives and zero wrong-direction flicks. Tuning stopped after the specified grid; no per-file rules were added.

## Chosen constants and behavior

| Parameter | Default |
| --- | --- |
| Quiet magnitude / duration | below 3.0 rad/s / 0.15 s |
| Onset | above 3.5 rad/s |
| Feature / decision | summed vector over 80 ms; third sample at 25 Hz |
| Linear decision | `a=normalize(mR−mL)`, `p=a·s−mid`; right/left beyond `±0.35×half` |
| Peak gate | `max(5.0, 0.65×weakest accepted calibration peak)` rad/s |
| Refractory / optional hold | 220 ms / 300 ms |
| Shake | 3 sign changes: **4** alternating qualifying lobes, each ≥2.0 rad/s, within 800 ms |
| Shake cooldown / stream-gap reset | 600 ms / gaps above 200 ms |
| Live calibration | 6 accepted right + 6 accepted left; peak below 5 does not count; require `half ≥5` |

Integration uses trapezoids over the first 80 ms plus 20 ms endpoint cells, divided by 40 ms. This equals `ω0+ω1+ω2` at 25 Hz and preserves that feature for the same linearly interpolated motion at 50 Hz, without waiting past 80 ms. Quiet duration is measured from the last non-quiet sample, as in the prototype; startup/reset requires observed quiet.

Low/Medium/High retain 1.35/1/0.75 scaling of the linear margin, peak gate and shake threshold, with an absolute 5 rad/s peak floor. Calibration displays `half`; weak captures say “A bit sharper,” and indistinct directions request a redo. Saved V3 calibration replaces the incompatible V2 template format on recalibration. The existing UI, bridge, BridgeClient, review/compensation controller and LegacyFlickDetector remain; bridge/controller/legacy source files are unchanged.

The shake guard now suppresses only an additional speculative action: curvature within the first stroke cannot suppress that stroke merely because its projection changes sign. Shake compensation retains the exact speculative timestamp, including a held flick already delivered. Three lobes alone do not satisfy the brief's explicit three-sign-change rule.

## Sweep

Grid: quiet `{.15,.20,.25,.30}`, onset `{3.5,4,4.5}`, peakMin `{5,5.5,6}`, shakeLobe `{2,2.5,3,3.5,4}`, window `{.5,.6,.7,.8,.9}`: **900 combinations**. Objective: correct right + correct left + correct shakes − 2×idle events − 2×wrong-direction flicks. Scores use net gestures after compensation. Ties retain grid order. N=3 has 900 valid configurations; N=5 has 600 (others cannot form valid calibration).

| N / rank | Quiet s | Onset | PeakMin | ShakeLobe | Window s | Right / left / shakes | Idle / wrong | Score |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 3 / **1 chosen** | .15 | 3.5 | 5 | 2 | .80 | 5 / 2 / 3 | 0 / 0 | 10 |
| 3 / 2 | .15 | 3.5 | 5 | 2 | .90 | 5 / 2 / 3 | 0 / 0 | 10 |
| 3 / 3 | .20 | 3.5 | 5 | 2 | .80 | 5 / 2 / 3 | 0 / 0 | 10 |
| 3 / 4 | .20 | 3.5 | 5 | 2 | .90 | 5 / 2 / 3 | 0 / 0 | 10 |
| 3 / 5 | .25 | 3.5 | 5 | 2 | .80 | 5 / 2 / 3 | 0 / 0 | 10 |
| 5 / **1 chosen** | .15 | 3.5 | 5 | 2 | .80 | 3 / 0 / 2 | 0 / 0 | 5 |
| 5 / 2 | .15 | 3.5 | 5 | 2 | .90 | 3 / 0 / 2 | 0 / 0 | 5 |
| 5 / 3 | .15 | 4 | 5 | 2 | .80 | 3 / 0 / 2 | 0 / 0 | 5 |
| 5 / 4 | .15 | 4 | 5 | 2 | .90 | 3 / 0 / 2 | 0 / 0 | 5 |
| 5 / 5 | .15 | 4 | 5 | 2.5 | .80 | 3 / 0 / 2 | 0 / 0 | 5 |

The supplied Python command was run unchanged: it finds 8 right and 6 left strokes, classifying 8 right and 4 left **including training**. After its first three candidates, that is 5 right and 2 left classifications. A regression independently reproduces its raw three-sample features and these counts at its original 4/.30 settings. Production additionally rejects weak calibration captures as required, so its split differs from that prototype.

## Replay tables

`--calibrate-from-labels N` uses the first N **accepted** strokes per direction, skipping peaks below 5; the full training prefix, including rejected attempts, is excluded from evaluation. No later features enter calibration. At the chosen settings the right/left segmenter finds **8/9** strokes. Two weak left attempts occur in the training prefix for both N values. N=3 leaves **5 right / 4 left** strokes; N=5 leaves **3 right / 2 left**. N=3 axis is `(-.1270,.3219,.9382)`, mid `-1.2786`, half `11.6896`; N=5 axis is `(-.2173,.3554,.9091)`, mid `-.7118`, half `11.5731`. Both calibrated peak gates are 5.

All counts below are net right / left / shake, not individually matched trial recall. The other two files use the labelled calibration unchanged, without training on their samples.

| File / segment | Segmented strokes (before training exclusion) | N=3 net R / L / S | N=5 net R / L / S |
| --- | --- | --- | --- |
| labelled-right10-left10-shake5-idle / 0 unlabelled | 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| labelled / 1 right | 8 | 5 / 0 / 0 | 3 / 0 / 0 |
| labelled / 2 left | 9 | 0 / 2 / 0 | 0 / 0 / 0 |
| labelled / 3 shake | 6 | 0 / 3 / 3 | 0 / 3 / 2 |
| labelled / 4 idle | 8 | 0 / 0 / 0 | 0 / 0 / 0 |
| labelled / 5 unlabelled | 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| two-buds-left-right-both / 0 | 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| two-buds / 1 | 4 | 0 / 4 / 0 | 0 / 4 / 0 |
| two-buds / **2** | **0** | **0 / 0 / 0** | **0 / 0 / 0** |
| two-buds / 3 | 3 | 2 / 0 / 0 | 0 / 0 / 0 |
| two-buds / 4 | 1 | 0 / 1 / 0 | 0 / 1 / 0 |
| handheld-free-flicks / 0 (whole file) | 15 | 2 / 4 / 1 | 2 / 4 / 1 |

Labelled raw N=3 deliveries: 5 R / 6 L / 3 S, with one left compensated. N=5: 3 R / 4 L / 2 S, with one left compensated. Free-flick raw deliveries for both calibrations: 3 R / 4 L / 1 S, with one right compensated. Two-bud raw and net counts agree. The three uncompensated left events in the shake block are visible failures; the specified score does not penalize them as wrong-direction flicks. Wrong-direction means left in the right block or right in the left block.

N=3 therefore misses the requested right ≥6/7 and left ≥3/5 targets. Its actual segmented fractions are 5/5 right and 2/4 left. Three shake detections reach the requested numerator, but **3/4 recall is not established**: the file labels say five intended shakes and the segmenter finds six starts. Idle=0 and wrong-direction=0 pass. N=5's remaining left strokes are weak or ambiguous. No thresholds were tuned beyond the reported grid.

Labelled flick onset-to-delivery latency is **80 ms median/max** for both N values. Shake first-qualifying-lobe-to-delivery median/max: N=3 **320/720 ms**, N=5 **500/720 ms**. These are offline recognition timings.

Reproduce after building (replace `3` with `5` for the second calibration):

```sh
AirAnki/.build/release/AirAnkiReplay research/data/labelled-right10-left10-shake5-idle.csv \
  --labels right,left,shake,idle --calibrate-from-labels 3 --expected 10,10,5,0 \
  --sweep --save-calibration build/lda-n3.json
AirAnki/.build/release/AirAnkiReplay research/data/two-buds-left-right-both.csv --load-calibration build/lda-n3.json
AirAnki/.build/release/AirAnkiReplay research/data/handheld-free-flicks.csv --load-calibration build/lda-n3.json
```

## Verification and unverified items

- `scripts/test.sh`: **112 tests, 0 failures**. CLT lacks XCTest; the script ran the same test bodies via AirAnkiCoreSelfTest. All 112 bodies are registered exactly once.
- Synthetic coverage: curved left, straight right, 25/50 Hz feature/latency equivalence, weak idle, three-lobe rejection/four-lobe recognition, weak lobes, expired windows, quiet arming, reversal, stream gaps, speculative and held compensation, six accepted captures, weak rejection and quality-triggered redo.
- Recording regressions assert N=3/N=5 results, all three files, training exclusion, zero wrong/idle events, silent two-bud segment 2, and parity with the supplied prototype's features/counts. Existing legacy/controller/bridge tests pass unchanged.
- `python3 -m unittest discover anki-addon/tests`: **10 tests, passed**.
- `scripts/build_app.sh`: **passed with no warnings**; plist lint, ad-hoc signing and strict signature verification passed. The app was not launched.
- `git diff --check` passed. `research/data/`, bridge/add-on, BridgeClient, review controller and legacy detector are unchanged. README and the manual test sheet describe the new classifier/calibration and replay options.
- Unverified: live calibration layout/audio, physical 50 Hz hardware behavior, grip generalization, Anki undo/render behavior and physical peak-to-card latency. Parameter selection used this recording, so held-out calibration strokes are not an independent test set for hyperparameter selection. Counts alone do not establish trial recall.
- All work is local. No push/remote/fetch/pull, hosted services, accounts, `.env`, global installs, sudo/brew, installer, app launch, Anki/Anki2 access, Bluetooth/TCC changes or unrelated process manipulation occurred. This report is committed with the implementation on `codex/v1-app`.
