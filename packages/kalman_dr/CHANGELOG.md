# Changelog

## 0.6.2

**The filter can now be tuned for what is actually carrying the device. Until
this version, forking was the only way.**

A verified external consumer pinned this package to an exact version and wrote a
fork plan into their own documentation — *"pin an exact version and be prepared
to vendor/fork it… Alternative: EKF is ~200 lines to own outright."* Their app
tracks **runners closing a geographic loop**, and loop closure is its core
mechanic.

**The cause was ours, not their distrust.** `_processNoise` was a private
`static const`, documented *"tuned for road driving at ~1 Hz GPS updates"*, with
entries annotated *"driver brakes/accelerates"* and *"driver turns"*. The
constructor took no arguments and there was no injection point anywhere. **There
was no supported way to tune this for a pedestrian**, and a heading noise
modelling a turning car smooths through a corner a runner actually took.

**Added: `MotionProfile`.** `KalmanFilter({MotionProfile profile})`, defaulting
to `MotionProfile.roadVehicle`.

**Nothing changes for any existing caller.** `roadVehicle` carries the 0.6.1
constants byte-for-byte and a test asserts that, because silent drift there
would change behaviour on upgrade — the one thing an additive parameter exists
to prevent. `KalmanFilter()` is unchanged in behaviour and signature.

### ⚑ `MotionProfile.pedestrian` is DERIVED, NOT MEASURED

Stated in the API, in its own `name` field, and asserted by a test — because a
reasoned guess presented as a calibration would read as a warrant this package
cannot issue. **`test/` contains zero recorded trajectory fixtures**, so nothing
here is fitted against real pedestrian traces.

The derivation is shown so you can disagree with it:

- **Heading 1.0 → 100.0.** A car at 50 km/h needs several seconds to turn 90
  degrees; a runner rounding a corner takes about one. A ~10x faster achievable
  turn rate scales as roughly the square.
- **Speed 0.5 → 0.1.** Running speed varies gently around 3–5 m/s with no
  equivalent of a hard brake, so trusting the constant-velocity model *more* is
  correct.
- **Position terms unchanged** — they model process drift, not carrier dynamics.

**If you have real traces, fit your own with the unnamed constructor and please
tell us what you found.**

### Verified

`dart test` 129/129, `dart analyze` clean. The profile test proves the pedestrian
profile **tracks a 90-degree corner the road profile smooths away**, with a
control asserting the two profiles **agree on a straight run** — so the corner
test demonstrates cornering, not merely that two constants differ. A
non-positive or non-finite process-noise term is refused at construction rather
than silently breaking the covariance update.


## 0.6.1

**The 500-metre accuracy cap was never 500 metres except at the Equator, and the
further north you drove the earlier dead reckoning gave up on you.**

**Who is affected.** Anyone reading `isAccuracyExceeded`, or catching
`DeadReckoningAccuracyExceededException`, above or below roughly 35 degrees
latitude. Everyone else sees no change. No API is added or removed and nothing
throws that did not throw before — **the threshold simply moves to where the
documentation always said it was.**

### What was wrong

`isAccuracyExceeded` compared the position covariance trace against a constant:

```dart
// 0.6.0 and earlier
bool get isAccuracyExceeded => _p[0][0] + _p[1][1] > maxCovarianceThreshold;
```

`_p[0][0]` and `_p[1][1]` are variances in **degrees squared** — of latitude and
of longitude. A degree of longitude is not a fixed distance: it is about 111 km
at the Equator and shrinks by `cos(latitude)`. So a fixed threshold in degrees
squared is a **different distance at every latitude**, and it tightens as you go
north. The package documented, and the app displayed, a cap of **500 m**. What
the code enforced was 500 m only where `cos(latitude) = 1`.

**Akita in February is at 39.7 N.** `cos(39.7 deg) = 0.769`. The cap there fired
meaningfully earlier than the number we printed — dead reckoning withdrawing
while a driver was still inside the accuracy she had been promised, in the exact
conditions the withdrawal exists to survive.

