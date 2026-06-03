# Changelog

## 0.0.5

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.0.4 — 2026-05-10 — Pana score recovery (Theme α P4)

- Add minimal `example/main.dart` for pana documentation scoring.
- Apply `dart format` to clear any formatter findings.
- No SDK source changes; metadata + format pass only.


## 0.0.3 — 2026-05-06 — Typed alert area (polygon + circle)

Adds a typed geographic-area record so consumers can present a precise
geographic scope (polygon or circle) to the driver rather than an
abstract zone identifier or a free-form area description string. The
existing `areaDesc` free-form field is preserved unchanged for
back-compat.

The driver-facing rationale: *"winter alert covers a precise
geographic area on the route, not just an abstract zone identifier."*
The polygon shape supports the integrator's per-route geofence-class
question — does this alert intersect my route? — without flying out
to a separate gazetteer service.

CAP area schema verbatim citation (CAP-v1.2 §3.2.4):
- `area/polygon` — *"The paired values of points defining a polygon
  that delineates the affected area of the alert message"*. Vertex
  list as decimal-degree pairs; closed shape (first == last).
- `area/circle` — *"The paired values of a point and radius
  delineating the affected area of the alert message"*. Format
  `"<lat>,<lon> <radius_km>"`.

### Added

- `WinterAlertArea` value-object (Equatable) with two fields:
  `polygon: List<GeoPoint>` (empty when publisher did not declare a
  polygon) and `circle: WinterAlertCircle?` (null when publisher did
  not declare a circle). Both null/empty → `WinterAlertArea.isEmpty
  == true` (caller falls back to `areaDesc`).
- `WinterAlertCircle` value-object (Equatable) with `center: GeoPoint`
  and `radiusKm: double`.
- `GeoPoint` value-object (Equatable) — WGS84 lat/lon pair. We
  deliberately do not depend on `latlong2` here to keep the
  `noaa_nws_adapter` boundary narrow per smallest-slice discipline;
  integrators wishing to hand off to a geometry library translate at
  their boundary.
- `WinterAlert.area: WinterAlertArea?` field. Non-null when the
  feature carried a parseable geometry or CAP circle. Construction
  without `area` is permitted (default null) for back-compat.
- `WinterAlert.fromFeature(feature)` factory: builds a record from
  the full GeoJSON feature envelope (properties + geometry); parses
  the typed area in addition to the existing field set.
- `WinterAlert.parseArea(geometry, parameters)` static helper —
  visible for direct testing.
- Exports: `WinterAlertArea`, `WinterAlertCircle`, `GeoPoint`.

### Changed

- `NoaaNwsClient.parseFeatureCollection` now uses
  `WinterAlert.fromFeature` (instead of `fromProperties`) so the
  typed area is populated through the HTTP path. Records produced by
  the production code path now carry `area` when the feature's
  geometry is parseable.

### Tests

- 6 new tests covering: polygon parse from typical NWS GeoJSON
  geometry; circle parse from CAP-style `parameters.circle` text;
  area-not-present (null geometry → `area = null`); MultiPolygon
  takes first polygon's first ring; invalid coordinates (non-numeric
  / wrong shape) skip vertex; negative radius rejected.

### Unchanged (back-compat)

- All 0.0.1 + 0.0.2 surface unchanged. `WinterAlert.fromProperties`
  still works and returns `area: null` (the properties dict alone
  does not carry geometry). Existing callers reading `areaDesc` see
  the same value as before; new callers can opt in to `area` for
  the typed shape.
- `NoaaNwsClient.fetchActiveWinterAlerts` API surface unchanged.
- Equatable `props` extended (additive); equality semantics for
  pre-0.0.3 records (constructed without `area`) match prior shape
  since the default `area = null` is consistent.

## 0.0.2 — 2026-05-04 — Bounded retry-with-backoff

