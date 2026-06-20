# Ship HER offline briefing onto 32-bit ARM (embedded edge developers)

This is the **embedded / 32-bit ARM (`armv7`) extension** of
[QUICKSTART.md](QUICKSTART.md). Read the QUICKSTART first — it walks you from an
empty `flutter create` to a working offline Akita whiteout briefing in ~15
minutes on a normal desktop. **Everything there still applies.** This doc adds
the one thing the embedded target needs that the desktop path does not: how to
get that same briefing running on **car-class 32-bit ARM hardware** (IVI head
units, Yocto images, single-board ARM), and an honest statement of what works
today versus what is still staged.

It is written for the edge developer who runs
`flutter build bundle --target-platform linux-arm` against an embedded target
and hits a wall. If that is you, the path below is real and you can start now.

## What works today, and what is staged (read this first)

This on-ramp is deliberately split into two layers, because they have different
levels of proof:

| Layer | Status | Proof |
|---|---|---|
| **The pure-Dart honest-decision core** (`pretrip_decision_advisor` + the offline path) | **Runs on `armv7` NOW** | A captured run on genuine 32-bit ARM — see §2 |
| **The Flutter VISUAL render** on `armv7` | **`[GATED]`** on [`flutter/flutter#188063`](https://github.com/flutter/flutter/pull/188063) | Not yet — staged honestly in §4 |

We do not claim the Flutter UI renders on `armv7`. We claim, and have run-SEEN,
that the **decision logic that produces HER briefing** — the part that decides
*wait an hour* versus *go now* — runs offline and deterministically on 32-bit
ARM today. You can build a real product on that layer now (headless service,
serial/CAN output, a non-Flutter front-end) and adopt the Flutter render the day
the gate clears.

> **Honest status:** adoption of these packages is currently zero. This is a
> documented *path to a pull*, not evidence of one. We are writing down the path
> because the wall in §1 is real and the unblock is real — not because anyone is
> using this yet. The doc reaches the cohort only via the public packages/repo —
> a public reference, never a targeted message to any developer; the path from the
> cohort's real entry point (the upstream issue, not a pub.dev search) to here is
> not closed by this build, and adoption may never follow. Acknowledged, not assumed.

---

## 1 — The `linux-arm` wall, the fix, and how to unblock today

### The wall

On an embedded 32-bit ARM target you reach for:

```sh
flutter build bundle --target-platform linux-arm
```

and Flutter stops you:

```
"linux-arm" is not an allowed value for option "target-platform".
```

`flutter_tool` does not (yet) list `linux-arm` (32-bit, `armv7`) as an allowed
build-bundle target platform, and does not key native-asset resolution for it.
`linux-arm64` (64-bit) is allowed; **32-bit `linux-arm` is not.** For car-class
and IVI hardware that is still 32-bit `armv7`, that is a hard stop at the tool
layer — before your code is even considered.

This is tracked publicly at
[`flutter/flutter#187018`](https://github.com/flutter/flutter/issues/187018).

### The fix

[`flutter/flutter#188063`](https://github.com/flutter/flutter/pull/188063) adds
`linux-arm` to the `build bundle` allowed-target list and keys native-assets
resolution for it. **Status: the PR is OPEN and awaiting maintainer review — it
is not merged.** Do not assume it is in your Flutter version; it is not in any
released channel as of this writing. Track the PR for its real state rather than
trusting this sentence.

### Unblock today (carry the patch)

You do not have to wait for the merge to keep moving. Carrying a local patch onto
a Flutter checkout is the ordinary approach for embedded/Yocto Flutter work
(meta-flutter recipes routinely pin and patch the engine/tool):

```sh
# 1. Use a Flutter SDK you control (a git checkout, not a packaged release):
git clone https://github.com/flutter/flutter.git
cd flutter
git checkout <the channel/commit your target is built against>

# 2. Cherry-pick the fix branch onto your checkout (or apply it as a .patch in
#    your Yocto recipe's SRC_URI). Inspect the PR before you carry it:
git fetch https://github.com/flutter/flutter.git refs/pull/188063/head
git cherry-pick FETCH_HEAD        # or: git format-patch -1 FETCH_HEAD && apply in-recipe

# 3. Re-run the tool from THIS checkout:
./bin/flutter build bundle --target-platform linux-arm
```

> **Honest note:** this lets `flutter_tool` accept `linux-arm` as a target so the
> *build* can proceed. It is the tool-layer unblock — the tool *accepting* the
> target (verified at the parse/allowed-list level). We have **not** run
> `flutter build bundle` end-to-end on an `armv7` target ourselves; the §2 proof
> ran the pure-Dart core via the Dart VM, not via `flutter_tool`. Verify #188063's
> live state and your own bundle build. It is **not** a claim that
> the full Flutter render then works on your specific `armv7` board — that is the
> separate, still-`[GATED]` question in §4. The layer that *is* proven on
> `armv7` today, with no patched Flutter at all, is §2.

---

## 2 — The pure-Dart core runs on `armv7` NOW (run-SEEN)

The honest-decision core — `pretrip_decision_advisor` and the offline path that
produces HER briefing — is **pure Dart with zero runtime dependencies.** It does
not need Flutter, a GPU, a display, or a network. So it runs wherever the Dart
VM runs, including genuine 32-bit ARM.

We ran it on `armv7` and looked at the output. The capture is on disk in this
example:

```
_capture/armv7_runnability_proof.txt   (captured 2026-06-20T12:05Z)
```

### What was proven

From that artifact, verbatim:

- **Architecture:** `uname -m` → `armv7l`; the `dart` binary is `ELF 32-bit ARM`
  (`EI_CLASS = 01`, `e_machine = 0x28 = EM_ARM`); `Dart SDK ... on "linux_arm"`.
  This is real 32-bit ARM, not a 64-bit shim.
- **Output:** HER Akita whiteout briefing, **identical to the documented x86_64 reference output** (the QUICKSTART/README briefing) —
  `verdict: waitAdvised`, `peakHazard: severe`, `strength: advisoryStrong`,
  `suggestedDelay: 1:00:00`. Exit code `0`.

```text
=== HER Akita pre-trip briefing (offline, deterministic) ===
verdict: PretripVerdict.waitAdvised
peakHazard: HourHazard.severe
chips:
  - Visibility may drop to ~80 m around 07:00 — whiteout conditions.
  - Conditions improve by about 08:15.
recommendation.strength: RecommendationStrength.advisoryStrong
recommendation.suggestedDelay: 1:00:00.000000
  … (confidenceWindow + rationale lines omitted) …
=== EXIT: 0 ===
```

### Reproduce it yourself

The capture was produced with the Dart `armv7` image under QEMU user-mode
emulation (`qemu-arm` binfmt) on an x86_64 host — so you can reproduce it without
physical ARM hardware:

```sh
# A throwaway pure-Dart project using ONLY the zero-dep advisor:
mkdir armv7_check && cd armv7_check
cat > pubspec.yaml <<'YAML'
name: armv7_check
environment: { sdk: ^3.10.0 }
dependencies: { pretrip_decision_advisor: ^0.2.1 }
YAML
mkdir bin
# bin/akita_armv7_check.dart = the package's end-to-end example main
# (see pretrip_decision_advisor README → "End-to-end: measured source → briefing").

# Run it on emulated 32-bit ARM (needs Docker + qemu-arm binfmt registered):
docker run --rm --platform linux/arm/v7 -v "$PWD":/app -w /app dart:stable \
  sh -c 'dart pub get && dart run bin/akita_armv7_check.dart'
```

The harness is QEMU user-mode emulation. It proves the **Dart VM executes the
core on the `armv7` instruction set** and produces the correct briefing. It does
**not** measure on-hardware GPU/render performance, and emulation timing is not
hardware timing — see §4.

---

## 3 — `pub add` the existing stack and brief on your target

No new packages exist for embedded — you use the **same hosted stack** as the
desktop QUICKSTART. On the layer that is proven today (pure Dart), add them with
`dart pub`:

```sh
dart pub add pretrip_decision_advisor   # 0.2.1 — zero runtime deps, pure Dart
dart pub add pretrip_source_jma         # 0.1.0 — http + advisor, both pure Dart
```

- **`pretrip_decision_advisor` (0.2.1)** — the advisor, the typed
  `PretripBriefing`, and `VisibilityObservation` / `mergeObservedVisibility`.
  **Zero runtime dependencies** → nothing to cross-compile, no native plugin to
  port. This is the part proven on `armv7` in §2.
- **`pretrip_source_jma` (0.1.0)** — `JmaVisibilityProvider`, which turns a live
  JMA AMeDAS reading into a `VisibilityObservation`. Its only runtime
  dependencies are `http` and the advisor — both pure Dart, no native code.

The data path is exactly the three published-package calls from
[QUICKSTART.md §2](QUICKSTART.md) — unchanged on embedded, because none of it
touches the platform:

```dart
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';

// 1. Merge the NOW measurement into the departure-hour slot only.
final merged = mergeObservedVisibility(forecast, observation, departure);
// 2. Brief on the merged forecast — deterministic, offline, no GPU, no network.
final briefing = const SnowAwarePretripAdvisor()
    .brief(forecast: merged, commute: commute, profile: driver);
// 3. Read the typed result out and surface it however your target can.
```

On an embedded target with no display (or before the Flutter render gate
clears), you surface the typed `PretripBriefing` through whatever your hardware
*does* have — a serial line, a CAN frame, a status LED, a headless service, a log
the IVI middleware reads. The decision is already made offline; the front-end is
your choice.

To brief on a **real** AMeDAS reading instead of the demonstration value, call
`JmaVisibilityProvider` (needs a network at fetch time only — the decision after
that is offline). It returns `null` when no fresh in-range reading exists —
the honest "driver's own judgment" outcome, never a fabricated number. See
[QUICKSTART.md §5](QUICKSTART.md) for the live-fetch snippet; it is identical on
embedded.

---

## 4 — The Flutter VISUAL render on `armv7` — `[GATED]`

This is the part we **do not** claim works yet.

Once the `flutter_tool` change in §1 lands (or you carry it as a local patch),
`flutter build bundle --target-platform linux-arm` will be *accepted by the
tool*. That removes the wall in §1. It does **not**, by itself, prove that the
Flutter engine renders your widget tree correctly and fast enough on your
specific `armv7` board.

Two things remain genuinely open, and we will not paper over them:

1. **The visual render on `armv7`** is gated on
   [`flutter/flutter#188063`](https://github.com/flutter/flutter/pull/188063)
   landing (or being carried) **and** an engine/embedder build for your target.
   We have not captured a render of this UI on `armv7`. Treat the QUICKSTART
   screenshot as the *desktop* render; the embedded render is unverified.
2. **Physical-hardware GPU / render performance** is not something the QEMU proof
   in §2 can speak to. Emulation runs the instructions; it does not measure
   frames on your GPU. On-hardware render performance is an open question for
   your board.

**Honest staging — what to do meanwhile:** build on the §2/§3 layer now (the
decision core is proven on `armv7`; surface it through a non-Flutter front-end),
and adopt the Flutter render when the gate clears and you have verified it on
*your* hardware. The decision logic does not change when the UI arrives — you are
adding a view over a `PretripBriefing` you can already compute on the target
today.

---

## 5 — The four honesty rules (binding — carried verbatim)

These are **safety contracts, not UI preferences.** They are enforced by the
packages, identical on desktop and embedded, and you must not relax them — on a
32-bit ARM head unit they matter exactly as much as on a desktop:

1. **Visibility is never estimated** — a source maps absent data to `null`, never
   to a value.
2. **A warning never produces a number** — measurement and warning live on
   separate packages.
3. **An observation is valid for the departure hour only** —
   `mergeObservedVisibility` sets the covering slot and never projects forward.
4. **`null` = the driver's own judgment**, never a fabricated hazard — and we
   never fabricate an "all clear".

And the determinism contract the embedded target relies on most:
**deterministic-offline-once-fed** — given the same typed inputs, the advisor
always produces the same recommendation, with no LLM, no network, and no clock in
the decision path. That is what lets this run in a vehicle when Google Maps has
failed, GPS has dropped, and the network is gone — the worst-case condition this
whole stack is designed for. The advisor is **advisory, not control**: it informs
a departure-timing decision; it does not actuate anything.

The `80 m` Akita value used throughout is a labelled **demonstration** whiteout
value (live Akita visibility in June reads clear). It shows the path that lights
the severe band when the sensor really does read low — which, for a driver in
Akita in winter, it will.

---

## Why this exists

The chain is short and it ends at a person: an embedded edge developer ships
HER offline winter-safety briefing onto her car-class 32-bit ARM hardware, so
that when she sets out in an Akita whiteout — net down, GPS gone — the head unit
can still tell her *wait about an hour*. The wall in §1 is what stops that today;
§2 is the proof the core already runs on the hardware; §1's unblock and §4's
honest staging are how you get the rest of the way.

## Where to go next

- The general 15-minute on-ramp (desktop, with screenshot): [QUICKSTART.md](QUICKSTART.md).
- The full worked reference app: [README.md](README.md).
- The contract + reference advisor: [`pretrip_decision_advisor`](https://pub.dev/packages/pretrip_decision_advisor).
- The `armv7` run capture cited in §2: `_capture/armv7_runnability_proof.txt`.
- The public wall + fix: [`flutter/flutter#187018`](https://github.com/flutter/flutter/issues/187018) (wall) and [`flutter/flutter#188063`](https://github.com/flutter/flutter/pull/188063) (fix, open).
