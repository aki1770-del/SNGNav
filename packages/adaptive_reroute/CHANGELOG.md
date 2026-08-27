## 0.2.1

- Widen `latlong2` from `^0.9.1` to `>=0.9.1 <0.11.0`.

  `latlong2 0.10.0` shipped 2026-04-25 and `flutter_map 8.x` resolves it, so the old
  ceiling made this package **uninstallable alongside current `flutter_map`** —
  `version solving failed` for every published version. No source change; the cap was
  gratuitous. Verified on `latlong2 0.10.1`: analyze clean, **34/34 tests pass**. ⚑ **This line said "NOT verified" when staged and that is now false**: at staging time this package could not resolve to 0.10.1 at all (`pub get` exit 65) because its published dependencies still capped `latlong2 ^0.9.1`. Once `navigation_safety_core 0.11.5`, `fleet_hazard 0.6.1` and `routing_engine 0.6.2` were published widened, resolution succeeded and the suite was run. Corrected before publish rather than shipped stale.

# Changelog

## 0.2.0

### Safety defect in 0.1.5 and earlier — please read

Up to and including 0.1.5, this package reported a route as **clear, with full
certainty, when it had no idea what the conditions were.**

`RerouteEvaluator.evaluate()` returned `RerouteDecision.clear()` — reason
`"Route is clear"`, `confidence = 1.0` — for *any* forecast in which no hazard
fired. But a hazard cannot fire on data that was never measured. Because
`driving_weather` 0.4.4 and earlier resolved absent readings into a fabricated
"clear" condition (`+5.0 °C`, `10000 m` visibility, `iceRisk = false` — see the
`driving_weather` 0.5.0 changelog), a route with **no weather data at all**
travelled through this package and came out the other side as:

    RerouteDecision(reroute=false, conf=1.00, reason="Route is clear")

That is the highest-confidence claim this package can make, asserted on the
basis of nothing. `confidence = 1.0` also contradicted the field's own
documented contract ("inherits from the forecast confidence of
`triggerSegment`") — there is no trigger segment on a clear decision, so the
value was not inherited from anything; it was invented.

If you shipped 0.1.5 or earlier to drivers, assume that any "route is clear"
decision your integration displayed **may have meant "we could not see the
route at all"**, and that no distinction was available to you at the API.
pub.dev releases are immutable and cannot be withdrawn: this note is the recall.

### Breaking: a decision that could not be assessed can no longer look certain

* **`RerouteDecision.clear()` is REMOVED.** It is not deprecated. Leaving it
  callable would leave the lie callable, and it would remain the path of least
  resistance for every existing consumer.

* **`RerouteDecision.confidence` is now `double?`.** `null` means **not
  assessable** — the conditions this decision would have rested on were absent.
  It never means "zero confidence" and never means "no hazard".

* **Two constructors replace the one**, splitting a case the old code
  conflated:
  * `RerouteDecision.noHazardFound({required double confidence})` — the
    forecast covered the route and nothing fired. Confidence is **inherited
    from the forecast** (the weakest segment along the route), never a
    synthetic `1.0`.
  * `RerouteDecision.cannotAssess({required String reason})` — the conditions
    were unknown, so no claim can be made. `shouldReroute` is `false` and
    `confidence` is `null`.

* **`RerouteDecision.isAssessed`** (new) — `confidence != null`. **Gate any
  "route is clear" UI on this.** `shouldReroute == false` on its own has never
  meant "the route is safe", and now it demonstrably does not: it is also what
  you get when the package could not look.

* **`RerouteEvaluator.verdictFor(segment)`** (new) — the tri-state
  `SafetyVerdict` (`hazardous` / `notHazardous` / `unknown`) for one segment,
  exposed so integrators can render per-segment map state without re-deriving
  the asymmetry and getting it wrong. `SafetyVerdict` is re-exported from
  `driving_weather`.

### Behaviour changes in `RerouteEvaluator.evaluate()`

* A route with **any** segment whose conditions are unknown can no longer be
  certified clear → `cannotAssess`. Only when *every* segment is known and none
  is hazardous does it return `noHazardFound`.
* An **empty** forecast (no segments) → `cannotAssess`. An empty segment list is
  not an empty hazard list; it means nothing was assessed.
* The evaluator no longer routes its decision through `RouteForecast`'s
  `bool`-valued `hasAnyHazard` / `firstHazardSegment`, which structurally cannot
  represent "unknown". It derives a tri-state verdict per segment from the
  segment's own condition and fleet hazard zones.

### The asymmetry — why this does not cry wolf

A hazard fires on **positive** evidence from any single known signal, even when
every other field is absent: an ice flag alone, a severe road-authority
assertion alone, or a fleet-reported hazard zone alone, all still recommend a
reroute. Only the **negative** claim — "no hazard on this route" — now requires
complete knowledge.

Being offline therefore does **not** raise a hazard alert (a driver who is
warned on every coverage gap learns within one trip to ignore the warning, and
then ignores it on the night it is real). It produces `cannotAssess`, which is
a state the driver can be *told* about.

### Migration

| 0.1.5 | 0.2.0 | Note |
|---|---|---|
| `RerouteDecision.clear()` | `RerouteDecision.noHazardFound(confidence: f)` | only when the route was actually assessed; pass the forecast's confidence, not `1.0` |
| — | `RerouteDecision.cannotAssess(reason: r)` | the new third outcome |
| `if (!d.shouldReroute) showClear();` | `if (!d.isAssessed) showUnknown(d.reason); else if (!d.shouldReroute) showClear(d.confidence!);` | **the fix, at your call site** |
| `double confidence` | `double? confidence` | `null` = not assessable |

`shouldReroute` is unchanged in type and meaning. If your integration only ever
reads `shouldReroute` and `detourWaypoints`, it still compiles and behaves as
before — but it will now silently treat `cannotAssess` as "no reroute needed",
which is exactly the failure this release exists to end. **Read `isAssessed`.**

### Also

* `driving_weather` constraint `^0.4.0` → `^0.5.0` (the Measured-or-Absent
  release; this package's honest-absence behaviour depends on that type
  surface, so the floor is hard).
* `route_condition_forecast` constraint `^0.1.0` → `^0.2.0`.
* `routing_engine` constraint `>=0.4.0 <0.6.0` → `>=0.4.0 <0.7.0`. This
  package's `lib/` imports no `routing_engine` symbol (it only holds a
  `RouteResult` transitively, inside `RouteForecast`), so the 0.6.0
  nullable-`RouteManeuver.position` break cannot reach it. The range spans 0.6.0
  deliberately rather than pinning consumers needlessly.
