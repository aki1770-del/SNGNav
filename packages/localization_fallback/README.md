# localization_fallback

One honest position estimate that degrades truthfully from trusted GPS to dead
reckoning to `lost` — so it **never emits a confidently-wrong fix once GPS
becomes untrustworthy**, in a whiteout.

```console
dart pub add localization_fallback
```

## Quickstart (run-verified)

Feed the controller one good fix, then take GPS away. Dead reckoning carries the
position while the confidence radius **grows** — until it crosses the honesty
horizon and the mode becomes `lost`. The radius never shrinks without a trusted
fix.

```dart
import 'package:localization_fallback/localization_fallback.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 8);
  final c = LocalizationController(
    // 8 m/s overrides the conservative 2.0 default to degrade FAST in this
    // whiteout demo; pick a rate that matches your platform's real drift.
    config: const LocalizationConfig(driftRateMetersPerSecond: 8),
    // Back this seam with kalman_dr in real code; here it just holds position.
    deadReckoningSeam: (asOf) =>
        const DeadReckoningEstimate(latitude: 39.7036, longitude: 140.1031),
  );

  // 1. A good, trusted fix.
  print(c.onFix(
    RawFix(latitude: 39.7036, longitude: 140.1031, accuracyMeters: 6, timestamp: t0),
    trust: TrustSignal.trusted,
  )); // gpsTrusted, radius 6m

  // 2. GPS is gone — poll on a tick; radius grows, then we go lost.
  for (final s in [10, 30, 60]) {
    print(c.poll(t0.add(Duration(seconds: s))));
  }
}
```

Real output (`dart run example/main.dart` ships a fuller version):

```
LocalizationEstimate(gpsTrusted, lat: 39.70360, lon: 140.10310, radius: 6m, sinceTrusted: 0s, basis: trustedGpsFix)
LocalizationEstimate(deadReckoning, lat: 39.70360, lon: 140.10310, radius: 86m, sinceTrusted: 10s, basis: deadReckoning)
LocalizationEstimate(deadReckoning, lat: 39.70360, lon: 140.10310, radius: 246m, sinceTrusted: 30s, basis: deadReckoning)
LocalizationEstimate(deadReckoning, lat: 39.70360, lon: 140.10310, radius: 486m, sinceTrusted: 60s, basis: deadReckoning)
```

(The radius keeps growing; with the default 500 m horizon it would tip to `lost`
shortly after — the bundled `example/main.dart` uses a tighter 300 m horizon to
show that transition.)

See [`example/main.dart`](example/main.dart) for the full
`gpsTrusted → gpsSuspect → deadReckoning → lost → reconverge` arc.

## What it is

A small, synchronous state machine. You give it:

- a stream of **raw fixes** (`RawFix`: lat, lon, accuracyMeters, timestamp,
  optional speed/heading), and
- per fix, a **trust signal** (`TrustSignal.trusted/suspect/failed`) that
  **you compute** — see [Computing the trust signal](#computing-the-trust-signal)
  below; no package in this catalog computes it for you, and
- optionally a **dead-reckoning seam** (`DeadReckoningSeam`) that you back with a
  dead-reckoning engine such as [`kalman_dr`](../kalman_dr), and
- optionally vehicle speed/heading on the fix.

It hands back exactly one `LocalizationEstimate` per input:

| field | meaning |
|---|---|
| `latitude` / `longitude` | the best position |
| `confidenceRadiusMeters` | "the dot could be anywhere within this circle" |
| `mode` | `gpsTrusted` / `gpsSuspect` / `deadReckoning` / `lost` |
| `secondsSinceTrustedFix` | how stale the last trusted fix is |
| `basis` | which input produced the position (`EstimateBasis`) |

### The state machine

```
              suspect verdict                   failed verdict
 gpsTrusted ───────────────► gpsSuspect          (or no fix on poll)
     ▲    │                       │                       │
     │    │ a TRUSTED fix         │  radius > maxTrustworthy
     │    │ returns (reconverge   │  OR seconds > maxDead  │
     │    │  — the only way the   ▼                        ▼
     │    └─► deadReckoning ──► lost ◄─────────────────────┘
     └────────── a TRUSTED fix returns ──────────────────────┘
```

`mode` follows that fix's `TrustSignal` (a `failed` fix goes straight to
`deadReckoning`, never through `gpsSuspect`) and the radius/time horizons; there
is no hidden gap-timer. It is **not** memoryless, though, and deliberately so:
the confidence radius is monotonic, and once the controller is `lost` it stays
`lost` until a fresh, newer **trusted** fix reconverges — a backwards or
out-of-order `poll`, a stale/duplicate fix, or a `suspect`/`failed` fix can
never silently un-lose you. The only arrow back to `gpsTrusted` is a trusted
fix. Drive degradation during a blackout by calling `poll(now)` on a tick; the
radius grows each call and reaches `lost` at the horizon.

