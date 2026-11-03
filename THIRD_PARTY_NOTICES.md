# Third-party notices

AirAnki has no third-party Swift package dependencies.

## PodMouse

`AirAnki/Sources/AirAnki/StemInput.swift` adapts the silent AVAudioEngine/AVAudioPlayerNode loop, MPRemoteCommandCenter mappings, Now Playing metadata, playback-state restoration and target-removal approach in [PodMouse's StemButtons.swift](https://raw.githubusercontent.com/tony1010-dev/PodMouse/main/Sources/StemButtons.swift), accessed 2026-10-30. AirAnki adds error propagation, explicit silence initialization, callback logging, lifecycle guards and audio-route recovery.

[Upstream license](https://raw.githubusercontent.com/tony1010-dev/PodMouse/main/LICENSE):

```text
MIT License

Copyright (c) 2026 tony1010-dev

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## AirClicker

[AirClicker](https://github.com/Harelzx/airclicker) by Harelzx / Harel Aronovich supplies the MIT-licensed `FlickListener` algorithm ported into `AirAnki/Sources/AirAnkiCore/FlickDetector.swift`. The supplied snapshot is `research/data/airclicker-main.swift.txt`; upstream is [main.swift](https://raw.githubusercontent.com/Harelzx/airclicker/main/Sources/AirClicker/main.swift). The port preserves gravity-projected yaw, burst thresholds, horizontal checks, sensitivity scales, short-turn wind-up rejection, repeat/return suppression and direction reversal. AirAnki adds measured-interval adaptation for 25 Hz, first-sample integration, a limited compact-impulse path, held flicks, shake detection/cooldown, structured traces and deterministic replay. `FlickInput.swift` also adapts the motion lifecycle and no-data watchdog. No synthetic-key or Accessibility code is included. Tuning details are in `CODEX_REPORT.md`.

[Upstream license](https://raw.githubusercontent.com/Harelzx/airclicker/main/LICENSE), accessed 2026-10-30:

```text
MIT License

Copyright (c) 2026 Harel Aronovich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## AnkiConnect

[AnkiConnect](https://git.sr.ht/~foosoft/anki-connect) is a separately installed Anki add-on, not bundled or linked into AirAnki. Its public documentation and plugin source were inspected to verify HTTP API semantics. No GPL/AGPL implementation code was copied, translated or included. AirAnki's HTTP clients and tests were independently written against the observed protocol. Protocol names and field names are used for interoperability. Historical API evidence and release distinctions are in `docs/codex-legacy-fix-report.md` and `docs/codex-v1-build-report.md`; current changes and checks are in `CODEX_REPORT.md`.
