# AirPods as an Anki remote — research findings

Research date and source access date: **2026-10-30**. No application was built or installed; no AirPods behavior was tested locally. **Inference** means a conclusion/design proposal, not an observed hardware result. **Untested** identifies a remaining empirical question. Source IDs resolve to the visited URLs and dated records in Sources.

## Executive summary

1. **Recommendation — inference:** build a free macOS helper around an **earbud's media commands**, with AnkiConnect as the reviewer bridge. [S31] [S33]
2. **Case only: feasible-but-hacky for lid experiments; not established as a usable Anki remote.** No documented case-button-to-review input was found. [S06] [S07] [S28] [S29]
3. Older proximity implementations depend on earbuds broadcasting case status; an **empty case is not a supported assumption**, especially across case generations. [S27] [S29]
4. Stem/crown single, double and triple presses normally supply three media meanings: play/pause, next, previous. This is not six independent left/right buttons. [S01] [S02] [S31]
5. **Proposed mapping:** single = Show/Good according to card side; double = Again; triple = Undo. Hard/Easy require an additional mode or motion gestures. [S33] (inference)
6. Held-earbud operation is plausible, but ear detection and audio routing matter; squeeze reliability in the user's hand remains **untested**. [S03] [S08] [P01]
7. Public headphone-motion data can support custom nod/shake/tilt detection on iOS 14+ and macOS 14+ with compatible hardware. Apple's Siri head gestures are a separate feature. [S08] [S09] [S15]
8. No verified ready-made AirPods-to-Anki grading add-on emerged from this sweep; the live AnkiWeb AirPods hit inspected fixes audio instead. **Search finding, not proof of nonexistence.** [S39] [P30]
9. AnkiMobile exposes keyboard/gamepad actions but no documented remote grading URL; an independent iOS helper has no established bridge into its reviewer. [S17] [S18] [S20] (inference)
10. AnkiDroid supports configurable key bindings; whether actual AirPods media commands reach them still needs a device test. [S23] [S24] (untested)

## Prior art table

The table and [prior_art.csv](prior_art.csv) contain the same **35 items**. Relevance scores (1–5) and maintenance judgments are **inferences**. Repository dates are GitHub `pushed_at`, not release dates or promises of support. Stars are snapshots, not download counts. Unknown values were not invented. GitHub metadata is retained in [repository_metadata.json](repository_metadata.json); each row cites its original endpoint. Hardware is represented as `app` in the CSV because the requested type vocabulary has no hardware category.