`deadReckoning` drives position from the seam and **grows** the confidence
radius with a documented model:

```
radius = lastTrustedAccuracy + driftRate * secondsSinceTrustedFix
```

(`driftRate` is `driftRateMetersPerSecond`, except while the dot is **frozen at
last-known** with no seam wired — there it is floored by the last fix's ground
speed so the circle still plausibly contains a vehicle that kept moving. The
radius is also floored to never drop below the seam's own accuracy claim, and
forced monotonic.) Past `maxTrustworthyRadiusMeters` or `maxDeadReckoningSeconds`
the mode becomes `lost` — which **still returns the last-known position and a
radius**, but says plainly that this is a guess. The same radius horizon applies
to a trusted fix: if a `trusted` fix's OWN reported accuracy already exceeds
`maxTrustworthyRadiusMeters`, it is adopted as the baseline but presented as
`lost`, never as a confident dot.

## The honesty contract

These are enforced in code and proven in
[`test/`](test/localization_controller_test.dart):

1. **Monotonic radius.** While not `gpsTrusted` and a position basis exists,
   `confidenceRadiusMeters` is non-decreasing. You cannot get more certain
   without a trusted fix — not from a slowly-drifting seam, not from a seam that
   under-reports its own accuracy, not from an out-of-order or stale "trusted"
   fix (one whose timestamp is not newer than the last is ignored, not snapped
   to). (The one exception is the bootstrap "nothing seen yet" state, which
   reports an *infinite* radius; the first coarse guess after it is finite —
   both are non-confident `lost`.)
2. **`lost` is first-class, honest, and terminal until re-acquisition.** It
   still returns a position + radius, but `mode == lost` means "we do not know
   where you are" — never a fabricated confident dot. Once `lost`, the
   controller stays `lost` until a fresh, newer **trusted** fix reconverges: no
   backwards-in-time or out-of-order `poll`, no stale/duplicate fix, and no
   `suspect`/`failed` fix can silently restore confidence we have lost.
3. **Every estimate carries its `basis`** so the app can be honest to the driver
   about where the dot came from.
4. **No silent smoothing.** A `suspect`/`failed` fix is never blended into the
   position as if trusted — a wild, confidently-labelled jump is ignored, and
   non-finite geometry is forced to `failed` even if the caller marks it
   trusted.

## Honesty bounds

- This is **advisory**. It is not anti-spoofing and not a survey-grade fix.
- **Trusted ≠ correct.** "Trusted" only reflects the trust signal you fed in;
  this package does not verify GPS, it orchestrates the handoff once you have.
- It **cannot create information GPS did not provide.** Dead reckoning only
  carries a prior position forward; this package's job is to **degrade that
  truthfully** — to grow the radius and reach `lost` honestly — not to invent
  certainty.
- The horizons (`driftRateMetersPerSecond`, `maxTrustworthyRadiusMeters`,
  `maxDeadReckoningSeconds`) are conservative defaults; tune them to your
  platform's real drift. When unsure, prefer admitting `lost` early over showing
  a confident wrong dot.

## Design

- **Pure Dart, zero runtime dependencies, no FFI, no Flutter.** The core runs on
  32-bit ARM (`armv7`) car-class hardware.
