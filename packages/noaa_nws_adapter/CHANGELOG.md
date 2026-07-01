# Changelog

## 0.0.8 — 2026-07-02 — Out-of-coverage short-circuit (behavior change)

`api.weather.gov` covers the United States **and its territories**. Handed
an out-of-coverage point (for example Akita, Japan — `39.7167, 140.0983`)
the endpoint returns **HTTP 400**, which this adapter surfaced as a
`NoaaNwsHttpException`. That forced every consumer to wrap non-US points in
a try/catch and pattern-match a 400 just to mean "no US alerts here."

**Behavior change:** `NoaaNwsClient.fetchActiveWinterAlerts` now returns an
**empty list** for an out-of-coverage point **without constructing or
sending any HTTP request** — the coordinate never leaves the process and
`api.weather.gov` never sees it. This makes the package safe for any
consumer that may pass a worldwide point, and avoids spending the
publisher's quota on requests that can only 400.

**In-coverage behavior is unchanged (real errors preserved):** for a
US/territory point a genuine 4xx/5xx from NWS **still throws**
`NoaaNwsHttpException` — only the out-of-coverage case is short-circuited;
a real US error is never swallowed. The retry policy, parser, filters, and
typed area are all unchanged.

### Added

- **`isWithinNwsCoverage(double latitude, double longitude)`** top-level
  predicate (exported): `true` when the point is inside the NWS service
  area — the US **and its territories** — approximated by inclusive
  bounding boxes. Coverage is **not** confined to the Western hemisphere:
  Guam, the Northern Mariana Islands, and the western Aleutians are
  positive-longitude US territories, and American Samoa is Southern
  hemisphere. The boxes:
  - CONUS: lat 24–50 / lon −125..−66
  - Alaska (main): lat 51–72 / lon −170..−129
  - Hawaii: lat 18–23 / lon −161..−154
  - Puerto Rico + US Virgin Islands: lat 17.5–18.7 / lon −67.5..−64.5
  - Guam + Northern Mariana Islands: lat 13.0–21.0 / lon 144.5..146.2
    (positive longitude)
  - American Samoa: lat −14.5..−11.0 / lon −171.2..−168.0 (Southern
    hemisphere)
  - Western Aleutians (west of the antimeridian): lat 51.0–54.0 /
    lon 172.0..180.0 (positive longitude)

  Boxes are deliberately generous supersets of US land — the only failure
  that matters is wrongly excluding covered US land, so over-inclusion
  (which merely costs a lookup that returns no alerts) is the safe
  direction. The positive-longitude Pacific boxes are latitude-disjoint
  from Japan (Japan ~24–46°N; Guam box caps at 21°N, Aleutian box starts
  at 51°N), so no Japanese point is covered. A non-finite coordinate
  (`NaN`, `±Infinity`) reports out-of-coverage.

### Changed

- `fetchActiveWinterAlerts` short-circuits to an empty list for an
  out-of-coverage point before any request is issued (see above). This is
  the only behavior change; the previous 400-throws-on-a-Japan-point
  behavior is gone for out-of-coverage points.

### Tests

- Out-of-coverage point (Akita) returns empty AND issues **no** HTTP
  request (proven with a recording fake client that flags any call).
- In-coverage US point still issues the request and still throws
  `NoaaNwsHttpException` on a simulated 400 (real-error surfacing
  preserved), with the request flag asserted true.
- Coverage-predicate boundaries: CONUS/Alaska/Hawaii interior + inclusive
  edges covered; covered US territories asserted (Puerto Rico, US Virgin
  Islands, Guam, Saipan/N. Mariana, western Aleutians, American Samoa);
  Japan (Akita + Tokyo) and several Japanese points sharing the Guam
  longitude band (Hokkaido, Sapporo, Okinawa, Yonaguni) asserted NOT
  covered; just-outside points and non-finite coordinates reported
  out-of-coverage.

## 0.0.7 — 2026-06-30 — Doc honesty

- Docs: library dartdoc no longer says `internal SNGNav adapter` /
  `Phase: explore` / `publish_to: none` / `Not published to pub.dev`;
  corrected to reflect the published-to-pub.dev state. No code change.

## 0.0.6 — 2026-06-26

- Docs: dev-first on-ramp — install (`dart pub add`) + run-verified quickstart
  snippet now lead the README; governance/mission prose moved to "Background &
  provenance". `example/main.dart` now demonstrates a real alert fetch instead
  of printing client config. No source or behavior change.

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