### What it is now

```dart
/// The safety cap, in METRES — the number the package documents and the app
/// displays. Compared against [accuracyMetres], which is latitude-correct.
static const maxAccuracyMetres = 500.0;

bool get isAccuracyExceeded => accuracyMetres > maxAccuracyMetres;
```

`accuracyMetres` already applied the `cos(latitude)` weighting to the longitude
term. The cap now uses it, so **500 m means 500 m at every latitude.**

`maxCovarianceThreshold` is kept and `@Deprecated`; it is removed in 1.0.0.

### How this is proven, and it is proven the awkward way round

`test/accuracy_cap_latitude_test.dart` was written **before** the fix and run
against the old code, where **4 of its 5 cases failed**. It asserts two things:
the cap never fires before the documented distance, and the stop radius is the
same at the Equator, Nagoya, Akita, Sapporo and Tromso — spread under one metre.
A test that had passed against the defect would have proven nothing. 122 tests
pass.

### ⚑ Why this is 0.6.1 and not 0.6.0

The fix was committed to the working tree while `pubspec.yaml` still read
`version: 0.6.0` — **a version already published, immutably, with the old cap in
it.** For a period, two different behaviours of a safety threshold answered to
one version string, and this changelog had no entry for the change at all. That
is recorded here rather than quietly renumbered, because a reader comparing
`0.6.0` on pub.dev against `0.6.0` in our git history would otherwise find two
different safety caps and no explanation.

## 0.6.0

**Two things the object told you that it could not support. Both are behaviour
changes with no compiler warning — read the first one before upgrading.**

**How the numbers below were produced**, so you can check them rather than take
them: every figure was measured on the published `0.5.1` archive and on this
release, through `DeadReckoningProvider(mode: DeadReckoningMode.kalman)` wrapped
around a stub inner provider, fixes at 35.1709 N 136.8815 E on heading 90
degrees, timestamps one second apart, and `.accuracy` read off the emitted
position; speed is 12.5 m/s and there is no outage except where a figure states
otherwise. Change the cadence or the prior and
the absolute numbers change; the differences between the two releases do not.

### ⚑ BREAKING (behaviour, not API): `extrapolatedFor` is now the real gap, always

Through `0.5.1` this field was `Duration.zero` on every `measured` and `fused`
emit, so `extrapolatedFor == Duration.zero` read as *"a sensor contributed"*.
**It no longer does.** On a `fused` position it is now the actual elapsed time
since the last reading the filter accepted — ordinary inter-fix spacing in
steady state (~1 s at 1 Hz), and the length of the outage after one.

**If you gate on `extrapolatedFor == Duration.zero` to mean "fresh", that gate
now never fires.** Nothing throws and the analyzer says nothing. Use
`source` / `isDeadReckoned` / `containsMeasurement` for the *"was a sensor
involved"* question — they answer it exactly, and always did.

**What the clock measures from.** It is the provider's own wall clock — the
moment a reading arrived — not the timestamp the reading carries. On a live
stream those agree. On a replayed or simulated trajectory they do not: fixes fed
faster than real time report a near-zero gap however far apart their timestamps
are. This is not new in `0.6.0`; the dead-reckoning path measured the same way
in `0.5.1`.

**Why it changed.** The first fix back after a GPS outage is not the
measurement: the filter blends it with a prediction that ran blind for the
whole gap, and on a short outage the prediction still dominates. `source` is
truthfully `fused` there, `isDrActive` is already false, and every quality
getter reads clean — so this field was the only thing left that could disclose
the gap, and it was stamped zero in the same breath.

