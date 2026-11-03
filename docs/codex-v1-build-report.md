# AirAnki v1 implementation report

Completed 2026-10-30 for [CODEX_BRIEF.md](CODEX_BRIEF.md), on local branch **codex/v1-app**. The app, core library, tests, bundle script and user documentation are implemented. The app was built and signed but **not launched**. Hardware and live Anki validation are intentionally left to the user.

## Delivered files

| Files | What they provide |
| --- | --- |
| AirAnki/Package.swift | macOS 14+ executable and Foundation-only core library; XCTest target and optional CLT self-test executable |
| AirAnki/Sources/AirAnkiCore/Gesture.swift, Action.swift, Mapping.swift | Three gestures, configurable actions, UserDefaults mappings, Easy/Good setting |
| AirAnki/Sources/AirAnkiCore/Debouncer.swift, ReviewController.swift | 350 ms quiet period, serialized actions, drop-while-busy, reviewer guards, state refresh, feedback; no mutation retries |
| AirAnki/Sources/AirAnkiCore/AnkiClient.swift | Protocol, loopback URLSession transport, legacy/V1 adapters, startup detection, reviewer tokens, offered ratings and operation polling |
| AirAnki/Sources/AirAnkiCore/LabCSV.swift | CSV formatting, escaping, raw-command and marker metadata |
| AirAnki/Sources/AirAnki/main.swift, AppDelegate.swift, MenuBar.swift | Menu-bar app, settings, 0.6-second feedback, optional Tink, connection check, CLI modes, clean shutdown |
| AirAnki/Sources/AirAnki/StemInput.swift | Silent audio loop, five media commands mapped to three gestures, Now Playing state, main-thread callbacks, raw logs, audio-configuration recovery |
| AirAnki/Sources/AirAnki/MotionLab.swift | Core Motion samples, connection callbacks, CSVs, numbered markers, permission/error diagnostics, one-second summaries |
| AirAnki/Tests/AirAnkiCoreTests/ReviewControllerTests.swift, AnkiClientTests.swift | Mock-review, concurrency, protocol/transport, debounce and CSV checks |
| AirAnki/Tests/AirAnkiCoreTests/SelfTestAssertions.swift, SelfTestMain.swift | Same test bodies without XCTest; nonzero exit on failure |
| Resources/Info.plist, scripts/build_app.sh, scripts/test.sh | Bundle metadata and Motion description, release build, ad-hoc signing, test fallback; local caches/temp files |
| README.md, docs/TESTING.md, THIRD_PARTY_NOTICES.md, .gitignore | Setup guide, complete human test tables, MIT attribution, ignored outputs |
| CODEX_REPORT.md | This replacement report |

Existing research files and CODEX_BRIEF.md were not changed. The generated **build/AirAnki.app** is present locally and ignored by Git.

## AnkiConnect API findings

Public plugin source was read before coding the client. **AnkiWeb serves different packages according to the Anki version.** Anki's downloader includes v=2.1 and p=<integer Anki version>; downloading with only v=2.1 retrieves a much older package. Modern version integers use YYMMPP. Sources: [Anki downloader](https://raw.githubusercontent.com/ankitects/anki/main/qt/aqt/addons.py), [version encoding](https://raw.githubusercontent.com/ankitects/anki/main/pylib/anki/utils.py), [AnkiWeb listing](https://ankiweb.net/shared/info/2055492159). All source access was on 2026-10-30.

These ZIP archives were inspected **in memory**, never installed or executed:

