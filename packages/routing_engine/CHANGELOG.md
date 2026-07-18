## 0.3.3

**Stops a set of malformed-response CRASHES. Additive/defensive only — no API
changed, no signature changed. Includes everything in 0.3.2 below.**

A crash is worse than a wrong coordinate: a thrown exception takes down the
**entire** `calculateRoute()` call, so a consumer who asked for a route home
gets nothing. Up to and including 0.3.1, several malformed-but-plausible
responses threw a raw `RangeError`/`TypeError`/`FormatException` that escaped
this package's documented `RoutingException` and crashed the caller. Each now
either returns a safe result or throws a `RoutingException` you already catch —
never a raw crash, never a fabricated place.

* **Valhalla — negative `begin_shape_index`** previously threw `RangeError`
  (`allPoints[-1]`). It is now clamped onto a real decoded point on your route
  and flagged `positionResolved: false`. For every non-negative index the
  position is unchanged from 0.3.1.
* **Valhalla — `begin_shape_index` or `type` sent as a JSON double** (e.g.
  `1.0`) previously threw `type 'double' is not a subtype of type 'int?'`. Both
  are now read as `num` and coerced to `int`.
* **OSRM — `maneuver.location` with non-numeric elements** (e.g. `["a","b"]`)
  previously threw a cast error. It is now treated as an unresolved position
  (clamped into the corridor + `positionResolved: false`), never a throw.
* **Both engines — a non-JSON body returned with HTTP 200** (a proxy or captive
  portal serving an HTML error page) previously threw a raw `FormatException`.
  It is now a `RoutingException('… non-JSON body (HTTP 200)')`.
* **Both engines — a crash backstop** now wraps response parsing: any remaining
  malformed-response throw (a non-object leg/step, a text field sent as a
  number, an undecodable shape) surfaces as a `RoutingException` instead of a
  raw crash. The targeted fixes above still return a usable, flagged route for
  the common cases; this only catches what they do not.

Nothing here is breaking: `RouteManeuver.position` is still a non-nullable
`LatLng`, no signature changed, and `RoutingException` is the error type this
package already documents. Take it without touching your code.

## 0.3.2

**Adds an honest signal for substituted maneuver positions. Additive only —
this is a drop-in patch, nothing you already read changes type or value.**

0.3.1 stopped this package from ever handing you `LatLng(0, 0)` (Null Island)
for a maneuver whose position it could not resolve. But it still had to put
*some* `LatLng` in the non-nullable `RouteManeuver.position` field, so when the
real location was unavailable it **clamped in a nearby point on the route
corridor** (or the route origin). That point is on your route — never in an
ocean — but it is **not where the turn actually happens**, and until now you
had no way to tell a clamped, imprecise point apart from a resolved one. So an
approximate position was still narrated, plotted, and measured with full
confidence.

**Now** every maneuver tells you which it is:

* Added `RouteManeuver.hasPosition` (and the backing field
  `RouteManeuver.positionResolved`). It is `true` when `position` is this
  maneuver's own resolved coordinate, and `false` when `position` is a
  substituted/clamped corridor point that must not be trusted as the turn's
  location.
  * **OSRM**: `false` when the step's `maneuver.location` was missing or
    malformed.
  * **Valhalla**: `false` when `begin_shape_index` was missing (previously
    defaulted to `0`, silently claiming the turn is at the route start) or ran
    past the decoded shape (clamped to the last decoded point).
* `RouteManeuver.toString()` appends `position unknown` when the position is
  substituted.

**Nothing is breaking.** `RouteManeuver.position` is still a **non-nullable
`LatLng`** and still carries the same clamped value it did in 0.3.1, so existing
code compiles and runs unchanged. `positionResolved` is a new field with a
default of `true`; `hasPosition` is a new getter. You can take this without
touching your code — and then guard your reads to stop trusting an
approximated place:

```dart
for (final m in route.maneuvers) {
  if (m.hasPosition) {
    announcePlace(m.instruction, m.position); // resolved — safe to narrate/plot/measure
  } else {
    announceTurn(m.instruction);              // substituted — say the turn, not a place
    // skip the map marker; do not measure distance-to-next-maneuver from m.position
  }
}
```

*(The 0.5.x/0.6.x line makes `position` itself nullable, which is the more
honest API but a breaking change. This 0.3.x patch gives you the same safety
signal without forcing that migration.)*

## 0.3.1

**Fixes a fabricated coordinate. Nothing else changes — this is a drop-in patch.**

Up to and including 0.3.0, when a maneuver's position could not be resolved — OSRM
omitted `maneuver.location`, or Valhalla's `begin_shape_index` ran past the decoded
shape — this package substituted `const LatLng(0, 0)`.

That is **Null Island**: a real coordinate in the Gulf of Guinea, thousands of
kilometres from any route. It is a perfectly valid `LatLng`, so **you had no way to
tell it apart from a real one.** If you drew markers from `RouteManeuver.position`,
one of them could silently appear in the Atlantic. If you computed a distance or a
bearing to it, you got a confident number about a place that does not exist.

**Now:** an unresolvable maneuver is clamped into the route corridor where a truthful
point is available, and **dropped entirely when none is.** We would rather hand you a
missing turn than an invented one — a missing turn is visible, a fabricated one is not.

**This is a patch release on the 0.3.x line, kept deliberately source-compatible.**
`RouteManeuver.position` is still a non-nullable `LatLng`; no signature changed. You
can take this without touching your code.

*(The 0.5.x/0.6.x line makes `position` nullable, which is the more honest API but is
a breaking change. This patch exists so that you do not have to accept a breaking
change to stop receiving a fabricated coordinate.)*

# Changelog

## 0.3.0

- Harmonize package version to 0.3.0 for Sprint 80 Direction F.
- Align internal ecosystem dependency constraints to ^0.3.0 where applicable.
- No breaking API changes in this package for this release.