* `SAFETY_BOUNDARY.md` §1/§3/§8 corrected in the same commit as the code: the
  0.1.0 record described a two-outcome advisory surface and did not disclose
  that an unassessable route was presented to the driver as a clear one.

## 0.1.5

- Widen the `routing_engine` constraint to `>=0.4.0 <0.6.0` so consumers can
  take `routing_engine` 0.5.0 (language-honoring turn-by-turn narration)
  alongside `adaptive_reroute`. No library code change (lib/ is byte-identical
  to 0.1.4).


## 0.1.4

- deps: require `fleet_hazard: ^0.5.0` (the anonymized aggregate — `HazardZone`
  no longer retains a re-identifiable per-vehicle trail). No API change here;
  this package reads only zone center/severity/vehicleCount/confidence, all
  preserved. Tests updated to the `ZoneObservation` element type.

## 0.1.3

Safety-documentation honesty fix. The docs now describe only what ships;
no source/behavior change.

- **Struck a fabricated SOTIF safety claim.** README and `SAFETY_BOUNDARY.md`
  (§3) described a "minimum-progress-before-reroute / anti-thrashing logic"
  presented as an explicit SOTIF-class mitigation against alarm-fatigue. No
  such field or logic exists in code; `RerouteEvaluator` evaluates each
  forecast independently with no debounce. Removed the claim and recorded
  alarm-fatigue mitigation as a documented carry-forward gap (integrator
  responsibility until implemented).
- **Corrected the "respects detour-distance limits" claim.** README said
  `DetourPlanner` respects detour-distance limits; `AdaptiveRerouteConfig`
  exposed `maxDetourFraction`, documented as the threshold above which a
  candidate route "is rejected." No code path consumes `maxDetourFraction` —
  nothing is rejected. The field is now documented as **declared but not yet
  enforced** (carry-forward gap; enforce in your own routing engine).
- Fixed a stale dartdoc reference to the non-existent `AdaptiveRerouteService`
  (actual class: `RerouteEvaluator`).

## 0.1.2

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.1.1 — 2026-05-10 — Refresh cascade-stale dependency constraints

- `driving_weather: ^0.3.0` → `^0.4.0` (consumer-side refresh after
  driving_weather 0.4.0 release earlier the same day).
- `fleet_hazard: ^0.3.0` → `^0.4.0`.
- `routing_engine: ^0.3.0` → `^0.4.0`.
- No source changes; pubspec dep-constraint refresh only.

## 0.1.0 — 2026-04-27

Initial release.

Safety-driven route adaptation for winter driving. Consumes a
`RouteForecast` from `route_condition_forecast`; returns a
`RerouteDecision` (whether to reroute, why, detour waypoints).

Exports:

- `AdaptiveRerouteConfig` — thresholds and limits for reroute decisions
- `DetourWaypoint`, `RerouteDecision` models
- `RerouteEvaluator` service — decides when rerouting is justified
- `DetourPlanner` service — generates hazard-bypassing waypoints

Pure Dart. No Flutter dependency.

Dependencies: `equatable`, `latlong2`, `driving_weather` ^0.3.0,
`fleet_hazard` ^0.3.0, `routing_engine` ^0.3.0,
`route_condition_forecast` ^0.1.0.
