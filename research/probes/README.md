# Passive macOS feasibility probes

**Status: untested — needs user.** Both Swift files compiled successfully on **2026-10-30** with the already installed Command Line Tools. Neither binary was executed, and no media or Bluetooth observations were made. Compilation establishes syntax/linking only; permissions and hardware behavior remain untested.

These are throwaway research probes, not an Anki application. By source inspection they only observe and print: no synthetic keys, media-command handlers, audio playback, Anki API calls, device connections, GATT writes, pairing/reset operations or settings changes. Each exits after 90 seconds. The media observer leaves events untouched; the scanner asks CoreBluetooth to scan. **Qualification:** OS-mediated scanning is not a guarantee of electrically passive radio reception; the OS can manage scan traffic. [Apple scanning documentation](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/scanforperipherals(withservices:options:).md), accessed 2026-10-30.

## Build locally

Run these commands from the repository root. They use the existing compiler, keep build output/module cache inside this directory, and install nothing. If `xcrun --find swiftc` fails, stop; this research does not require installing developer tools.

```sh
xcrun --find swiftc
mkdir -p research/probes/.build/module-cache
xcrun swiftc -module-cache-path research/probes/.build/module-cache research/probes/media_events.swift -o research/probes/.build/media-events
xcrun swiftc -module-cache-path research/probes/.build/module-cache research/probes/apple_advertisements.swift -o research/probes/.build/apple-advertisements -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker research/probes/ProbeInfo.plist
```

The embedded plist declares a Bluetooth usage description; the scanner checks authorization **before** constructing the manager. If authorization is not already allowed, it exits with status 2 rather than requesting access. The media probe similarly preflights existing observation/Accessibility authorization without asking for it. **Untested:** whether macOS attributes a command-line binary to Terminal or its own identity on the user's setup. A status-2 exit is an inconclusive permission result, not evidence against AirPods support. No automatic grant/retry or settings-change procedure is included. Sources: [CoreBluetooth authorization](https://developer.apple.com/documentation/corebluetooth/cbmanager/authorization-swift.type.property.md), [listen-event preflight](https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess().md), accessed 2026-10-30.

## 1. Observe exposed system media events

User-run command, **not run during research**:

```sh
./research/probes/.build/media-events
```

Use only an already connected device, with its existing settings. Record the AirPods model, macOS version, current output device, ear-detection setting and foreground/playing app. First press a normal keyboard media key as a positive control if available. Then try separated single/double/triple stem presses, with at least two seconds between intended gestures. Test worn and held states separately if convenient. Do not hold the case setup control or change pairing.

**Expected output / untested decoding:** elapsed seconds, a candidate media-key name, raw phase, repeat flag and `data1`. The subtype-8/key-code decoding follows the conventional macOS system-key layout used by media-key tooling. A down and up record can describe **one** action; do not count them as two activations. The observer prints no ordinary typed keys. Relevant references: [MediaKeyTap](https://github.com/nhurden/MediaKeyTap), [Hammerspoon system-key events](https://www.hammerspoon.org/docs/hs.eventtap.event.html), [Apple event monitoring](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html), accessed 2026-10-30.

**Interpretation:** a printed event establishes visibility in this event path for this setup only. Silence is inconclusive: Bluetooth commands can follow the Now Playing route instead. This probe deliberately does **not** claim Now Playing, suppress playback, or prevent Music from opening; those effects remain normal OS behavior. Testing `MPRemoteCommandCenter` ownership would require a separate playback-capable experiment, beyond this passive probe. Sources: [Apple remote-event requirements](https://developer.apple.com/documentation/mediaplayer/handling-external-player-events-notifications.md), [PodMouse stem handler implementation](https://raw.githubusercontent.com/tony1010-dev/PodMouse/main/Sources/StemButtons.swift), accessed 2026-10-30.

## 2. Observe Apple manufacturer advertisements

User-run command, **not run during research**:

```sh
./research/probes/.build/apple-advertisements
```

If Bluetooth is already authorized and powered on, the probe requests unfiltered foreground discovery with duplicate observations enabled. It does not enable Bluetooth or request a connection. It logs Apple company ID `0x004C` observations, elapsed time, a session-local device number, RSSI, data length and the first 13 manufacturer-data bytes. Full peripheral UUIDs and the trailing 16-byte payload are not printed.

**Tentative decoder:** for the documented 29-byte `4c 00 07 19 …` layout only, it prints byte 10 as `candidate-lid-byte`, plus `low3` and `bit3`. These are **not asserted open/closed states**. AirPodsDesktop treats bit 3 as closed, while airpods-notify documents a conflicting polarity. The number assigned to a discovered peripheral is not a permanent identity; a nearby device or changing identifier can appear as another number. Sources: [packet layout](https://raw.githubusercontent.com/SpriteOvO/AirPodsDesktop/main/Source/Core/AppleCP.h), [decoder](https://raw.githubusercontent.com/SpriteOvO/AirPodsDesktop/main/Source/Core/AppleCP.cpp), [conflicting protocol notes](https://github.com/fischejo/airpods-notify/blob/master/doc/proximity_protocol.md), accessed 2026-10-30.

Suggested human procedure (**proposed, not performed**):

1. Record exact case/earbud models, OS, existing connection state, occupancy and relative distance. Leave Bluetooth/settings alone.
2. Observe an idle interval, then slowly open/close the case. Note each physical action time against the log's elapsed seconds. Do not press/hold/double-tap any setup control.
3. Repeat at least 20 cycles for each convenient state: both buds in the case, one bud in, and empty. Ordinary removal/replacement of buds is sufficient; do not pair or reset anything. Keep unrelated Apple devices stationary if possible.
4. Compare candidate field transitions with the human record. Count missing, duplicate, delayed and unrelated observations. Repeated identical packets are not repeated lid actions.
5. Report medians/range only if timestamps were actually recorded. A missing close packet, a burst on opening or a disappearing device is not proof of a reliable close event.

**Limits / inference:** Apple manufacturer data can include devices other than AirPods. Packet layouts may vary; the decoder intentionally rejects other lengths. No packets could mean permission/radio filtering, no advertising, OS batching, wrong hardware assumptions or an unavailable device. The 2020 macOS visibility result is historical evidence, not a current guarantee. [BTLEmap paper](https://wisec2020.ins.jku.at/proceedings/wisec20-6.pdf), accessed 2026-10-30.

## Proposed results sheet

No result rows have been filled because no runtime test occurred.

| Probe / model / OS | Wear or case occupancy | Existing ear detection / audio owner | Intended action / time | Observed command or bytes / time | Miss / duplicate / false event | Notes |
| --- | --- | --- | --- | --- | --- | --- |

For stem testing, a proposed first gate is 30 trials of each logical gesture plus idle/card-audio/app-switch observations. Report reliability separately for each state; do not average away a failure when held in the hand. Logs can be redirected into `research/probes/*.log`, which is ignored, if the user chooses to retain them. No logs exist from this research.

## Stop and cleanup

Ctrl-C stops either probe; otherwise it exits automatically. No daemon or background login item is installed by these files. `.build/` and `*.log` are ignored. Do not interpret successful compilation, permission preflight or scanner startup as an AirPods compatibility test.