Adds an opt-in retry policy for transient publisher-network failures.
Default behavior unchanged for back-compat: passing no `retryPolicy`
to `NoaaNwsClient` still produces the 0.0.1 single-attempt semantics
where the caller decides backoff.

The driver-facing rationale: a single transient failure (5xx, brief
connection reset, brief DNS hiccup) should not silently drop the
alert reach for the driver in unexpected snow. The retry policy is
conservative on intent (transient-only; never retries 4xx) and
bounded on attempts so an integrator's logs remain honest about how
many calls actually went out.

### Added

- **`NoaaNwsRetryPolicy`** value-object: `maxRetries`, `baseDelay`,
  `retryableStatusCodes`. Default constructor: 3 retries, 1s base,
  retries on `{408, 429, 500, 502, 503, 504}`. Exponential backoff
  per `delayForAttempt(retryIndex)` (1s, 2s, 4s on default).
  `NoaaNwsRetryPolicy.none` constant preserves 0.0.1 behavior.
- **`NoaaNwsClient.retryPolicy`** parameter: defaults to
  `NoaaNwsRetryPolicy.none` (back-compat). Pass an explicit
  `NoaaNwsRetryPolicy()` to opt in.
- **`NoaaNwsClient.sleep`** parameter: injectable sleep function for
  tests; defaults to `Future.delayed`.

### Changed

- `NoaaNwsClient.fetchActiveWinterAlerts()` now applies the configured
  `retryPolicy` to transient failures (5xx / 408 / 429 /
  transport-class). 4xx (other than 408 / 429) is NOT retried — these
  are client-class errors where retry produces the same failure and
  wastes the publisher's quota. After retry exhaust, the most recent
  failure surfaces as `NoaaNwsHttpException` with the same shape as
  0.0.1.

### Tests

- 9 new tests covering: default-policy delays (1s, 2s, 4s); none-policy
  zero-retries; status-code retryability table (5xx + 408 + 429
  retryable, 4xx not); retry-success path (503 then 200); retry-exhaust
  (4 consecutive 503 → exception); 4xx-no-retry (404 → 1 call only);
  retry-on-429; observed-sleep-durations; default-back-compat (no
  retry without explicit policy).

### Unchanged (back-compat)

- All 0.0.1 surface unchanged. `NoaaNwsClient(userAgent: ...)` without
  `retryPolicy` behaves identically to 0.0.1.

## 0.0.1 — 2026-05-03

Initial publish.

- `NoaaNwsClient` stateless HTTP wrapper for
  `https://api.weather.gov/alerts/active?point={lat},{lon}` (User-Agent
  required; mandatory at construction).
- `WinterAlert` Equatable model carrying CAP-class fields (`event`,
  `severity`, `certainty`, `urgency`, `status`, `messageType`,
  `headline`, `areaDesc`, `effective`, `expires`, `description`,
  `instruction`).
- CAP enums with safe `unknown` default: `AlertSeverity`,
  `AlertCertainty`, `AlertUrgency`, `AlertStatus`, `AlertMessageType`.
- `kNwsWinterEventTypes` 14-string catalogue (Winter Storm Warning /
  Watch, Winter Weather Advisory, Blizzard Warning, Ice Storm Warning,
  Heavy Freezing Spray Warning / Watch, Lake Effect Snow Warning,
  Freeze Warning / Watch, Freezing Fog Advisory, Cold Weather
  Advisory, Extreme Cold Warning / Watch).
- `NoaaNwsHttpException`, `NoaaNwsParseException` typed error surfaces.
- Default filter `actualOnly: true` excludes `Test` / `Exercise` /
  `System` / `Draft` entries from production driver-facing flow.
- Malformed CAP features skipped (warn-and-continue) rather than
  aborting the whole response.
- 25 tests covering value-object, CAP-enum mapping, parse-layer error
  surfaces, MockClient round-trip, header propagation, transport
  failure surfaces.
- BSD-3-Clause license (matches the rest of SNGNav).
- Pure Dart, no Flutter dependency.