A first attempt disclosed the gap only when it reached `gpsTimeout`. That was
wrong, and measured wrong on this tree: **`gpsTimeout` decides when dead
reckoning takes over, and says nothing about whether an estimate is stale.** It
is also a constructor parameter you can set to anything, so the number would
have meant *"the gap, if it happened to exceed a value you chose"*. At the
shipped default of **3 s**, gaps below it never start dead reckoning at all —
measured on the `0.5.1` archive, a **2 s gap at 20 m/s reported
`extrapolatedFor` of zero while the emitted coordinate sat 13.0 m from the true
position against a reported radius of 3.92 m**, 3.3× its own claimed accuracy,
disclosed nowhere. At 12.5 m/s the same gap gave 8.1 m against 3.71 m, 2.2×.
The same code measured at a 200 ms timeout disclosed every band, which is
exactly how the threshold looked correct. The field is now threshold-free and monotonic in the
gap; under the threshold it was 0, 0, 0, then jumped.

### FIXED: an accuracy the sensor never stated was read as a precision claim

`geolocator` reports `accuracy: 0.0` when `Location.hasAccuracy()` is false,
GeoClue2 can report `0`, and some providers use `-1`. Those are sentinels
meaning *"not stated"* — and `0.5.1` read them as measurements.

Measured on the `0.5.1` tree, four fixes at `accuracy: 0` through
`DeadReckoningProvider`: **the reported radius was 0.0000 m**, and
`isHighAccuracy` passed on it. `-1` squared back to a 1 m claim and reported
1.0861 m, exactly what a stated 1 m fix reports — so the two spellings of
*"unavailable"* did not even agree with each other. In `0.6.0` both report
**3.6246 m**, the same figure a stated 5 m fix gets, because that is what this
filter already assumes for an unmeasured GPS.

Two zero-accuracy fixes collapse the position covariance to exactly zero, after
which `S = P + R` is singular, `_invertMat` returns `null`, and
**every further reading at that timestamp is discarded in silence while
`DeadReckoningProvider` still emits the untouched state labelled `fused`** — a
coordinate no sensor contributed to, wearing the label that says one did.
Measured directly: a third fix 92 km away left the state unchanged.

The root of it is that `_diagFromAccuracy` floored the *initial* covariance at
1 m while `update()` floored nothing, so the first fix and every later fix
disagreed about what an unstated accuracy was worth, and the disagreement
compounded. Both paths now go through one rule.

A sentinel is now **replaced** — not floored — by this filter's own documented
reading of an unmeasured GPS, ~5 m, the same figure already in
`_defaultMeasurementNoise`. All of `0`, `-1`, `NaN` and `+infinity` land on the
same answer.

**A stated sub-metre accuracy is honoured, and deliberately so.** `0.5.1` did
honour RTK from the second fix onward, and every one of those numbers is
unchanged here: measured on both releases, a stated 0.05 m fix settles at
0.0645 m, 0.1 m at 0.1287 m, 0.5 m at 0.6039 m, 1 m at 1.0795 m and 5 m at
3.3519 m — identical to four decimals. **On the `update()` path nothing moved.**

**⚑ The FIRST fix did move, and only the first.** Through `0.5.1` the
initialisation path floored the initial covariance at 1 m while `update()`
floored nothing, so a receiver stating 0.05 m had its first emitted position
reported as 1.2916 m no matter what it said, and only the second fix honoured
it. `0.6.0` puts both paths through one rule, so the first fix is honoured too.
First emitted position, measured on both:

| stated accuracy | `0.5.1` | `0.6.0` |
|---|---|---|
| 0.02 m | 1.2916 m | 0.0258 m |
| 0.05 m | 1.2916 m | 0.0646 m |
| 0.10 m | 1.2916 m | 0.1292 m |
| 0.50 m | 1.2916 m | 0.6458 m |
| 1.00 m | 1.2916 m | 1.2916 m |
| 5.00 m | 6.4579 m | 6.4579 m |

From the second fix onward the two releases agree to four decimals, and at a
stated 1 m or worse nothing changes at all. The same path serves
`KalmanFilter.withState(initialAccuracy:)` and a first `update()` on a fresh
`KalmanFilter`, and both move with it.

