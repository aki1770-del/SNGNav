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

