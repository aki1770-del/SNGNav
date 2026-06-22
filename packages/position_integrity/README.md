# position_integrity

> **0.1.0. The calibration-free floor: turn a fused location stream into a trust verdict.**

The platform tells you GPS **accuracy**. It never tells you when GPS has started
**lying**. In a snow-loaded urban canyon a reflected signal can teleport the dot
200 m onto the next street — carrying a perfectly normal accuracy number. A
navigation app that believes it issues a wrong-street turn at the worst possible
moment.

`position_integrity` is the decision layer we're not aware of any pub.dev package
filling: wrap your fused location stream, hand each fix to the monitor, and act
on a first-class **integrity verdict** — `trusted` / `suspect` / `failed`, plus a
source recommendation (`gps` = keep current / `deadReckoning` / `hold`). It is
the upstream **trigger** that tells the rest of your stack *when to stop
believing GPS* and fall back to dead reckoning.

Pure Dart. Offline. Deterministic. No motion model, no road graph, no network,
no calibration — it runs on the `latitude / longitude / accuracy / timestamp`
every platform already exposes, so it is cheap on a low-end ARM head unit and
testable with synthetic fixes.

> **This is an advisory floor** for app-level display / source-handoff
> decisions. It is **not a safety-rated function and must not be used as an
> input to automated vehicle control.**

## What it is for

- **Who pulls it:** any Dart/Flutter developer who wraps a `geolocator`
  `Stream<Position>` and needs to **fail safe** under GPS multipath, urban-canyon
  teleports, or a blackout — instead of silently routing a driver off a
  fabricated position.
- **The app it unlocks:** a rural/winter offline nav app that detects when GPS
  has gone from *accurate* to *confidently wrong*, suppresses the bad turn, and
  hands the blue dot off to dead reckoning at the right moment. `geolocator`
  reports an accuracy number, never an integrity decision.

## Quick start

```dart
import 'package:position_integrity/position_integrity.dart';

final monitor = PositionIntegrityMonitor(); // sensible road defaults

// For each fused fix from your location plugin, map it into a PositionFix.
// (geolocator: Position.timestamp was nullable before v12 — use `?? DateTime.now()`;
//  Position.accuracy can be 0 / negative when the platform reports "unknown".)
final verdict = monitor.update(
  PositionFix(
    latitude: pos.latitude,
    longitude: pos.longitude,
    accuracyMetres: pos.accuracy,
    timestamp: pos.timestamp,
  ),
  // OPTIONAL: how fresh your dead-reckoning estimate is, so a fault can
  // recommend a handoff. Omit it and a fault always recommends `hold`.
  deadReckoningAge: deadReckoning.age,
);

// Act on STATUS, not on recommendedSource alone (a single suspect keeps `gps`).
switch (verdict.status) {
  case IntegrityStatus.trusted:
    showGpsPosition(pos);
  case IntegrityStatus.suspect:
    showGpsPosition(pos, caution: true);
  case IntegrityStatus.failed:
    if (verdict.recommendedSource == SourceHint.deadReckoning) {
      switchToDeadReckoning();
    } else {
      holdLastKnownGood(); // SourceHint.hold
    }
}
// verdict.reason         -> 'impossible speed: 201 m/s (max 50)'
// verdict.violatedGates  -> {GateId.impossibleSpeed}  (unambiguous; empty when clean)
// verdict.gateResults    -> raw per-gate audit map (true = passed)
```

Wiring the whole stream (the monitor is stateful — feed it one `update()` per
fix, in order, from a single non-broadcast subscription):

```dart
positionStream
    .map((p) => monitor.update(toFix(p)))
    .listen((v) { /* act on v.status / v.recommendedSource */ });
```

## The four gates (this release — the floor)

Each is a calibration-free physical-plausibility check between two fixes:

| Gate | Fires when | Severity |
|---|---|---|
| `teleport` | a jump too large over a delta too small to compute a reliable speed | hard → `failed` |
| `impossibleSpeed` | implied speed exceeds `maxPlausibleSpeed` (default 50 m/s) | hard → `failed` |
| `impossibleAccel` | implied speed change exceeds `maxPlausibleAccel` (default 8 m/s²) | soft → `suspect`, `failed` if sustained |
| `stationaryJitter` | the position wanders while the vehicle is stationary | soft → `suspect` only (never `failed`) |

Hard faults fail immediately (a teleport is unambiguous); the acceleration gate
debounces (`failAfterConsecutiveSoft`, default 2) so one glitch does not flap the
verdict. Stationary jitter is a caution hint and never escalates on its own.

## Running it

`dart run example/main.dart` feeds a north-bound track with a 200 m multipath
teleport at t=5 and prints:

```text
t   status    source         reason
--  --------  -------------  ------------------------------------------
0   trusted   gps            first fix — no prior position to compare
1   trusted   gps            no fault detected
2   trusted   gps            no fault detected
3   trusted   gps            no fault detected
4   trusted   gps            no fault detected
5   failed    deadReckoning  impossible speed: 201 m/s (max 50)
6   failed    deadReckoning  impossible speed: 201 m/s (max 50)
7   trusted   gps            no fault detected
```

## Honesty bound (read this)

- **`trusted` ≠ correct.** It means "no fault detected by *these* tests", never
  "position verified". Measurement plausibility is not state correctness.
- **This is not anti-spoofing.** The floor catches *abrupt* faults (teleports,
  impossible motion). A slow, smooth spoof that walks the position away
  gradually will pass. Lead with multipath/teleport protection; do not market
  this as defeating a determined spoofer.
- **It recommends `deadReckoning` only when you say your DR is fresh.** The
  monitor cannot judge whether your DR is any *good* — only that you told it the
  estimate is recent. When in doubt it recommends `hold`, never a source it has
  no basis to trust.

See `KNOWN_LIMITATIONS.md` for the full list (including the weakly-gated first
fix after a long blackout, and the rate gates' warm-up).

## Roadmap (not in this release)

The floor stands alone and is useful alone. A later slice adds the optional
**NIS / chi-square consistency layer**: feed it an independent motion prediction
(e.g. from a dead-reckoning EKF) and it also catches fixes that are physically
*possible* but statistically inconsistent with how the vehicle is actually
moving. It lands additively (an optional parameter on `update`); the floor keeps
protecting even if that finer layer is mistuned.

## Status

0.1.0. The calibration-free plausibility floor. Pure Dart, no dependencies.
Interface may evolve before 1.0 as the NIS layer lands; changes will follow
semver and the honesty bounds above are permanent.