| Item / evidence | Platform | Last update observed | Popularity | Mechanism | Maintenance assessment | Relevance / limits |
| --- | --- | --- | --- | --- | --- | --- |
| Harelzx/airclicker [P01] [M01] | macOS 14+ | 2026-10-29 (repository push) | 0 GitHub stars | Held-AirPod wrist flicks become arrow keys using headphone motion and CGEvent. Author reports 159 tuning trials. | Inference: Recent push; long-term maintenance unknown | 5/5; MIT; author-held-bud demonstration, not verified here. |
| tony1010-dev/PodMouse [P02] [M02] | macOS 14+ | 2026-10-29 (repository push) | 0 GitHub stars | Core Motion moves a pointer; MPRemoteCommandCenter maps stem 1/2/3 presses to clicks/dictation. | Inference: Recent push; long-term maintenance unknown | 5/5; MIT; author tested AirPods 4 variants. Strongest stem implementation lead; not tested here. |
| nhurden/MediaKeyTap [P03] [M03] | macOS | 2024-01-05 (repository push) | 74 GitHub stars | Swift event tap handles system media keys and tracks media-app priority. | Inference: Archived | 4/5; MIT; system-key capture does not establish Bluetooth command delivery. |
| tombonez/noTunes [P04] [M04] | macOS | 2024-08-08 (repository push) | 6167 GitHub stars | Prevents Music/iTunes launching; does not map inputs to Anki. | Inference: No push since 2024; uncertain | 3/5; MIT; optional workaround only. |
| roxgib/anki-contanki [P05] [M05] | Anki desktop | 2024-06-26 (repository push) | 72 GitHub stars | Anki add-on maps gamepad/controller inputs to reviewer actions. | Inference: No push since 2024; uncertain | 4/5; AGPL-3.0; gamepad input is not proof of AirPods compatibility. |
| TheDabblingDuck/ankimote [P06] [M06] | Anki desktop + phone browser | 2023-05-12 (repository push) | 28 GitHub stars | Phone browser controls Anki over local network via add-on. | Inference: No push since 2023; uncertain | 3/5; MIT; useful reviewer-bridge design, no headphone listener. |
| CoderBomber68/Anki-Remote-Driver [P07] [M07] | Anki desktop / macOS guidance | 2026-02-09 (repository push) | 0 GitHub stars | Gesture-remote driver accepts HID/keyboard/UDP input; center flips and directions select grades. | Inference: Push in 2026; uncertain | 4/5; MIT; touch/page-turner adaptation, no AirPods claim. |
| adolfintel/OpenPods [P08] [M08] | Android | 2025-09-26 (repository push) | 1263 GitHub stars | BLE battery/status monitor for AirPods. | Inference: Last push 2025; uncertain | 4/5; GPL-3.0; useful advertising precedent, no grading controller. |
| SpriteOvO/AirPodsDesktop [P09] [M09] | Windows; Linux WIP | 2026-10-27 (repository push) | 3829 GitHub stars | AirPods status integration with reverse-engineered proximity packet parser. | Inference: Recent push; active inference | 5/5; GPL-3.0; lid state/counter fields are research evidence, not a case-button API. |
| steam3d/MagicPods-Windows [P10] [M10] | Windows | 2026-09-22 (repository push) | 880 GitHub stars | AirPods integration; MagicAAP driver adds noise and button customization. | Inference: Push in 2026; active inference | 3/5; No repository license detected; do not assume implementation reusable. |
| steam3d/MagicPodsLinux [P11] [M11] | Linux / SteamOS | 2026-09-20 (repository push) | 57 GitHub stars | Battery/noise controls and proximity popups for AirPods and other headphones. | Inference: Push in 2026; active inference | 3/5; GPL-3.0; useful adjacent protocol implementation. |
| librepods-org/librepods [P12] [M12] | Android / Linux | 2026-10-28 (repository push) | 30533 GitHub stars | Implements proprietary AirPods features via reverse-engineered AACP; includes Android head gestures. | Inference: Recent push; active inference | 4/5; GPL-3.0; platform requirements vary; not a stock macOS/iOS API. |
| furiousMAC/continuity [P13] [M13] | Protocol research / Wireshark | 2026-02-27 (repository push) | 687 GitHub stars | Documents Apple Continuity including proximity-pairing type 0x07 and lid-related counter. | Inference: Push in 2026; uncertain | 5/5; GPL-2.0; observations, not an Apple specification. |
| fischejo/airpods-notify [P14] [M14] | Linux / BLE research | 2022-12-19 (repository push) | 11 GitHub stars | Battery notification tool with documented model/status/battery/lid fields. | Inference: No push since 2022; uncertain | 4/5; No license detected; lid bit interpretation conflicts with AirPodsDesktop. |
| hammerspoon/hammerspoon [P15] [M15] [S43] | macOS | 2026-07-08 (repository push) | 16349 GitHub stars | Lua event taps and system-key events support automation/remapping. | Inference: Push in 2026; active inference | 4/5; MIT metadata; inspect individual files before reuse. AirPods transport visibility untested. |
| pqrs-org/Karabiner-Elements [P16] [M16] [S37] | macOS | 2026-10-29 (repository push) | 23030 GitHub stars | Remaps keyboard and consumer media key events through virtual input device. | Inference: Recent push; active inference | 4/5; Unlicense metadata; cannot assume AirPods appear as keyboard HID. |
| keymapperorg/KeyMapper [P17] [M17] | Android | 2026-10-26 (repository push) | 2784 GitHub stars | Remaps device/headset buttons into actions and keyboard input. | Inference: Recent push; active inference | 4/5; GPL-3.0; permissions and AirPods routing require device test. |
| ankidroid/Anki-Android [P18] [M18] [S24] [S25] | Android | 2026-10-30 (repository push) | 12128 GitHub stars | Reviewer has configurable key/controller bindings; accepts general KeyEvent codes. | Inference: Recent push; active inference | 5/5; GPL-3.0; no verified automatic AirPods-to-grading path. |
| AnkiConnect (current SourceHut; archived GitHub mirror) [P19] [M19] [S35] | Anki desktop | Current page: latest commit 10 days ago; mirror push 2025-11-04 | 2083 GitHub stars (archived mirror) | Local HTTP reviewer API; current development moved from archived GitHub to SourceHut. | Inference: Current SourceHut development; old mirror archived | 5/5; Current SourceHut license GPL-3.0-or-later; use API capabilities for installed version. |
| BetterTouchTool [P20] [S38] | macOS | Unknown (documentation current at access) | Not published | Special-key triggers include play/next/previous; can assign keyboard actions. | Inference: commercial product currently offered | 3/5; Paid license; unsuitable as required dependency for a free solution. AirPods interception untested. |
| 8BitDo Micro keyboard mode [P21] | macOS / iOS / Android / Windows | Unknown (undated FAQ) | Not published | K mode exposes a configurable keyboard; other modes are controller profiles. | Inference: supported product; update cadence unknown | 4/5; Hardware comparator recorded as app in required schema; not a free software solution. |
| Study Remote Anki add-on guide [P22] | Anki desktop / keyboard-capable hosts | 2025-11-25 (article) | Not published | Manufacturer describes keyboard-mode keystrokes and add-on custom mappings. | N/A (article); current product support unknown | 4/5; Manufacturer primary account; exact factory key map not established by this article. |
| 8BitDo Micro Anki key mapping guide [P23] | macOS | 2024-08-12 (last active) | 1 gist star | Author records Micro factory letters and Karabiner remaps to Space and answer numbers. | N/A (guide); no newer activity verified | 4/5; First-hand mapping example; firmware/profile dependent; not independently tested. |
| Media keys to answer Anki cards [P24] | Anki desktop (question) | 2023-05-17 (indexed post); later edits unknown | Not visible in accessible excerpt | Asks about answering cards with media keys; no working implementation verified. | N/A (discussion) | 3/5; Search excerpt only; direct page timed out. Not evidence that a working add-on exists. |
| Best Anki Remote? (r/medicalschool) [P25] | Desktop / mobile | 2026-06-16 (indexed post); edits unknown | Not shown in retrieved page | User discussion compares 8BitDo and other study controllers. | N/A (discussion) | 2/5; User preferences only; no protocol or reliability validation. |
| Control Eye Chart with AirPods [P26] | Mobile app; exact OS unverified | 2025-06-14 (indexed post); edits unknown | Not shown in retrieved page | Developer describes AirPods as an eye-chart remote; links demonstration. | Unknown | 3/5; Implementation and linked video not verified; not technical API evidence. |
| AirPods-controlled game (Hacker News) [P27] | iOS | 2025-09-24 (submission); later changes unknown | 222 points; 44 comments shown | Developer describes a game steered by headset motion. | Unknown (app); N/A (post) | 3/5; First-person project report; first-ever claim not adopted. |
| AirPods GATT access discussion (Apple Developer Forums) [P28] | macOS / iOS | Relative age: 1 week at access; exact date unverified | Not collected | Developer observes missing AirPods GATT services; Apple DTS explains system-service filtering. | N/A (discussion) | 4/5; GATT service filtering does not establish advertisement filtering. |
| Bluetooth audio cut-off discussion (Anki Forums) [P29] | Anki desktop / macOS | 2022-05-04 (visible discussion); later edits unknown | Not collected | Maintainer discusses short Bluetooth clips and silent-audio workaround. | N/A (discussion) | 3/5; Pitfall evidence only; no input mapping. |
| AirPods: fix audio dropouts (macOS) [P30] | Anki desktop / macOS | 2026-08-06 (AnkiWeb update) | 3 positive; 0 negative ratings | Keeps an inaudible audio stream open to reduce playback dropouts. | Inference: recently updated | 3/5; AnkiWeb rendered page reviewed in Chrome; author labels suspension explanation inference. Does not handle stem grading. |
| AirPod controls / Centre Court tennis score app discussion [P31] | iOS | 2023-09-27 (indexed post); edits unknown | Not shown in retrieved page | App author reports Remote Command Center plus silent background audio for scoring. | Unknown | 4/5; First-person anecdote; not a guarantee of App Store approval or AnkiMobile control. |
| AirPodsNod [P32] [S16] [S46] | macOS 14+ | Unknown (not exposed in retrieved snapshot) | Not exposed in retrieved snapshot | Core Motion nod/shake detection emits Enter/Escape for allowed foreground apps. | Unknown | 4/5; Inference: its exclusion of AirPods 3 contradicts Apple’s head-tracking list; use Apple support and a runtime check. License not verified. |
| AirPoise [P33] [S47] | macOS 14+ | Unknown (not exposed in retrieved snapshot) | Not exposed in retrieved snapshot | Head motion triggers configurable shortcuts; also provides posture feedback. | Unknown | 4/5; README declares MIT; gesture performance is author-reported and untested here. |
| AnkiDroid custom combination controls request #12425 [P34] | Android | 2022-09-17 (opened); later updates unknown | Not collected | Requests combinations and multi-press/long-press controls including headset/volume use. | N/A (open feature request at access) | 3/5; A request is not evidence of a shipped feature. |
| Contanki and media keys (r/Anki) [P35] | Anki desktop | 2026-06-16 (indexed post); edits unknown | Not shown in retrieved page | Asks why Contanki cannot emit programmed media keys. | N/A (discussion) | 2/5; Opposite direction from receiving AirPods commands; avoid false-positive match. |

### Search coverage and limits

**Research observation:** searches covered GitHub; AnkiWeb's live catalog (`headphone`, `media key`, `AirPods`); Anki Forums; r/Anki, r/medicalschool and r/airpods; Hacker News; Stack Overflow / Apple Developer Forums; and vendor/developer blogs. Useful forum matches and false positives are retained above. Stack Overflow searches did not supply a stronger relevant primary implementation than the Apple forum and project source. [S39] [P24] [P25] [P26] [P27] [P28] [P29] [P35]

**Research observation / limitation:** this was a public-source sweep, not an exhaustive index. AnkiWeb initially returned a JavaScript shell to text retrieval; its rendered catalog and the audio-fix listing were subsequently reviewed in Chrome without login. One Reddit result, P24, was available only as a search excerpt and timed out on direct retrieval. GitHub REST later rate-limited requests; no bypass was attempted. SourceHut's overview, API and license were readable through public HTTPS, but a later individual-commit request returned HTTP 418. These limitations are preserved in [sources.json](sources.json).

**Assessment — inference:** PodMouse's source is the strongest stem-input lead; AirClicker and other motion projects demonstrate related interaction designs. Their existence does not establish compatibility or reliability on this user's setup. Contanki, Ankimote and keyboard remotes solve different portions of the problem. None of their reviewed descriptions establishes a complete, tested AirPods-to-Anki controller. [P01] [P02] [P05] [P06] [P21] [S31]

### What commercial remotes actually send

8BitDo documents **keyboard mode** separately from gamepad modes. Study Remote describes keyboard-mode keystrokes and an add-on for remapping. **Inference:** the important distinction is keyboard/gamepad input versus headset media input; the reviewed material does not establish that every remote uses BLE HID rather than another Bluetooth transport. A ring/page-turner that emits only volume or swipe events is not automatically an Anki keyboard. The remote-driver project exists to adapt such inputs. [P21] [P22] [P07]

