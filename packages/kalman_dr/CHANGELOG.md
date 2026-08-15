# Changelog

## 0.5.1

**A documentation patch, and one line of it is a real defect that could crash your app.**

- **⚑ FIXED: every `.listen()` example on this page taught a pattern that crashes.**
  `DeadReckoningProvider` pushes a terminal `DeadReckoningAccuracyExceededException`
  onto `positions` when dead reckoning drifts past the 500 m safety cap. **Every
  snippet we shipped through `0.5.0` called `.listen()` with no `onError`** — the
  word `onError` appeared **zero times** in the published README. A reader who
  copied our Quick Start took an **uncaught zone error**, and it fires precisely
  when DR has drifted furthest: the deepest point of a GPS outage, which is the
  worst possible moment for a navigation app to die. Every example now registers
  `onError`, and the Features list says the cap emits a terminal error.
- **FIXED: the page contradicted itself about what `accuracy` means.** The Features
  list sold *"covariance-driven accuracy: honestly degrades over time during GPS
  loss"* while the integration section warned *"Accuracy answers 'how confident',
  never 'is this real'."* **Both were on the same page.** Provenance
  (`position.source`) is now stated first and named as the only liveness signal;
  accuracy is described as a confidence number and nothing else.
- **FIXED: reader-supplied symbols in examples are now declared** (`// oracle:placeholders`),
  so a reader can see at a glance which identifiers are theirs to provide. Five
  symbols across the README and three library doc comments were undeclared, which
  meant copying an example verbatim produced a compiler error with no hint why.

**⚑ DISCLOSURE OWED SINCE `0.1.0`, and not made until now.** From `0.1.0` through
`0.4.4` this package's README used `position.accuracyMetres` — **a member
`GeoPosition` has never had** — in both examples, so **neither example compiled**,
across four releases. Worse, it taught `accuracyMetres > 25` as the way to tell a
live fix from an extrapolation, which is **exactly the inference this package
exists to refute**: 1 s of dead reckoning off a clean 8 m fix reports ~13 m and
would render as "live", while a genuine 40 m fix under tree cover would render as
"predicted". `0.5.0` fixed the page but **did not disclose that it had been wrong**.
It is disclosed here.

**Nothing in this release changes runtime behaviour, the public API, or the
equality contract.** `0.5.0`'s breaking change stands as described below. This is
in-range for any `^0.5.0` dependency: a `pub upgrade` carries it.


## 0.5.0

- **BREAKING (behaviour, not API): `GeoPosition` equality changed.** `source`
  now participates in `==` and `hashCode`, so a position tagged `measured`,
  `fused` or `deadReckoned` is no longer equal to an otherwise-identical
  position carrying the default `unknown`. If you put `GeoPosition` in a `Set`
  or use it as a `Map` key, and one side of the comparison has been through a
  serializer that predates this release, **lookups that used to hit now return
  `null`, silently** — no exception, no analyzer warning. This affects the
  GPS-present `fused` path, not only the dead-reckoning fallback. The case
  worth naming: a last-known-position cache keyed by `GeoPosition` starts
  missing precisely when GPS is gone. Carry `source` through your codecs, or
  key on `(latitude, longitude, timestamp)`. Everything compiles unchanged;
  this is why it takes the minor slot rather than riding in as a patch.
- **`GeoPosition` now states its own provenance.** New `PositionSource` enum
  (`measured` / `fused` / `deadReckoned` / `unknown`) on `GeoPosition.source`,
  with `isMeasured`, `containsMeasurement` and `isDeadReckoned`. A consumer
  holding only a position can now tell a real fix from an extrapolated one.
  Previously the only discriminator was the provider's out-of-band `isDrActive`
  getter, which is unavailable to anyone holding just a position — a stored
  trajectory, a BLoC state, a log line, a downstream fusion library.
- **Neither accuracy nor timestamp discriminated, and the docs said accuracy
  did.** One second of dead reckoning off a clean 8 m fix reports 13 m, which
  reads *better* than a genuine 40 m fix under heavy tree cover; both clear
  `isNavigationGrade`. And an extrapolated position carries the emission time,
  so it looks *fresher* than the real fix behind it. The library docstring
  promising accuracy-based degradation as the consumer's signal is corrected.
- **New `GeoPosition.extrapolatedFor`** — how long an estimate has run without a
  sensor reading. Not recoverable from `accuracy`, which conflates base fix
  quality with elapsed drift.
- **Kalman-mode GPS-present output is marked `fused`, not `measured`.** It was
  already the filter's estimate rather than the sensor's value; that is now
  visible rather than implied.
- **`source` participates in equality.** This protects a consumer's own
  dedupe — `.distinct()`, a `Set`, a "has this changed?" guard — from swallowing
  the measured → dead-reckoned transition at a stationary coordinate, which is
  exactly the event worth knowing. It is *not* a change in what this package
  emits: the provider's own stream emits the same number of positions as
  before, measured. The protection is for the stream you derive, not the one we
  hand you.
- API-additive: the new parameters are optional, the default is `unknown`
  (never `measured` — a library cannot assert a sensor reading it did not
  take), and `toString()` is byte-identical **for positions you construct
  yourself without passing `source`** — not for positions this package emits,
  which now carry their provenance and print it. Source compatibility is
  unchanged; see the equality note above for the one behaviour that is not.

## 0.4.4

- Provenance correction (honesty-of-record): the 0.4.3 CHANGELOG stated "No code
  change", but 0.4.3 in fact shipped — carried in from the 2026-06-27
  finite-position safety work — four executable NaN/non-finite guards in the
  dead-reckoning + Kalman path that were not present in the published 0.4.2:
  a non-finite latitude/longitude early-return in `_onGpsPosition`
  (`dead_reckoning_provider.dart`); an `accuracy.isFinite` condition on the
  Kalman-update gate; a non-finite-determinant guard in the matrix inverse
  (`kalman_filter.dart`); and a NaN-reject floor in the accuracy→covariance
  mapping. These guards are correctness-improving — they stop a NaN/Inf GPS fix
  from corrupting the filter or teleporting the position — and are covered by
  `finiteness_guard_test.dart`. This 0.4.4 release corrects the record; it
  contains no further code change of its own (lib is identical to 0.4.3).

## 0.4.3

- Docs: correct the README test-count claim from "200+ unit tests" to the real count (77, confirmed via `dart test`). Update the README install snippet pin to `^0.4.3` to resolve the current version. No code change.

## 0.4.2

- Docs: correct the dead-reckoning description — the package does constant-velocity extrapolation from the last GPS fix, NOT device-sensor/IMU fusion. No code change.

## 0.4.1

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.4.0 — 2026-05-10 — Pana score recovery + dart format alignment

- Trim pubspec `description` to ≤180 characters so search-engine
  snippets surface the package's purpose cleanly.
- Apply `dart format` across `lib/` and `test/` (9 files reformatted)
  to clear pana static-analysis formatter findings.
- No SDK source changes; metadata + formatter pass only.

## 0.3.0

- Harmonize package version to 0.3.0 for Sprint 80 Direction F.
- Align internal ecosystem dependency constraints to ^0.3.0 where applicable.
- No breaking API changes in this package for this release.

