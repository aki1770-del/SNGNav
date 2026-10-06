# sngnav_road_friction_ipc

**sngnav_road_friction_ipc for Eclipse iceoryx™**

Road-condition samples over [iceoryx2™](https://github.com/eclipse-iceoryx/iceoryx2)
shared memory, classified by **`RoadFriction.classify` from `kuksa_dart_sdk`**, the same rule that package
applies to friction read over Eclipse KUKSA™. The rule is `kuksa_dart_sdk`'s, not the Eclipse KUKSA™ project's.

A publisher writes a `sngnav_road_friction_t` into shared memory. This package
receives it and hands the value to `RoadFriction.classify` from
[`kuksa_dart_sdk`](https://pub.dev/packages/kuksa_dart_sdk), so a consumer
reading friction over iceoryx2™ and a consumer reading it over KUKSA™ cannot
disagree about whether a road is icy. There is no second threshold table here —
a second place to decide "the road is fine" is a second place to be wrong.

```dart
import 'dart:io';

import 'package:kuksa_dart_sdk/kuksa_dart_sdk.dart'; // RoadGrip lives here, not in this package
import 'package:sngnav_road_friction_ipc/sngnav_road_friction_ipc.dart';

void main() {
  // The path tool/build_iceoryx2.sh prints as ICEORYX2_LIB (see below).
  final libraryPath =
      Platform.environment['ICEORYX2_LIB'] ?? 'libiceoryx2_ffi_c.so';
  final source = IpcRoadFrictionSource.open(libraryPath: libraryPath);
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
  bridge.dispose();
}
```

`open()` with no arguments looks for `libiceoryx2_ffi_c.so` on the loader path, and `tool/build_iceoryx2.sh` does not install it there. Pass the `ICEORYX2_LIB` path that script prints: `IpcRoadFrictionSource.open(libraryPath: ...)`. If the library cannot be loaded, `open()` throws, naming the path.

If no publisher is running, `open()` still succeeds and `tryNext()` returns `null`. Nothing in this package reports a publisher that is absent or has stopped: `null` means only that no new sample arrived.

Run the demo:

```
./tool/build_iceoryx2.sh        # builds libiceoryx2_ffi_c.so, prints ICEORYX2_LIB=<path>
make -C native                  # builds the publisher
./native/road_friction_publisher 200 &   # ~40 s of samples, then exits
dart run example/example.dart
```

Run these from a clone of the repository, not from the pub cache: the Makefile writes the publisher binary and `native/.iceoryx2.env` into the package directory. The first run fetches iceoryx2™ and builds it with cargo into `~/.cache/sngnav/iceoryx2` (about 360 MB on the one host measured). Set `SNGNAV_ICEORYX2_BUILD_DIR` to put it elsewhere.

A run leaves iceoryx2™'s files on the host, and this package removes none of
them. Measured on the one host: after the publisher exits by itself or on
SIGTERM, one file stays in `/dev/shm` (`iox2_…global_mgmt`, 16 bytes) and the
directory `/tmp/iceoryx2` stays with empty `nodes` and `services`
subdirectories. After SIGKILL, the service's shared-memory segments
(`/dev/shm/iox2_*.data`, `iox2_*.dynamic`) and the node's files under
`/tmp/iceoryx2` stay as well.

The program at the top of this page reads the library path from `ICEORYX2_LIB`.
After the steps above, in the package directory, this sets it to the library
the publisher was linked against:

```
export ICEORYX2_LIB="$(sed -n 's/^ICEORYX2_LIB=//p' native/.iceoryx2.env)"
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
  That test needs `packages/driving_conditions/tool/abi_layout_check.dart` from
  the SNGNav repository, which is not in this package's archive. Run it from a
  clone of the repository. Run from the pub cache, it fails as UNVERIFIED.
- **Not usable across processes on Android.** Upstream iceoryx2™'s Android
  support is inter-thread only.
- **No version symbol exists in iceoryx2™'s C API.** Measured by RSE on the
  built `libiceoryx2_ffi_c.so`, 2026-09-12: zero exported symbols matching
  version / abi / revision / semver across 660 `iox2_*` symbols. A stale
  iceoryx2™ cannot be detected at `dlopen` time. iceoryx2™ does compare a payload
  type name, size and alignment at service-open, which catches a **width**
  change — it does not catch a **field reorder** at constant width.
- **First release, 0.0.1.** Verified only on host Linux x86_64, within the bounds above.
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

  This package assumes one publisher per host and enforces nothing. It has not
  run on any vehicle target, so no target has been shown to have only one. The
  bundled `native/road_friction_publisher` sends a scripted loop of fixed values
  (80 %, 50 %, 18 %, not measured) stamped with the current time. It is a demo,
  not a sensor. With no argument it runs until stopped. Do not leave it running
  on a host where a real publisher uses `sngnav/road_friction`: its readings
  arrive as current ones, and nothing in the payload tells them apart.

## What you are binding to, and what the build needs

- **The pin is a commit on `main`, not a release.** `tool/build_iceoryx2.sh`
  pins iceoryx2™ to `05a3a8fa` (2026-09-11). Every iceoryx2™ release to date is
  flagged prerelease — 17 of 17 as of 2026-09-12, newest `v0.9.3` from
  2026-07-08, two months behind the pin. There is no stable line to track yet,
  and the C API exports no version symbol (0 of 660), so if the pin moves and
  you keep an old `.so`, nothing at `open` will tell you.
- **The build fetches over the network.** Nothing from iceoryx2™ is vendored; the
  script does a bare-SHA shallow fetch from GitHub and re-verifies the SHA after
  checkout. If that SHA ever becomes unfetchable the package is unbuildable. To
  build from a local clone or a mirror instead, set `SNGNAV_ICEORYX2_URL`
  (`build_iceoryx2.sh:31`); `SNGNAV_ICEORYX2_BUILD_DIR` and
  `SNGNAV_ICEORYX2_PROFILE` are the other two knobs.
- **`git`, a Rust toolchain and a C compiler are required on the machine that
  builds.** Consumers who cannot have them cannot use this package today.
  iceoryx2™ at the pin declares `rust-version = "1.89"` (its workspace
  `Cargo.toml`, inherited by the `iceoryx2-ffi-c` crate the script builds).
  This package's build has been run with Rust 1.94.1 only.

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
Dart binding for iceoryx2™ found first — contributed to a repository that is
dual-licensed Apache-2.0 OR MIT, so his work sits under both — and credits its
author in the file headers. Before this first release, a draft carried a
BSD-3-Clause `LICENSE` copied from the repository root, contradicting the
Apache-2.0 headers. It was corrected before publication; no published version
carried it.

Eclipse, iceoryx, iceoryx2 and KUKSA are trademarks of Eclipse Foundation AISBL.
This package is not part of the Eclipse iceoryx™ or Eclipse KUKSA™ projects and is not
endorsed by either.
`kuksa_dart_sdk`, which supplies the classification rule, is by the same author and is not part of the Eclipse KUKSA™ project either.