| Platform | Useful keyboard/controller inputs documented by the receiving app | Implication for remote mapping |
| --- | --- | --- |
| Anki desktop | Space/Enter shows the answer and accepts Good; number keys select answer buttons, normally 1 Again / 2 Hard / 3 Good / 4 Easy. [S21] | **Proposal:** use Space plus rating keys, or preferably a semantic reviewer API; obtain offered answers rather than assume every card has four buttons. [S33] |
| AnkiMobile | Space shows/accepts Good; 1–4 selects the numbered answer. Extended-profile gamepads can have actions assigned in preferences. [S17] [S18] | **Proposal:** configure each physical button in the app or keyboard profile. Undo is available as a study action; its keyboard shortcut was not verified here. [S19] (untested) |
| AnkiDroid | Manual lists Space/Enter for Show/Good, numbered answers, `z` for Undo, and gamepad answer buttons. Current source supports configurable key codes. [S22] [S24] | **Proposal:** use native control bindings first; distinguish keys arriving at the reviewer from media commands routed to another app. [S23] |

One first-hand Micro guide records defaults **D-pad up/down/left/right = c/d/e/f, A/X/Y/B = g/h/i/j, L/R = k/m, L2/R2 = l/r**, then remaps to Anki actions. That is a concrete profile example, not a universal key map for all remotes, firmware or operating modes. The manufacturer allows keyboard customization; the current Study Remote article does not establish its exact factory letters. [P23] [P21] [P22]

## AirPods input events per model and platform

### Hardware gestures and logical commands

Notation: **P/N/B** = play-pause / next / previous; these are logical media meanings, **not evidence of keyboard HID events**. “Motion” means a candidate for Apple's public motion stream, subject to `isDeviceMotionAvailable`, connection, permissions and OS/model support. Actual packet transport and event delivery for each model are **untested** here. [S08] [S09] [S11] [S31]

| Model | Normal music controls | Hold / volume / assistant controls | Built-in Siri nod/shake | Public motion candidate |
| --- | --- | --- | --- | --- |
| AirPods 2 | Double-tap each side: configurable P, N, B or Siri; no stem 1/2/3 sequence. [S01] | Voice Siri; double-tap can invoke Siri. [S01] | Not listed. [S01] | No dynamic head tracking in reviewed support list. [S16] |
| AirPods 3 | Stem 1/2/3 → P/N/B. [S01] | Hold Siri; no volume swipe. [S01] [S02] | Not listed. [S01] | Yes, conditional. [S16] [S08] |
| AirPods 4 | Stem 1/2/3 → P/N/B. [S01] | Hold Siri; no volume swipe. [S01] [S02] | Yes. [S01] | Yes, conditional. [S16] [S08] |
| AirPods 4 ANC | Stem 1/2/3 → P/N/B. [S01] | Hold noise modes or Siri; no volume swipe. [S01] [S02] | Yes. [S01] | Yes, conditional. [S16] [S08] |
| AirPods Pro 1 | Stem 1/2/3 → P/N/B. [S02] | Hold noise modes/Siri; no volume swipe. [S02] [S03] | Not listed. [S01] | Yes, conditional. [S16] [S08] |
| AirPods Pro 2, Lightning and USB-C | Stem 1/2/3 → P/N/B. [S04] [S05] | Hold noise modes/Siri; swipe volume. [S04] [S05] | Yes with suitable firmware/OS. [S15] | Yes, conditional. [S16] [S08] |
| AirPods Pro 3 | Stem 1/2/3 → P/N/B. [S02] | Hold noise modes/Siri; swipe volume. [S02] [S03] | Yes. [S01] | Yes, conditional. [S16] [S08] |
| AirPods Max | Crown 1/2/3 → P/N/B; rotate volume. [S02] | Hold crown Siri; separate noise button. [S02] | Max 1 Lightning/USB-C: not listed; current guide also lists **Max 2** for Siri head gestures. [S01] | Max head tracking supported; runtime check required for exact generation/connection. [S16] [S09] |

Apple's firmware notes explicitly associate Pro 2's Siri gestures with iOS/iPadOS 18 and macOS Sequoia (15), among other compatible hosts. These are responses to announcements/calls, not unrestricted application shortcuts. Newer models also require their own compatible firmware/OS; the older API's introduction date is not a promise that newer hardware works on every old release. [S15] [S01] (last sentence inference)

**Transport qualification — inference/untested:** normal Bluetooth playback controls are expected to follow AVRCP-style play/skip semantics, but no over-air capture was performed and the reviewed Apple user guides do not specify the wire protocol for every model/host. On Apple platforms there can also be accessory-specific paths. The defensible application contract is the delivered media command, not “every squeeze produces an `NX_KEYTYPE_*` event.” Siri, noise toggles, volume and call controls should not be counted as additional independently interceptable review buttons. [S11] [S31] [S02]

**Platform qualification — inference/untested:** the model table describes Apple’s documented normal controls. Siri labels do not imply an Android Siri callback; Android media delivery and any accessory-specific noise/head features need their own validation. The host matrix below applies to each listed model’s supported logical controls, not to unsupported gestures.

### Host APIs and interception limits

| Host | Available receiving mechanism | What is established / what remains untested |
| --- | --- | --- |
| macOS: preferred path | `MPRemoteCommandCenter`: toggle/play/pause, next/previous and other media commands. [S11] | PodMouse registers these handlers and keeps a silent audio engine and Now Playing state. It is concrete implementation evidence, not a hardware test here. Media ownership and competing playback remain **untested**. [S31] |
| macOS: event path | `NSEvent` local/global monitors, event taps, Hammerspoon system-key events; Karabiner consumer-key remapping. [S36] [S43] [S37] | Global monitoring observes rather than cancels events; swallowing requires a different mechanism. These operate on events the OS actually exposes. **Inference:** a missing event does not prove the AirPod sent nothing. HID remapping cannot create an input device that the OS never exposes. |
| iOS / AnkiMobile | `MPRemoteCommandCenter` belongs to the eligible Now Playing app; Apple says playback must begin before remote events arrive. [S12] | A companion can handle its own playback commands but no supported route into AnkiMobile's reviewer was found in its actions/URL documentation. **Inference:** this is not a drop-in AnkiMobile controller. [S17] [S19] [S20] |
| Android / AnkiDroid | Media-button `KeyEvent.KEYCODE_MEDIA_*` delivery, foreground dispatch and media-session routing. [S23] | AnkiDroid can bind arbitrary received key codes, but its current main-source search found no explicit standard media-button/session handler in the searched files. Binding UI support alone does not ensure Bluetooth delivery. **Untested:** capture actual single/double/triple commands on the target phone. [S24] [S25] |

**Research observation:** the AnkiDroid archive search covered 2,922 `.kt`, `.java` and `.xml` files under `src/main`, looking for `KEYCODE_MEDIA_PLAY/PAUSE/NEXT/PREVIOUS`, `MediaSession` and headset-hook identifiers. It found no explicit matching handler; `Binding.kt` does accept general `KeyEvent.keyCode` values. This is a limited static inspection: dependencies, alternative naming, WebView behavior or OS dispatch could affect runtime results. It does **not** prove media buttons are impossible. [S24] [S25]

**Design inference:** accept `play`, `pause` and `toggle` as one logical action, never two successive grades; serialize actions and reject duplicates tied to the same reviewer state. Command callbacks should not be assumed to identify which earbud—or even which physical remote—originated them. Ear detection, Control Center, keyboard keys and other players can affect the same media path. Gate operation behind an explicit study mode and active reviewer, and suspend around disconnects/calls. [S03] [S11] [S31]

There is a newer exception to “only media controls”: iOS 26 camera apps can use AirPods capture controls through `AVCaptureEventInteraction`. Apple scopes that interaction to active capture use, not arbitrary background apps. **Inference:** adding a camera session to a study companion is not a justified general AnkiMobile bridge. [S13] [S14]

### Motion and the number of usable actions

`CMHeadphoneMotionManager` arrived on iOS/iPadOS 14 and macOS 14. Apple demonstrates `CMDeviceMotion` attitude, acceleration and rotation rate, with sensor-location and connection information. Use `isDeviceMotionAvailable`; include `NSMotionUsageDescription` before starting updates. With ear detection active, removing the buds can disconnect the motion stream. This is enough input for an app's own gesture classifier; Apple does not promise classifier accuracy. [S08] [S09]