- **Decoupled by seams.** It computes neither position trust nor dead reckoning
  — you wire those in via the trust signal and the dead-reckoning seam. A
  dead-reckoning engine such as [`kalman_dr`](https://pub.dev/packages/kalman_dr)
  fits the DR seam directly. The trust verdict you compute yourself (below).

### Why this exists

In the compound-failure worst case — GPS fails, maps fail, whiteout, "the driver
does not see where she is" — an app must still show a position and decide
guidance **after GPS becomes untrustworthy**. A confidently-wrong dot sends the
driver off a snowy road. A dead-reckoning stream
([`kalman_dr`](https://pub.dev/packages/kalman_dr)) existed, but nothing
orchestrated the handoff with honest, growing uncertainty. This package is that
handoff: one estimate, degrading truthfully, that would rather say "lost" than
lie.

## Computing the trust signal

This package does **not** compute trust. You can either compute it yourself from
the worked assessment below, or take it from
[`position_integrity`](https://pub.dev/packages/position_integrity), which is on
pub.dev and does exactly this job.

Its `PositionIntegrityMonitor.update(fix)` returns an `IntegrityVerdict` whose
`.status` is an `IntegrityStatus` — `trusted` / `suspect` / `failed` — the same
three cases, by the same names, as our [`TrustSignal`]:

```dart
final verdict = monitor.update(fix);
final trust = switch (verdict.status) {
  IntegrityStatus.trusted => TrustSignal.trusted,
  IntegrityStatus.suspect => TrustSignal.suspect,
  IntegrityStatus.failed  => TrustSignal.failed,
};
controller.onFix(rawFix, trust: trust);
```

**Read its `KNOWN_LIMITATIONS.md` before you rely on it.** It is honest about a
real bound that matters here: a moderate multipath offset can still read
`trusted`. `trusted` means *no gate fired*, not *this position is correct*.

> **Corrected in 0.1.4.** Up to and including 0.1.3 this section told you no such
> published package existed. That was **true when 0.1.3 was published on
> 2026-07-14** and stopped being true on **2026-07-23**, when `position_integrity`
> was published — and we left the stale sentence standing for sixteen days. If you
> read 0.1.3 and wrote your own trust computation because we told you there was
> nothing to use, that cost was ours.

`onFix` therefore defaults to `TrustSignal.trusted`: **it believes the fix.** That
default is usable (a controller that trusted nothing could never anchor) but it is
not safe — a multipath or teleported fix becomes a confident dot, and guidance is
spoken from it. Compute a verdict from what your locator already reports:

```dart
// oracle:placeholders controller, fix, lastFix
import 'dart:math' as math;

/// Decide whether a raw fix can be believed. Copy this, then tune the numbers
/// to your receiver and vehicle.
TrustSignal assess(RawFix fix, RawFix? previous) {
  // 1. Geometry that cannot be true.
  if (!fix.hasFiniteGeometry) return TrustSignal.failed;

  // 2. Accuracy the receiver itself does not believe.
  final acc = fix.accuracyMeters;
  if (acc == null || acc > 100) return TrustSignal.suspect;

  // 3. A jump no vehicle could have made (multipath / teleport).
  if (previous != null) {
    final seconds =
        fix.timestamp.difference(previous.timestamp).inMilliseconds / 1000.0;
    if (seconds > 0) {
      final impliedKmh = _metresBetween(previous, fix) / seconds * 3.6;
      if (impliedKmh > 250) return TrustSignal.suspect;
    }
  }
  return TrustSignal.trusted;
}

/// Great-circle distance in metres.
double _metresBetween(RawFix a, RawFix b) {
  const earthRadiusM = 6371000.0;
  double rad(double d) => d * math.pi / 180.0;
  final dLat = rad(b.latitude - a.latitude);
  final dLon = rad(b.longitude - a.longitude);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(a.latitude)) *
          math.cos(rad(b.latitude)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return 2 * earthRadiusM * math.asin(math.min(1.0, math.sqrt(h)));
}

// Then pass the verdict with every fix:
controller.onFix(fix, trust: assess(fix, lastFix));
```

Tune the thresholds to your receiver and vehicle. The point is that *some* verdict
is computed — the failure this package exists to prevent begins with believing a
fix you never checked.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