| Package selector | Observed source and capabilities |
| --- | --- |
| [v=2.1&p=260903](https://ankiweb.net/shared/download/2055492159?v=2.1&p=260903), Anki 26.09.3 | 91,090 bytes; legacy v6 and JSON-RPC V1 shipped together. Inspected __init__.py, legacy.py, gui.py, services.py and web.py match SourceHut tag 26.10.14.0 byte-for-byte. |
| [v=2.1&p=250900](https://ankiweb.net/shared/download/2055492159?v=2.1&p=250900), Anki 25.09; also p=65 | 25,659 bytes; legacy guiCurrentCard, guiShowAnswer, guiAnswerCard and guiUndo exist. No reviewer-side field. |
| [v=2.1 without p](https://ankiweb.net/shared/download/2055492159?v=2.1) | 15,658 bytes; older legacy package without guiUndo. This is not the package served to the current supported Anki version. |

SHA-256, current package: **456a546fd9e1bf53962c70618f7d72d10b1768690ce88fa5c9c6909ae5e9e1ec**.

SHA-256, p=250900/p=65 package: **665d9534654469b7e4708b4df235d43cf3770ff85b23b9ff5eb36f9b7b4133cf**.

Current SourceHut master was also inspected through its public archive; the overview identified commit **62fc13d107c2b02130e503749e9933495c6456fb**. Current requirements specify Anki Desktop 26.08+. Sources: [release archive](https://git.sr.ht/~foosoft/anki-connect/archive/26.10.14.0.tar.gz), [master archive](https://git.sr.ht/~foosoft/anki-connect/archive/master.tar.gz), [overview](https://git.sr.ht/~foosoft/anki-connect), [README](https://git.sr.ht/~foosoft/anki-connect/blob/master/README.md). SourceHut was inaccessible through the web reader, so ordinary public HTTPS retrieval was used. One tree URL returned HTTP 418; the public archives worked.

### Verified wire contract

- **Legacy:** POST / with action, version:6 and params; response has result/error. The version action returns 6 in both generations, so it cannot distinguish the releases. guiShowAnswer/guiAnswerCard return booleans; false is failure. guiUndo exists in both the current and normal legacy AnkiWeb packages.
- **State limitation:** guiCurrentCard includes both question and answer HTML on either side, plus card ID, buttons and metadata. Neither official implementation inspected exposes answerShown or an equivalent side field. Remembering AirAnki's own previous presses would become wrong after keyboard input, Undo or card/profile changes. Source: the actual packages and [legacy translation](https://git.sr.ht/~foosoft/anki-connect/blob/master/plugin/legacy.py).
- **V1:** POST /api/v1 using JSON-RPC 2.0, request ID, method and named params. reviewer.get supplies active, side (question/answer/none), stateToken, card ID and offered rating names. Inactive review or collectionUnavailable becomes notReviewing.
- **Show:** reviewer.showAnswer takes the current stateToken and returns a changed acknowledgement. AirAnki then re-reads and verifies the same card is on the answer side before a combined Again action.
- **Grade:** reviewer.answer takes stateToken and an offered rating (again/hard/good/easy). It returns an operation handle.
- **Undo:** collection.undo also returns an operation handle. AirAnki polls operations.get until success/failure/cancellation. It retains unresolved handles to prevent another action overtaking pending work; it never resends the mutation after a timeout.

Sources: [V1 API](https://git.sr.ht/~foosoft/anki-connect/blob/master/API_V1.md), [legacy API](https://git.sr.ht/~foosoft/anki-connect/blob/master/API_LEGACY.md), [reviewer implementation](https://git.sr.ht/~foosoft/anki-connect/blob/master/plugin/gui.py), [collection implementation](https://git.sr.ht/~foosoft/anki-connect/blob/master/plugin/services.py), and the actual AnkiWeb package above. Clients and tests were independently written against the protocol; no GPL/AGPL source was copied or translated.

### Necessary adjustment to the proposed legacy preference

The legacy adapter is implemented and its version action is probed first. **V1 is selected for operation when available**, because the required single-press Show/Easy semantics cannot safely be implemented from official legacy state payloads. Older installs can report not-reviewing, but fail closed with an upgrade message when review is active. This is an evidence-driven change from the brief's proposed legacy-primary preference. Full remote functionality requires Anki 26.08+ and the current AnkiWeb add-on; the README makes that requirement explicit.

No Cmd+Z/Accessibility fallback was needed for supported installs: the actual current package supports API Undo. The obsolete no-p package also lacks usable side detection and is outside supported reviewing compatibility. Synthetic Undo alone would not make it compatible. No Accessibility prompting or key injection was added.

## Implemented behaviour

Default single = Show/Easy (or Good), double = Show then Again, triple = Undo. Mappings, grade and optional sound are configurable in the menu and saved locally. Gestures inside the 350 ms quiet interval, while another action/connection check is in flight, or mapped to Do nothing are discarded. State is read before and after actions; errors surface without automatically retrying writes.

The transport only addresses **http://127.0.0.1:8765**, with two-second request/resource timeouts, proxies disabled, no cookies/cache, and redirects refused. No requestPermission API call is sent. An optional existing AnkiConnect API key can be read from AirAnki's UserDefaults; there is no key-entry UI.

Lab mode adds recording without changing mappings. **--lab-only never constructs an Anki client/controller or calls AnkiConnect.** It retains silent playback and stem capture for comparable hardware conditions; capture can be paused in its menu. The CSV includes all 18 requested columns plus raw_command, marker_id and detail, avoiding overloaded sensor fields. Non-motion sensor values stay blank. Writes flush every second, at markers, and on normal quit. Same-second filenames get numeric suffixes. Terminal Return inserts markers; Ctrl+C/SIGTERM close the log. There is no case-tap detector or motion grading.

## Verification results

Environment: Apple Silicon, Apple Swift 6.1.2, Command Line Tools; compiler target arm64-apple-macosx15.0. The package deployment minimum is macOS 14.

1. **Release build:** scripts/build_app.sh runs swift build -c release against AirAnki/ with repository-local cache/temp paths. Final build succeeded with **zero errors and zero compiler warnings**, producing build/AirAnki.app.
2. **XCTest attempt:** swift test was tried first and failed with **error: no such module 'XCTest'**. As the brief permits, the same test bodies were executed through AirAnkiCoreSelfTest. scripts/test.sh falls back only for that missing-module error, not ordinary test failures.
3. **Self-test result:**

       Build of product 'AirAnkiCoreSelfTest' complete! (1.60s)
       Executed 31 tests, with 0 failures in 0.119 seconds.

   Coverage includes all requested mock-review cases: single on question/answer with Easy/Good; double on question/answer with Again; triple Undo; not-reviewing guards; unreachable Anki; duplicate and overlapping gestures. Further checks cover failure without grade retries, post-action state, disabled mappings, debounce boundaries, stored mappings, CSV metadata/escaping, exact legacy actions, missing-side refusal, V1 detection, fresh/stale tokens, changed-card rejection, unavailable ratings, operation completion/failure/reconciliation, malformed responses and URLSession request serialization. HTTP tests intercept requests through URLProtocol; **no test opened a socket to Anki**. During development a test-harness unwrap exposed URLSession's streamed request body; it was fixed before the passing run.
4. **Metadata:** plutil -lint on both source and bundled Info.plist reported **OK**. Bundle identifier, LSUIElement, minimum OS 14.0 and the exact requested Motion usage text are present.
5. **Signature:** codesign -dv reported **Signature=adhoc**, identifier local.airanki.AirAnki, and an arm64 Mach-O app bundle. codesign --verify --strict --verbose=2 reported **valid on disk** and **satisfies its Designated Requirement**.
6. **Hygiene:** shell syntax, local documentation links, test-runner registration, whitespace and ignored outputs were checked. Sources and this report are committed locally on codex/v1-app; the final working-tree check follows the commit. Compiler, test and bundle outputs stay ignored.

## Manual work and remaining verification

- Install/update AnkiConnect through AnkiWeb code **2055492159**, restart Anki and use a supported Anki version. No Anki installation/add-on folder was inspected or changed here.
- Launch the built app yourself. Grant Motion & Fitness only if you want Lab data. A direct Terminal launch may attribute that permission to Terminal instead of AirAnki. Accessibility is unnecessary.
- Follow [docs/TESTING.md](docs/TESTING.md): 20 trials per stem gesture held and worn; question/answer, Undo and error tests; open-case streaming duration; 10 marked case taps; 5 shakes; lid-close behaviour; 10 held-bud comparisons; Anki audio and Music/Spotify coexistence.
- **Unverified:** stem delivery/routing on AirPods Pro 3 firmware 9A348; real motion rates and open/closed-case streaming; permission attribution; reconnect behaviour; UI/sound presentation; media competition/card audio; actual grading/Undo in a live Anki instance. Source and mock protocol checks do not establish hardware or live integration behaviour.
- Undo is ignored outside review, including after the last card finishes a deck; use Anki's own Undo there. Within review it operates on Anki's global undo entry, so avoid unrelated edits. These limits appear in the guide and test sheet.
- XCTest itself could not execute on this machine. The equivalent self-test executable passed; no Xcode/global installation was performed.

Existing research was preserved. All development writes stayed inside this repository. No app launch requiring a human, Bluetooth reconfiguration, system/TCC change, login item, account, payment, post/message, hosted/production service, .env edit, sudo, brew install, global install or remote Git operation occurred. Public source retrieval was read-only; commits are local only.