`CMHeadphoneActivityManager` (iOS 18 / macOS 15) provides activity information; it is not a documented “Siri nodded yes” event subscription. **Inference:** use the motion stream to detect custom nods/shakes rather than assume Apple's announcement recognizer is exposed. Android does not expose Apple's Core Motion API; LibrePods is a separate reverse-engineered implementation, not a portable public equivalent. [S10] [P12]

| Inputs available | Distinct direct command budget | Proposed review behavior — all untested |
| --- | --- | --- |
| One AirPods 2 earbud | One configured double-tap meaning. [S01] | Show/Good only; insufficient for independent Again and Undo. |
| Both AirPods 2 earbuds | Up to two configured meanings, if set differently. [S01] | Show/Good and Again; Undo elsewhere. No settings were changed for this study. |
| Stem models or Max crown | Three usual music commands. [S02] [S31] | Single Show/Good; double Again; triple Undo: **four functions from three inputs**, using reviewer state. |
| Three commands plus custom motion | Extra classifications are possible, but reliable count is unmeasured. [S08] [P33] | Add left/right tilt = Hard/Easy, retaining triple Undo: six functions. Must validate false activations. |
| Three commands plus a menu | No extra hardware input; additional actions through state. **Inference.** | Single Show/confirm; double cycle offered grades; triple Undo/cancel. Supports all grades with more presses. |

**Reliability assessment — inference:** no set of four to six actions can honestly be called reliable before hardware testing. Counting each squeeze of a double/triple press separately risks unintended grades: use the OS's resolved logical command. Long-press usually invokes Siri/noise control, and swipe/rotation changes volume; neither is a dependable spare grading key. Custom motion needs calibration, deliberate-return detection and a cooldown, plus an easy way to disable it. [S01] [S02] [S31] [S46]

## Case-only analysis

### Button, lid and case generation

Apple documents the case's setup control for pairing/reset, not as a keyboard or media remote. Older relevant cases use a rear button; AirPods 4 and Pro 3 use front touch interactions for setup. Opening a case with buds is part of Apple's connection flow. **Inference:** a popup or pairing-state change is not an application-level click, and repeatedly invoking setup is not a sensible review input. No case-button event field or public button callback was identified. [S06] [S07] [S28]

| Case / state | Evidence | Verdict — inference unless stated otherwise |
| --- | --- | --- |
| AirPods 2/3 and Pro 1-style cases, earbuds inside | Older reverse engineering attributes case telemetry advertisements to an earbud and documents lid-related bytes. [S27] [S29] | Lid experiment is plausible without wearing an earbud. Not a stable multi-button controller. |
| Same cases, empty | Reviewed implementation says the case itself has no Bluetooth radio; empty-case lid counts are not supplied by that path. [S27] [S29] | Do not expect the old proximity method to work. That historical claim must not be generalized to every newer case. |
| Pro 2 Lightning or USB-C MagSafe case | Apple lists case U1, speaker and lanyard features. [S04] [S05] | Those features do not document a third-party case-input API. Independent empty-case lid/button control is **unverified**. |
| AirPods 4 / 4 ANC and Pro 3 cases | Apple documents different setup controls; newer models appear in the community decoder. [S07] [S30] | Parsing a model ID is not evidence of empty-case support, button events or reliable lid latency. Each exact case needs a test. |
| AirPods Max Smart Case | Headphone controls are on the crown/noise button, not described as case controls. [S02] | No useful case-input path found; do not transfer earbud charging-case packet assumptions. |

### Advertisements, fields and disagreement

The useful reverse-engineered family is Apple manufacturer data (`0x004C`, bytes `4c 00`) containing Continuity **proximity pairing type `0x07`**. Common packets have a type/length header, model, status/ear-placement bits, battery/charging information and a lid-related byte. The project's packet validator expects 27 bytes excluding the company ID, or 29 including it. This is a community format, not an Apple compatibility commitment. [S28] [S29] [S30]

In AirPodsDesktop's layout, the candidate lid byte is at **zero-based index 10 including `4c 00`**, or 8 when the company ID is removed. Its low three bits are a wrapping/resetting switch counter and bit 3 is named `closed`; its decoder treats zero as open. **Inference:** these offsets follow the inspected packed layout, not a new measurement. [S29] [S30]

**Conflicting evidence:** airpods-notify describes the polarity differently (bit 3 set means open), and its offset documentation is not fully consistent with the other layout. Continuity documentation describes an open-related count without guaranteeing the same transition semantics. Consequently the probe logs the byte, low bits and bit value as **candidates**, without claiming open/closed truth. Do not assume one monotonically increasing counter, stable addresses, or one packet per physical action. [S27] [S28] [S29]

**Untested:** no lid latency, advertisement interval, lost-packet rate, usable range or current-model empty-case behavior was measured. A close may stop advertisements rather than produce an observable close packet; absence is not an immediate close signal. **Inference:** duplicate reports, dropped packets, rotating peripheral identities, nearby other AirPods and counter wrap/reset complicate event detection. A timeout cannot safely stand for a precise button press. Source evidence supports experimentation, not a latency promise. [S28] [S29] [S41]

### Does CoreBluetooth filter the data?

The 2020 BTLEmap paper explicitly reports Apple manufacturer-data filtering on **iOS**, while its **macOS** CoreBluetooth implementation did not strip that data. This is historical platform evidence, not a guarantee for the current user's macOS/firmware. A recent Apple DTS reply confirms that system-implemented **GATT services** can be filtered, which is a different layer from manufacturer-data advertisements. It would be incorrect to conclude “all Apple advertisements are filtered on Mac” from that reply. [S26] [P28]

**Proposed experiment:** use foreground `CBCentralManager.scanForPeripherals(withServices: nil)` with duplicate observations enabled, inspect manufacturer data, and correlate raw candidate fields with human-timed lid movements. CoreBluetooth is OS-mediated scanning, not an unrestricted radio sniffer; successful observation does not provide a supported case API. The passive probe does not connect, pair or write characteristics. [S41] (inference)

### Must an earbud be worn?

Apple documents automatic pause/routing changes when earbuds are removed; disabling automatic ear detection sends audio to the AirPods regardless of whether worn. Apple's motion talk also describes wear-driven connection events. Neither establishes all-model **held stem-squeeze** reliability. AirClicker's author describes held-bud motion control with ear detection disabled and silent audio keeping the stream alive; that is useful first-person evidence for motion, not proof of stem behavior. [S03] [S08] [P01]

| Physical state | Assessment |
| --- | --- |
| Buds inside an open case | **Inference:** may supply proximity telemetry; not an established stem controller. No in-ear requirement for the historical lid method. [S27] [S29] |
| One bud worn and connected | Documented usage context for playback controls; **untested locally**. [S01] [S02] |
| One bud out of case and held | **Plausible but untested:** press detection and delivery may differ with current ear-detection/routing state. Motion has an author demonstration. [P01] [S03] |
| Both buds out but none worn | **Untested:** automatic ear detection may stop/reroute audio and motion. [S03] [S08] |
| Empty case | Historical lid method lacks a broadcasting bud; newer independent case features do not establish a public lid/button stream. [S27] [S04] (inference) |

**Final case verdict — inference:** **feasible-but-hacky** for one coarse lid input on some configurations, usually with an earbud inside in the older implementations. **Not established** for an empty-case remote, arbitrary case-button presses, or full four-to-six-action reviewing. Prefer an earbud controller; treat the case probe as a bounded feasibility experiment rather than the product foundation.

## Architecture options with recommendation

All four options below are **proposals**, not implemented or tested systems. Complexity estimates are engineering inferences relative to a small prototype; OS support, packaging and reliability work would increase them.

