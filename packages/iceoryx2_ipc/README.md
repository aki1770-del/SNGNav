# iceoryx2_ipc

Road-condition samples over [Eclipse iceoryx2](https://github.com/eclipse-iceoryx/iceoryx2)
shared memory, classified by **the same rule the KUKSA path uses**.

A publisher writes a `sngnav_road_friction_t` into shared memory. This package
receives it and hands the value to `RoadFriction.classify` from
[`kuksa_dart_sdk`](https://pub.dev/packages/kuksa_dart_sdk), so a consumer
reading friction over iceoryx2 and a consumer reading it over KUKSA cannot
disagree about whether a road is icy. There is no second threshold table here —
a second place to decide "the road is fine" is a second place to be wrong.

```dart
import 'package:iceoryx2_ipc/iceoryx2_ipc.dart';
import 'package:kuksa_dart_sdk/kuksa_dart_sdk.dart'; // RoadGrip lives here, not in this package

final source = Iox2RoadFrictionSource.open();
final bridge = RoadFrictionBridge(source);

final sample = bridge.tryNext();
if (sample != null) {
  switch (sample.grip) {
    case RoadGrip.icy:     // positively measured as ice
    case RoadGrip.reduced: // wet, slush, loose
    case RoadGrip.grip:    // normal
    case RoadGrip.unknown: // NOT a claim that the road is fine
  }
}
```

Run the demo:

```
./tool/build_iceoryx2.sh        # builds libiceoryx2_ffi_c.so
make -C native                  # builds the publisher
./native/road_friction_publisher &
dart run example/road_friction_glance.dart
```

## Absence is not grip

The wire carries a `quality` byte. `quality == 0` means **not measured** — it is
never a friction value, and the friction field is ignored when it is set. That
becomes a `null` percent in Dart, and `classify(null)` returns
`RoadGrip.unknown`.

`RoadGrip.unknown` answers `false` to *both* `isIcy` and `isNotIcy`. That is
deliberate. Absence of a reading is not a claim about the road in either
direction, and a surface that renders it as "clear" is the exact failure this
package is shaped against — a confident wrong answer, not a missing one.

The scale is **percent, 0–100**, per VSS, not a 0.0–1.0 ratio. An ESC on black
ice reports something like `18.0`. Read as a ratio it becomes a clear road.

## What this package has NOT been shown to do

Stated here rather than in a commit message, because a consumer reads this file.

- **Host Linux x86_64 only.** That is the only architecture on which the C and
  Dart struct layouts have been compared to each other.
- **Not verified on the IVI target.** Nothing here has run on the real head
  unit.
- **Not verified on aarch64 at runtime.** The C half of the layout has been
  measured under cross-compilation elsewhere in this repo; the *Dart* half has
  not, because there is no aarch64 Dart SDK on the host that ran it. The pair
  has never been compared on the architecture the IVI target runs.
  Run `test/abi_layout_test.dart` on the target before trusting it there.
- **Not usable across processes on Android.** Upstream iceoryx2's Android
  support is inter-thread only.
- **No version symbol exists in iceoryx2's C API.** Measured by RSE on the
  built `libiceoryx2_ffi_c.so`, 2026-09-12: zero exported symbols matching
  version / abi / revision / semver across 660 `iox2_*` symbols. A stale
  iceoryx2 cannot be detected at `dlopen` time. iceoryx2 does compare a payload
  type name, size and alignment at service-open, which catches a **width**
  change — it does not catch a **field reorder** at constant width.
- **Not published.** `publish_to: none`. This is an integration, not a release.
- **The service name is machine-global, and this package does not own it.**
  `SNGNAV_ROAD_FRICTION_SERVICE` is the fixed string `sngnav/road_friction`,
  compiled into both halves. **Any** other process on the same host publishing
  to that name is publishing into the same service, and a subscriber receives
  the interleaved union of all of them.

  Measured 2026-09-12, two publishers started three seconds apart, one
  subscriber:

  ```
  49   50.0%         reduced
  34   18.0%         icy
  50   18.0%         icy
  35   not measured  unknown
  ```

  Sequence numbers go **backwards**, because they are two independent counters.
  Every individual sample still classified correctly — the transport and the
  layout are not at fault — but two consequences are real and must be designed
  around before this is relied on:

  1. **Sequence gaps cannot be used to detect dropped samples** while more than
     one publisher exists. A "gap" may simply be the other publisher's turn.
  2. **A foreign or stale publisher's reading is delivered as a current one**,
     indistinguishably. Nothing in the payload identifies which process wrote
     it.

  Today that is a development-environment hazard rather than a shipped one —
  there is one publisher on a real target. It is recorded because a
  single-publisher assumption is currently enforced by nothing, and the failure
  it produces is a plausible wrong reading, not an error.

## What you are binding to, and what the build needs

- **The pin is a commit on `main`, not a release.** `tool/build_iceoryx2.sh`
  pins iceoryx2 to `05a3a8fa` (2026-09-11). Every iceoryx2 release to date is
  flagged prerelease — 17 of 17 as of 2026-09-12, newest `v0.9.3` from
  2026-07-08, two months behind the pin. There is no stable line to track yet,
  and the C API exports no version symbol (0 of 660), so if the pin moves and
  you keep an old `.so`, nothing at `open` will tell you.
- **The build fetches over the network.** Nothing from iceoryx2 is vendored; the
  script does a bare-SHA shallow fetch from GitHub and re-verifies the SHA after
  checkout. If that SHA ever becomes unfetchable the package is unbuildable. To
  build from a local clone or a mirror instead, set `SNGNAV_ICEORYX2_URL`
  (`build_iceoryx2.sh:31`); `SNGNAV_ICEORYX2_BUILD_DIR` and
  `SNGNAV_ICEORYX2_PROFILE` are the other two knobs.
- **A Rust toolchain and a C compiler are required on the machine that builds.**
  Consumers who cannot have either cannot use this package today.

## The layout check

`sngnav_road_friction_t` is the one layout in this package declared twice, in C
and in Dart. A disagreement between the two does not crash — it produces a
plausible number, which `classify` will turn into a grip verdict.

`test/abi_layout_test.dart` runs
`../driving_conditions/tool/abi_layout_check.dart` over both declarations and
compares **per-field offset and width**, matched by name, then size and
alignment. A size-and-alignment-only check is not enough, and that is measured
rather than assumed: on 2026-09-12 such a check passed a deliberate field
reorder on a six-scalar struct, because every permutation had the same size.

The struct carries three named `reserved` bytes rather than `uint8_t
reserved[3]`. The wire is byte-identical either way (both are 24 bytes, align 8,
fields at 0/8/16/20); the array form is used because the layout checker refuses
any C field containing `[` and would have exited "could not verify" on the one
struct it exists for.

## Tests

| File | Proves |
|---|---|
| `test/road_friction_bridge_test.dart` | classification, on a fake. Says **nothing** about the transport. |
| `test/abi_layout_test.dart` | the Dart and C declarations agree, field by field, on this host. |
| `test/cross_process_wire_test.dart` | bytes actually cross a process boundary. |

The wire test **fails** rather than skips when the shared object or publisher is
absent, and says `UNVERIFIED`. A skipped transport test and a passing one look
identical in a CI summary.

## Licence

Apache-2.0 — the `LICENSE` file, every `SPDX-License-Identifier` header, and this
line agree.

This differs from the rest of the SNGNav catalog, which is BSD-3-Clause. It is
deliberate: the FFI layer takes the opaque-handle path an earlier, unmerged
Dart binding for iceoryx2 found first — contributed to a repository that is
dual-licensed Apache-2.0 OR MIT, so his work sits under both — and credits its
author in the file headers. That credit said "Apache-2.0 on both sides", which
narrowed his side and, for a few hours on
2026-09-12 it was false — this package briefly shipped a BSD-3-Clause `LICENSE`
copied from the monorepo root, which made pub.dev stop refusing the package and
made the crediting sentence untrue at the same time. A refusal became a
contradiction. Corrected the same evening.