**The direction is worth stating plainly: on that first fix `0.6.0` reports a
tighter radius than `0.5.1` did** — 20× tighter at a stated 0.05 m, 50× at
0.02 m — because it now reports what the receiver stated instead of a 1 m floor.
If you read the first emitted position and your source states sub-metre
accuracy, that number changed under you. An earlier draft of this entry claimed
nothing on the stated-accuracy path had moved. That was measured false before
publish, and this is the correction.

A hard 1 m floor was written, tested and **rejected**: it would have degraded a
genuine 0.05 m source **16.7×** to buy a fix for a defect that lives entirely
in the sentinel values, and it was justified in the source by a sentence that
measurement showed to be false (*"no source was ever honoured below it"* — three
were). The only bound kept on the honoured band is a **1 mm** conditioning
floor, three orders of magnitude below anything GNSS delivers, present solely
to keep `R` strictly positive so `S` stays invertible.

**⚑ What this does NOT fix.** A sentinel now settles a few metres out —
**3.6246 m** under the harness above, drifting toward 3.2 m as more fixes
arrive — and `isHighAccuracy` is `accuracy <= 10.0`, **so it still passes.** A consumer
gating only on `isHighAccuracy` still cannot tell a device that never states
its accuracy from one that states a good one. Separately, `DeadReckoningProvider`
gates its filter feed on `pos.accuracy.isFinite`, so a `NaN` or `+infinity` fix
never becomes `fused` at all — it is forwarded raw as `unknown`. Through the
provider, only `0` and `-1` ever reached the filter; the `NaN` path matters for
consumers driving `KalmanFilter` directly.

### Why `0.6.0` and not `0.5.2`

`^0.5.0` resolves `>=0.5.0 <0.6.0`, so a `0.5.2` would have been carried
silently by `pub upgrade` — and the `extrapolatedFor` change is exactly the
shape that hurts when it arrives unannounced: compile-compatible, no analyzer
warning, no exception, a freshness gate that quietly stops firing. `0.5.0` set
this package's own precedent by calling a silent equality change **BREAKING**
and taking the minor position for it. This follows it.

### ⚑ Who this release reaches

**No reader we can see receives it.** The only dependency on this package we
have been able to find is an **exact version pin**, not a range, on the branch
that project builds from. **An exact pin is not crossed by any release we make**
— not this one, and not a patch either. Only an edit to that project's own
manifest moves it, and that edit is theirs to make or not to make.

Older branches in that project do carry a range, and it would be easy to quote
one and call this release reachable. It is not: they are not what the project
builds from, and reading a branch a project does not build from is a mistake
this unit has already made once and written down.

No package on pub.dev depends on `kalman_dr`. **This release is for the future
stranger**, not for the reader we already have. Saying otherwise would repeat
the mistake the `0.5.1` note below was written to record.

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

**⚑ WHERE `0.5.0` AND `0.5.1` CAME FROM — added to this entry after `0.5.1` was
published, so the `0.5.1` archive on pub.dev does not contain it.**

**The defect `0.5.0` addresses was found by a consumer of this package, in live
device and emulator testing, not by our own tests.** Their code — public, and
written about three weeks before either release — records the dead-reckoning
stream continuing to emit extrapolated positions indistinguishably from measured
ones, so a stationary device accumulated distance it had not travelled. They
diagnosed it, worked around it with the out-of-band `isDrActive` getter, and
wrote a regression test for it, on hardware we do not own. `PositionSource`
exists so that workaround is not needed.

**They did not report it to us, and nothing here should be read as their having
done so.** We found it by reading code they published. That same reading is how
we found this release's defects: their subscriptions already registered
`onError` against the terminal accuracy-cap error, which is precisely the
handler every example we shipped through `0.5.0` left out.

We also had the means to catch the documentation defects ourselves and did not
use it — `tool/readme_api_check.dart`, in this package, fails against the
`0.4.4` tree.

**No name appears here because none is ours to publish.** A developer who never
asked to be written about does not become an entry in a changelog on the
strength of our having found their work useful.

**What we could not establish:** what this cost them, and whether anything else
in their code is still working around this package. Both live inside their
project, and we did not ask.


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