| Option | Concrete design and mapping | Advantages / complexity | Main limitations and reuse |
| --- | --- | --- | --- |
| **A. Anki desktop add-on** | On macOS, bridge AppKit/system media events into Anki's Qt main thread; act only in reviewer state. P → Show/Good, N → Again, B → Undo. If system-key delivery fails, a native command receiver is still needed. | Direct reviewer context; **medium** if visible events arrive, **high** if native audio/Now Playing integration is needed. | Event visibility is untested; local Qt key handlers are insufficient for commands consumed by another app. Contanki offers reviewer/action ideas (AGPL-3.0); Ankimote and Remote Driver offer MIT bridge examples. [P05] [P06] [P07] [S36] |
| **B. Native macOS menu-bar helper — recommended** | Register media-command handlers; explicitly arm study mode; obtain Anki state through loopback AnkiConnect. Use P → Show/Good, N → Again, B → Undo; later add optional Hard/Easy motion or menu mode. | Clear separation of media routing and reviewer logic; **medium** prototype, **medium–high** reliable distribution. Motion requires macOS 14+; command API predates it. | Now Playing competition, silent audio, focus and calls need testing. MIT PodMouse/AirClicker are useful input examples; AnkiConnect is GPL-3.0-or-later. Calls over HTTP do not mean its source has been copied; check actual files/dependencies before distribution. [S11] [S31] [S32] [S35] |
| **C. iOS companion / own reviewer** | Own app can receive media commands while eligible Now Playing and classify headphone motion. Same three-command mapping works only for actions the app owns. | **High**, and no established bridge into the requested AnkiMobile reviewer. | No documented grading URL; synthetic cross-app key injection is not an established public solution. A separate reviewer or upstream AnkiMobile feature would change scope. Existing tennis/game posts show related use, not interoperability. Use native AnkiMobile keyboard/gamepad support for existing physical controllers. [S12] [S17] [S20] [P31] [P27] |
| **D. Android / AnkiDroid** | First test existing control binding capture for play/next/previous. If delivered, map to Show/Good, Again, Undo. Otherwise consider a Key Mapper configuration, native MediaSession helper plus permitted input bridge, or an AnkiDroid contribution that handles commands within reviewer state. | **Low** if native binding receives commands; **medium–high** if a companion/input method or upstream change is required. | OS media routing, foreground/background behavior, OEM power management and permissions need tests; no stock head-motion API established. Key Mapper / AnkiDroid / LibrePods are GPL-3.0 metadata, with file-level verification needed before reuse. [S23] [S24] [P17] [P18] [P12] |

### Recommended macOS contract

The current AnkiConnect project moved from GitHub to SourceHut; an archived GitHub repository is **not** evidence that the current add-on is abandoned. Its current documentation recommends JSON-RPC v1, defaults to loopback port 8765, requires Anki Desktop 26.08+, and retains the older version-6 action API. Check the installed capabilities instead of assuming the user's Anki version. [S45] [P19]

**Proposed v1 flow:** query `reviewer.get`; if on the question, `reviewer.showAnswer` using the current state token; if on the answer, `reviewer.answer` with an offered named rating. Reacquire state after each change and wait for operation completion. Use `collection.undo` only when the intended last review is still the undo target. Tokens/operation results help reject stale or overlapping actions. For older add-ons, legacy `guiCurrentCard`, `guiShowAnswer`, `guiAnswerCard` and `guiUndo` need a separate compatibility check. [S33] [S34] (design inference)

**Proposed safeguards and behavior:**

- Explicit arm/disarm state; require the Anki reviewer and intended profile. Ignore commands in editors/dialogs, during an outstanding action, and when disconnected. Do not treat a connection/automatic pause as a deliberate answer.
- A double press means Again only when an answer is visible; on the question it should do nothing or show the answer, according to a user-selected policy. Never silently grade an unseen answer.
- Deduplicate equivalent play/pause/toggle callbacks; expire events rather than replay a queue after an interruption. On an uncertain HTTP result, refresh state rather than retry a grade blindly.
- Keep the API on loopback. Prefer semantic calls to foreground-dependent simulated keys. If a keystroke fallback is chosen, it requires its own focus/permission checks and a tested answer-button map.
- Start with three commands. Add Hard/Easy only after the core path passes tests; offer a visible grade-selection mode before requiring head movement.

These are engineering proposals based on reviewer-state APIs and shared media-command routing, not existing product behavior. [S33] [S11] [S03]

**Known pitfalls to validate:** Music launching is sufficiently common to motivate noTunes, but noTunes itself does not capture review commands. Silent playback may keep an audio route active and consume battery; Anki's short card audio can compete with that route. Avoid claiming both uninterrupted Spotify/music control and exclusive review use of the same three commands. Built-in call/Siri behavior and automatic switching can take control away. No private `MediaRemote` framework or device firmware modification is required by the recommended prototype. [P04] [P01] [P29] [P30] [S12] (design inference)

### Local probes and next test gate

Two small Swift probes live in [probes/](probes/README.md): a passive system-media-event observer and an Apple manufacturer-advertisement scanner. **Local verification:** both compiled with the installed Swift compiler on 2026-10-30; neither was executed. They request no permissions themselves and exit if not already authorized. No hardware results exist. The README includes exact commands, expected fields, negative-result limits and a human test matrix.

**Proposed acceptance gate:** record at least 30 deliberate examples of each intended gesture, count misses/duplicates/false actions, and observe an idle interval plus card-audio playback and an app switch. Test held versus worn only with existing device settings recorded. For the lid experiment, correlate at least 20 open/close cycles in each available case occupancy state. These counts are suggested experimental minimums, not statistical proof or measured results. Do not start grading real cards during logging tests.

## Open questions

These are questions for a later implementation/test phase; they did not block the authorized research deliverables.

1. Which exact AirPods generation and case model (including Pro 2 Lightning versus USB-C, or Max generation) does the user own, and what firmware/macOS/Anki versions are in use?
2. Is holding a single earbud acceptable, or is an **empty case** a firm requirement? Must an earbud remain usable for listening at the same time?
3. Are Show/Good, Again and Undo sufficient initially, or must Hard/Easy each have an immediate gesture?
4. Is a deliberate head tilt acceptable, or would a small grade-selection menu be preferable?
5. Must controls coexist with music/podcasts, call handling and Anki card audio? Which should have priority?
6. Which secondary platform and exact AnkiMobile/AnkiDroid version should be tested first?
7. For a later user-run test, are the necessary observation permissions already present? If not, the supplied probes intentionally stop; no permission or Bluetooth settings were changed here.

## Sources

Every entry below was accessed **2026-10-30**. IDs in prose/tables link directly to these sources. “Reviewed” means the relevant public content or selected source sections were read; it does not mean that software was installed or claims independently reproduced. The inventory contains **101 distinct URLs: 81 substantive content/source URLs reviewed, 19 GitHub metadata endpoints reviewed, and 1 search-excerpt-only result**. It excludes failed guessed documentation URLs, generic search noise and duplicate locale/query variants not used as evidence. The machine-readable record is [sources.json](sources.json).

- **M01** — [Harelzx/airclicker repository metadata](https://api.github.com/repos/Harelzx/airclicker). Accessed **2026-10-30**. Public GitHub REST metadata; selected fields saved in repository_metadata.json. Push date is not release date.
- **M02** — [tony1010-dev/PodMouse repository metadata](https://api.github.com/repos/tony1010-dev/PodMouse). Accessed **2026-10-30**. Public GitHub REST metadata; selected fields saved in repository_metadata.json. Push date is not release date.
- **M03** — [nhurden/MediaKeyTap repository metadata](https://api.github.com/repos/nhurden/MediaKeyTap). Accessed **2026-10-30**. Public GitHub REST metadata; selected fields saved in repository_metadata.json. Push date is not release date.
- **M04** — [tombonez/noTunes repository metadata](https://api.github.com/repos/tombonez/noTunes). Accessed **2026-10-30**. Public GitHub REST metadata; selected fields saved in repository_metadata.json. Push date is not release date.
- **M05** — [roxgib/anki-contanki repository metadata](https://api.github.com/repos/roxgib/anki-contanki). Accessed **2026-10-30**. Public GitHub REST metadata; selected fields saved in repository_metadata.json. Push date is not release date.
- **M06** — [TheDabblingDuck/ankimote repository metadata](https://api.github.com/repos/TheDabblingDuck/ankimote). Accessed **2026-10-30**. Public GitHub REST metadata; selected fields saved in repository_metadata.json. Push date is not release date.
- **M07** — [CoderBomber68/Anki-Remote-Driver repository metadata](https://api.github.com/repos/CoderBomber68/Anki-Remote-Driver). Accessed **2026-10-30**. Public GitHub REST metadata; selected fields saved in repository_metadata.json. Push date is not release date.
- **M08** — [adolfintel/OpenPods repository metadata](https://api.github.com/repos/adolfintel/OpenPods). Accessed **2026-10-30**. Public GitHub REST metadata; selected fields saved in repository_metadata.json. Push date is not release date.
- **M09** — [SpriteOvO/AirPodsDesktop repository metadata](https://api.github.com/repos/SpriteOvO/AirPodsDesktop). Accessed **2026-10-30**. Public GitHub REST metadata; selected fields saved in repository_metadata.json. Push date is not release date.
- **M10** — [steam3d/MagicPods-Windows repository metadata](https://api.github.com/repos/steam3d/MagicPods-Windows). Accessed **2026-10-30**. Public GitHub REST metadata; selected fields saved in repository_metadata.json. Push date is not release date.
- **M11** — [steam3d/MagicPodsLinux repository metadata](https://api.github.com/repos/steam3d/MagicPodsLinux). Accessed **2026-10-30**. Public GitHub REST metadata; selected fields saved in repository_metadata.json. Push date is not release date.
- **M12** — [librepods-org/librepods repository metadata](https://api.github.com/repos/librepods-org/librepods). Accessed **2026-10-30**. Public GitHub REST metadata; selected fields saved in repository_metadata.json. Push date is not release date.
- **M13** — [furiousMAC/continuity repository metadata](https://api.github.com/repos/furiousMAC/continuity). Accessed **2026-10-30**. Public GitHub REST metadata; selected fields saved in repository_metadata.json. Push date is not release date.
- **M14** — [fischejo/airpods-notify repository metadata](https://api.github.com/repos/fischejo/airpods-notify). Accessed **2026-10-30**. Public GitHub REST metadata; selected fields saved in repository_metadata.json. Push date is not release date.
- **M15** — [hammerspoon/hammerspoon repository metadata](https://api.github.com/repos/hammerspoon/hammerspoon). Accessed **2026-10-30**. Public GitHub REST metadata; selected fields saved in repository_metadata.json. Push date is not release date.
- **M16** — [pqrs-org/Karabiner-Elements repository metadata](https://api.github.com/repos/pqrs-org/Karabiner-Elements). Accessed **2026-10-30**. Public GitHub REST metadata; selected fields saved in repository_metadata.json. Push date is not release date.
- **M17** — [keymapperorg/KeyMapper repository metadata](https://api.github.com/repos/keymapperorg/KeyMapper). Accessed **2026-10-30**. Public GitHub REST metadata; selected fields saved in repository_metadata.json. Push date is not release date.
- **M18** — [ankidroid/Anki-Android repository metadata](https://api.github.com/repos/ankidroid/Anki-Android). Accessed **2026-10-30**. Public GitHub REST metadata; selected fields saved in repository_metadata.json. Push date is not release date.
- **M19** — [FooSoft/anki-connect repository metadata](https://api.github.com/repos/FooSoft/anki-connect). Accessed **2026-10-30**. Public GitHub REST metadata; selected fields saved in repository_metadata.json. Push date is not release date.
- **P01** — [Harelzx/airclicker](https://github.com/Harelzx/airclicker). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **P02** — [tony1010-dev/PodMouse](https://github.com/tony1010-dev/PodMouse). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **P03** — [nhurden/MediaKeyTap](https://github.com/nhurden/MediaKeyTap). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **P04** — [tombonez/noTunes](https://github.com/tombonez/noTunes). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **P05** — [roxgib/anki-contanki](https://github.com/roxgib/anki-contanki). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **P06** — [TheDabblingDuck/ankimote](https://github.com/TheDabblingDuck/ankimote). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **P07** — [CoderBomber68/Anki-Remote-Driver](https://github.com/CoderBomber68/Anki-Remote-Driver). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **P08** — [adolfintel/OpenPods](https://github.com/adolfintel/OpenPods). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **P09** — [SpriteOvO/AirPodsDesktop](https://github.com/SpriteOvO/AirPodsDesktop). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **P10** — [steam3d/MagicPods-Windows](https://github.com/steam3d/MagicPods-Windows). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **P11** — [steam3d/MagicPodsLinux](https://github.com/steam3d/MagicPodsLinux). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **P12** — [librepods-org/librepods](https://github.com/librepods-org/librepods). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **P13** — [furiousMAC/continuity](https://github.com/furiousMAC/continuity). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **P14** — [fischejo/airpods-notify](https://github.com/fischejo/airpods-notify). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **P15** — [hammerspoon/hammerspoon](https://github.com/Hammerspoon/hammerspoon). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **P16** — [pqrs-org/Karabiner-Elements](https://github.com/pqrs-org/Karabiner-Elements). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **P17** — [keymapperorg/KeyMapper](https://github.com/keymapperorg/KeyMapper). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **P18** — [ankidroid/Anki-Android](https://github.com/ankidroid/Anki-Android). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **P19** — [AnkiConnect (current SourceHut; archived GitHub mirror)](https://git.sr.ht/~foosoft/anki-connect). Accessed **2026-10-30**. Read successfully using public HTTPS retrieval after web-tool restriction. Later individual commit lookup returned HTTP 418; no workaround attempted.
- **P20** — [BetterTouchTool](https://docs.folivora.ai/docs/json/trigger-definitions/). Accessed **2026-10-30**. Reviewed public page; implementation claims attributed to author where applicable.
- **P21** — [8BitDo Micro keyboard mode](https://support.8bitdo.com/faq/micro.html). Accessed **2026-10-30**. Reviewed public page; implementation claims attributed to author where applicable.
- **P22** — [Study Remote Anki add-on guide](https://studyremote.com/blogs/quick-guide/anki-remote-add-on). Accessed **2026-10-30**. Reviewed public page; implementation claims attributed to author where applicable.
- **P23** — [8BitDo Micro Anki key mapping guide](https://gist.github.com/emleddin/fa059bd25445f9bb30150857640c0bc9/). Accessed **2026-10-30**. Reviewed public page; implementation claims attributed to author where applicable.
- **P24** — [Media keys to answer Anki cards](https://www.reddit.com/r/Anki/comments/13k5v7z). Accessed **2026-10-30**. Search excerpt reviewed; full page timed out.
- **P25** — [Best Anki Remote? (r/medicalschool)](https://www.reddit.com/r/medicalschool/comments/1u7jaz1/best_anki_remote/). Accessed **2026-10-30**. Reviewed public page; implementation claims attributed to author where applicable.
- **P26** — [Control Eye Chart with AirPods](https://www.reddit.com/r/airpods/comments/1lawpws). Accessed **2026-10-30**. Reviewed public page; implementation claims attributed to author where applicable.
- **P27** — [AirPods-controlled game (Hacker News)](https://news.ycombinator.com/item?id=45362365). Accessed **2026-10-30**. Reviewed public page; implementation claims attributed to author where applicable.
- **P28** — [AirPods GATT access discussion (Apple Developer Forums)](https://developer.apple.com/forums/thread/845352). Accessed **2026-10-30**. Reviewed public page; implementation claims attributed to author where applicable.
- **P29** — [Bluetooth audio cut-off discussion (Anki Forums)](https://forums.ankiweb.net/t/audio-cut-off-at-end-with-macos-monterey-12-3-1/19695). Accessed **2026-10-30**. Reviewed public page; implementation claims attributed to author where applicable.
- **P30** — [AirPods: fix audio dropouts (macOS)](https://ankiweb.net/shared/info/676963607). Accessed **2026-10-30**. Reviewed public page; implementation claims attributed to author where applicable.
- **P31** — [AirPod controls / Centre Court tennis score app discussion](https://www.reddit.com/r/iOSProgramming/comments/16tajqc). Accessed **2026-10-30**. Reviewed public page; implementation claims attributed to author where applicable.
- **P32** — [AirPodsNod](https://github.com/kun-Jiang/AirPods_Nod). Accessed **2026-10-30**. Reviewed public page; implementation claims attributed to author where applicable.
- **P33** — [AirPoise](https://github.com/jaskirat1616/AirPoise). Accessed **2026-10-30**. Reviewed public page; implementation claims attributed to author where applicable.
- **P34** — [AnkiDroid custom combination controls request #12425](https://github.com/ankidroid/Anki-Android/issues/12425). Accessed **2026-10-30**. Reviewed public page; implementation claims attributed to author where applicable.
- **P35** — [Contanki and media keys (r/Anki)](https://www.reddit.com/r/Anki/comments/1u6zjc4/contanki_and_media_keys/). Accessed **2026-10-30**. Reviewed public page; implementation claims attributed to author where applicable.
- **S01** — [Apple AirPods controls and gestures](https://support.apple.com/guide/airpods/use-controls-and-gestures-with-your-airpods-devb2c431317/web). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S02** — [Apple pause, skip and adjust volume](https://support.apple.com/en-ie/102628). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S03** — [Apple AirPods settings and automatic ear detection](https://support.apple.com/en-gb/108764). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S04** — [AirPods Pro 2 USB-C technical specifications](https://support.apple.com/en-us/111834). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S05** — [AirPods Pro 2 Lightning technical specifications](https://support.apple.com/en-in/111851). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S06** — [Apple restart and reset AirPods](https://support.apple.com/en-euro/guide/airpods/iph561965261/web). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S07** — [Apple AirPods pairing controls](https://support.apple.com/en-my/118576). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S08** — [WWDC23: What is new in Core Motion (transcript)](https://developer.apple.com/videos/play/wwdc2023/10179/). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S09** — [CMHeadphoneMotionManager](https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager?changes=latest_major). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S10** — [CMHeadphoneActivityManager](https://developer.apple.com/documentation/coremotion/cmheadphoneactivitymanager.md). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S11** — [MPRemoteCommandCenter](https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter.md). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S12** — [Handling external player events notifications](https://developer.apple.com/documentation/mediaplayer/handling-external-player-events-notifications.md). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S13** — [WWDC25 camera capture features](https://developer.apple.com/videos/play/wwdc2025/253/). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S14** — [AVCaptureEventInteraction](https://developer.apple.com/documentation/avkit/avcaptureeventinteraction?changes=_8_2&language=objc). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S15** — [AirPods firmware release notes; 7A294](https://support.apple.com/en-us/106340). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S16** — [Apple Spatial Audio and head tracking support](https://support.apple.com/my-mm/guide/airpods/dev00eb7e0a3/web). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S17** — [AnkiMobile preferences and gamepad support](https://docs.ankiweb.net/ankimobile/preferences). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S18** — [AnkiMobile study-screen keyboard shortcuts](https://docs.ankiweb.net/ankimobile/study-screen.md). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S19** — [AnkiMobile study tools and user actions](https://docs.ankiweb.net/ankimobile/study-tools.md). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S20** — [AnkiMobile URL schemes](https://docs.ankiweb.net/ankimobile/url-schemes.md). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S21** — [Anki desktop studying manual](https://docs.ankiweb.net/manual/studying). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S22** — [AnkiDroid manual](https://docs.ankidroid.org/). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S23** — [Android media-button routing](https://developer.android.com/media/legacy/media-buttons). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S24** — [AnkiDroid general key bindings source](https://raw.githubusercontent.com/ankidroid/Anki-Android/main/AnkiDroid/src/main/java/com/ichi2/anki/reviewer/Binding.kt). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S25** — [AnkiDroid main source archive](https://codeload.github.com/ankidroid/Anki-Android/tar.gz/refs/heads/main). Accessed **2026-10-30**. Archive read in memory; 2,922 main Kotlin/Java/XML files searched, with no explicit media/session/headset-hook identifier matches. No extraction, execution, installation or git operation.
- **S26** — [BTLEmap demonstration paper (WiSec 2020)](https://wisec2020.ins.jku.at/proceedings/wisec20-6.pdf). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S27** — [airpods-notify proximity protocol documentation](https://github.com/fischejo/airpods-notify/blob/master/doc/proximity_protocol.md). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S28** — [Continuity proximity-pairing documentation](https://github.com/furiousMAC/continuity/blob/master/messages/proximity_pairing.md). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S29** — [AirPodsDesktop Apple Continuity packet layout](https://raw.githubusercontent.com/SpriteOvO/AirPodsDesktop/main/Source/Core/AppleCP.h). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S30** — [AirPodsDesktop packet validation and lid decoder](https://raw.githubusercontent.com/SpriteOvO/AirPodsDesktop/main/Source/Core/AppleCP.cpp). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S31** — [PodMouse StemButtons.swift](https://raw.githubusercontent.com/tony1010-dev/PodMouse/main/Sources/StemButtons.swift). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S32** — [AirClicker motion and key-event source](https://raw.githubusercontent.com/Harelzx/airclicker/main/Sources/AirClicker/main.swift). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S33** — [AnkiConnect current v1 API](https://git.sr.ht/~foosoft/anki-connect/blob/master/API_V1.md). Accessed **2026-10-30**. Read successfully using public HTTPS retrieval after web-tool restriction. Later individual commit lookup returned HTTP 418; no workaround attempted.
- **S34** — [AnkiConnect current legacy API](https://git.sr.ht/~foosoft/anki-connect/blob/master/API_LEGACY.md). Accessed **2026-10-30**. Read successfully using public HTTPS retrieval after web-tool restriction. Later individual commit lookup returned HTTP 418; no workaround attempted.
- **S35** — [AnkiConnect license](https://git.sr.ht/~foosoft/anki-connect/blob/master/LICENSE). Accessed **2026-10-30**. Read successfully using public HTTPS retrieval after web-tool restriction. Later individual commit lookup returned HTTP 418; no workaround attempted.
- **S36** — [Apple Cocoa event monitoring guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S37** — [Karabiner from-event definition](https://karabiner-elements.pqrs.org/docs/json/complex-modifications-manipulator-definition/from/). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S38** — [BetterTouchTool license offerings](https://folivora.ai/buy). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S39** — [AnkiWeb add-on catalog](https://ankiweb.net/shared/addons). Accessed **2026-10-30**. Live rendered catalog reviewed in Chrome; searches: headphone, media key, AirPods. Text-only fetch was a JavaScript shell.
- **S40** — [CoreBluetooth pre-creation authorization check](https://developer.apple.com/documentation/corebluetooth/cbmanager/authorization-swift.type.property.md). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S41** — [CoreBluetooth advertisement scanning](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/scanforperipherals(withservices:options:).md). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S42** — [CoreGraphics listen-event permission preflight](https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess().md). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S43** — [Hammerspoon event and system-key reference](https://www.hammerspoon.org/docs/hs.eventtap.event.html). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S44** — [OpenPods releases](https://github.com/adolfintel/OpenPods/releases). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S45** — [Archived AnkiConnect GitHub migration notice](https://github.com/FooSoft/anki-connect). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S46** — [AirPodsNod README](https://raw.githubusercontent.com/kun-Jiang/AirPods_Nod/main/README.md). Accessed **2026-10-30**. Reviewed public page/document or source file.
- **S47** — [AirPoise README](https://raw.githubusercontent.com/jaskirat1616/AirPoise/main/README.md). Accessed **2026-10-30**. Reviewed public page/document or source file.

[P01]: <https://github.com/Harelzx/airclicker>
[M01]: <https://api.github.com/repos/Harelzx/airclicker>
[P02]: <https://github.com/tony1010-dev/PodMouse>
[M02]: <https://api.github.com/repos/tony1010-dev/PodMouse>
[P03]: <https://github.com/nhurden/MediaKeyTap>
[M03]: <https://api.github.com/repos/nhurden/MediaKeyTap>
[P04]: <https://github.com/tombonez/noTunes>
[M04]: <https://api.github.com/repos/tombonez/noTunes>
[P05]: <https://github.com/roxgib/anki-contanki>
[M05]: <https://api.github.com/repos/roxgib/anki-contanki>
[P06]: <https://github.com/TheDabblingDuck/ankimote>
[M06]: <https://api.github.com/repos/TheDabblingDuck/ankimote>
[P07]: <https://github.com/CoderBomber68/Anki-Remote-Driver>
[M07]: <https://api.github.com/repos/CoderBomber68/Anki-Remote-Driver>
[P08]: <https://github.com/adolfintel/OpenPods>
[M08]: <https://api.github.com/repos/adolfintel/OpenPods>
[P09]: <https://github.com/SpriteOvO/AirPodsDesktop>
[M09]: <https://api.github.com/repos/SpriteOvO/AirPodsDesktop>
[P10]: <https://github.com/steam3d/MagicPods-Windows>
[M10]: <https://api.github.com/repos/steam3d/MagicPods-Windows>
[P11]: <https://github.com/steam3d/MagicPodsLinux>
[M11]: <https://api.github.com/repos/steam3d/MagicPodsLinux>
[P12]: <https://github.com/librepods-org/librepods>
[M12]: <https://api.github.com/repos/librepods-org/librepods>
[P13]: <https://github.com/furiousMAC/continuity>
[M13]: <https://api.github.com/repos/furiousMAC/continuity>
[P14]: <https://github.com/fischejo/airpods-notify>
[M14]: <https://api.github.com/repos/fischejo/airpods-notify>
[P15]: <https://github.com/Hammerspoon/hammerspoon>
[M15]: <https://api.github.com/repos/hammerspoon/hammerspoon>
[P16]: <https://github.com/pqrs-org/Karabiner-Elements>
[M16]: <https://api.github.com/repos/pqrs-org/Karabiner-Elements>
[P17]: <https://github.com/keymapperorg/KeyMapper>
[M17]: <https://api.github.com/repos/keymapperorg/KeyMapper>
[P18]: <https://github.com/ankidroid/Anki-Android>
[M18]: <https://api.github.com/repos/ankidroid/Anki-Android>
[P19]: <https://git.sr.ht/~foosoft/anki-connect>
[M19]: <https://api.github.com/repos/FooSoft/anki-connect>
[P20]: <https://docs.folivora.ai/docs/json/trigger-definitions/>
[P21]: <https://support.8bitdo.com/faq/micro.html>
[P22]: <https://studyremote.com/blogs/quick-guide/anki-remote-add-on>
[P23]: <https://gist.github.com/emleddin/fa059bd25445f9bb30150857640c0bc9/>
[P24]: <https://www.reddit.com/r/Anki/comments/13k5v7z>
[P25]: <https://www.reddit.com/r/medicalschool/comments/1u7jaz1/best_anki_remote/>
[P26]: <https://www.reddit.com/r/airpods/comments/1lawpws>
[P27]: <https://news.ycombinator.com/item?id=45362365>
[P28]: <https://developer.apple.com/forums/thread/845352>
[P29]: <https://forums.ankiweb.net/t/audio-cut-off-at-end-with-macos-monterey-12-3-1/19695>
[P30]: <https://ankiweb.net/shared/info/676963607>
[P31]: <https://www.reddit.com/r/iOSProgramming/comments/16tajqc>
[P32]: <https://github.com/kun-Jiang/AirPods_Nod>
[P33]: <https://github.com/jaskirat1616/AirPoise>
[P34]: <https://github.com/ankidroid/Anki-Android/issues/12425>
[P35]: <https://www.reddit.com/r/Anki/comments/1u6zjc4/contanki_and_media_keys/>
[S01]: <https://support.apple.com/guide/airpods/use-controls-and-gestures-with-your-airpods-devb2c431317/web>
[S02]: <https://support.apple.com/en-ie/102628>
[S03]: <https://support.apple.com/en-gb/108764>
[S04]: <https://support.apple.com/en-us/111834>
[S05]: <https://support.apple.com/en-in/111851>
[S06]: <https://support.apple.com/en-euro/guide/airpods/iph561965261/web>
[S07]: <https://support.apple.com/en-my/118576>
[S08]: <https://developer.apple.com/videos/play/wwdc2023/10179/>
[S09]: <https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager?changes=latest_major>
[S10]: <https://developer.apple.com/documentation/coremotion/cmheadphoneactivitymanager.md>
[S11]: <https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter.md>
[S12]: <https://developer.apple.com/documentation/mediaplayer/handling-external-player-events-notifications.md>
[S13]: <https://developer.apple.com/videos/play/wwdc2025/253/>
[S14]: <https://developer.apple.com/documentation/avkit/avcaptureeventinteraction?changes=_8_2&language=objc>
[S15]: <https://support.apple.com/en-us/106340>
[S16]: <https://support.apple.com/my-mm/guide/airpods/dev00eb7e0a3/web>
[S17]: <https://docs.ankiweb.net/ankimobile/preferences>
[S18]: <https://docs.ankiweb.net/ankimobile/study-screen.md>
[S19]: <https://docs.ankiweb.net/ankimobile/study-tools.md>
[S20]: <https://docs.ankiweb.net/ankimobile/url-schemes.md>
[S21]: <https://docs.ankiweb.net/manual/studying>
[S22]: <https://docs.ankidroid.org/>
[S23]: <https://developer.android.com/media/legacy/media-buttons>
[S24]: <https://raw.githubusercontent.com/ankidroid/Anki-Android/main/AnkiDroid/src/main/java/com/ichi2/anki/reviewer/Binding.kt>
[S25]: <https://codeload.github.com/ankidroid/Anki-Android/tar.gz/refs/heads/main>
[S26]: <https://wisec2020.ins.jku.at/proceedings/wisec20-6.pdf>
[S27]: <https://github.com/fischejo/airpods-notify/blob/master/doc/proximity_protocol.md>
[S28]: <https://github.com/furiousMAC/continuity/blob/master/messages/proximity_pairing.md>
[S29]: <https://raw.githubusercontent.com/SpriteOvO/AirPodsDesktop/main/Source/Core/AppleCP.h>
[S30]: <https://raw.githubusercontent.com/SpriteOvO/AirPodsDesktop/main/Source/Core/AppleCP.cpp>
[S31]: <https://raw.githubusercontent.com/tony1010-dev/PodMouse/main/Sources/StemButtons.swift>
[S32]: <https://raw.githubusercontent.com/Harelzx/airclicker/main/Sources/AirClicker/main.swift>
[S33]: <https://git.sr.ht/~foosoft/anki-connect/blob/master/API_V1.md>
[S34]: <https://git.sr.ht/~foosoft/anki-connect/blob/master/API_LEGACY.md>
[S35]: <https://git.sr.ht/~foosoft/anki-connect/blob/master/LICENSE>
[S36]: <https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html>
[S37]: <https://karabiner-elements.pqrs.org/docs/json/complex-modifications-manipulator-definition/from/>
[S38]: <https://folivora.ai/buy>
[S39]: <https://ankiweb.net/shared/addons>
[S40]: <https://developer.apple.com/documentation/corebluetooth/cbmanager/authorization-swift.type.property.md>
[S41]: <https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/scanforperipherals(withservices:options:).md>
[S42]: <https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess().md>
[S43]: <https://www.hammerspoon.org/docs/hs.eventtap.event.html>
[S44]: <https://github.com/adolfintel/OpenPods/releases>
[S45]: <https://github.com/FooSoft/anki-connect>
[S46]: <https://raw.githubusercontent.com/kun-Jiang/AirPods_Nod/main/README.md>
[S47]: <https://raw.githubusercontent.com/jaskirat1616/AirPoise/main/README.md>
