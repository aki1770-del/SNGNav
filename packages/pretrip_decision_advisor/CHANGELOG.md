# Changelog

## 0.5.0

Humidity-aware black ice — the no-precipitation killer the ambient-only
frost check missed. Envelope-bounded after adversarial review.

- **`SnowAwarePretripAdvisor.hazardOf` gains a radiative-frost condition**:
  when a forecast slot carries relative humidity, the advisor computes the
  Magnus effective road-surface estimate (via `navigation_safety_calibration`
  — the family's single source of truth; the package's FIRST runtime
  dependency, per the depend-don't-copy discipline) and flags **caution**
  when the estimate is at/below freezing while ambient is above zero —
  freezing fog / hoar frost / clear-sky radiative cooling, no precipitation
  required. Caution-add-only (the estimate never exceeds ambient).
- **Bounded to the calibration's documented envelope**: the condition
  requires ambient ≤ `radiativeFrostAmbientCeilingCelsius` (+3.0 °C,
  "several degrees above 0 °C"). The unbounded dew-point test alone fires
  on benign dry days (probe-measured: 20 °C at 25% RH) — adversarial review
  caught the cry-wolf class and the ceiling is the fix, pinned by tests.
- New reason chip `blackIceRadiativeRisk` (EN + JA:
  「放射冷却で路面だけが凍ることがあります(ブラックアイス)」), emitted only for
  the above-zero-ambient window; at/below zero the existing freezing-air
  chip keeps precedence (brief()-level tests pin both the emission and the
  precedence).
- Unit seam, stated precisely: `HourlyForecast.humidityRH` is PERCENT; the
  calibration takes a FRACTION. The guard ADAPTS (does NOT mirror) the
  boundary classes of `navigation_safety_core`'s percent door: core throws
  on implausible input; a briefing must never crash on one dirty forecast
  slot, so here every rejected class — `<= 0` sentinels, everything below a
  5% physical-plausibility floor (which kills the mis-wired-fraction class
  INCLUDING exactly `1.0`, saturated air, its most common value), `> 105`,
  non-finite, and subnormal underflow — simply adds nothing. Absence (or corruption) of data is never presence of hazard,
  and never an exception out of `hazardOf`.
- Honest bound: the calibration's surface-cooling magnitude is documented
  UNVERIFIED-conservative (early-warning direction); see
  KNOWN_LIMITATIONS.md, updated with the full envelope statement.

## 0.4.0

Add the destination-AREA condition read (the FAMILY-THREAD section) — a
PUBLIC-WEATHER-AT-A-PLACE read that watches no person and claims no road.

**BREAKING (source-incompatible for downstream language subclasses):**
`PretripMessages` gained eight required members — `areaOfficialWarning`,
`areaNoOfficialWarning`, `areaWarningCheckUnavailable`, `areaHazardChip`,
`areaHazardBand`, `areaForecastNotCovered`, `areaMeasuredVisibility`,
`areaNoMeasuredVisibility`. Any downstream `class _Xx extends PretripMessages`
(e.g. a Korean locale) must add these eight `area*` overrides to compile.
`PretripMessages.en` / `.ja` carry them; `forLanguage` is unchanged.

Honesty hardening on the area chips:

- `areaOfficialWarning` (en) now frames the verbatim event as "winter warning
  or advisory" so a JMA 注意報 (advisory) is never upgraded to a "warning" in
  English. The verbatim event name still carries the precise class.
- `areaNoOfficialWarning` is scoped to "snow" (en + ja) — it states only the
  negative actually checked (snow-class), never a wider all-winter negative it
  did not verify.

## 0.3.0

Add a localization seam for the reason chips and an offline daylight clock —
**non-breaking**. English stays the default and existing output is byte-for-byte
unchanged; the daylight clock is silent unless a trip opts in via `geo`.

Localization seam:

- Add `PretripMessages` — a hand-rolled, pure-Dart locale table for the
  advisor's reason chips. `PretripMessages.en` (default + fallback) and
  `PretripMessages.ja`; `PretripMessages.forLanguage(code)` resolves one and
  falls back to English for any language not carried (never throws).
- `SnowAwarePretripAdvisor` gains an optional `messages` parameter
  (defaults to `PretripMessages.en`), so every existing caller is unchanged.
  Pass `PretripMessages.ja` to emit the same deterministic logic in Japanese.
- Add abstract `PretripMessages.daylightChip(TripDaylight)`, overridden in
  `en`/`ja`, for the daylight-clock note (below).
- Measured safety numbers (visibility, temperature, minutes, hours) pass
  through every locale verbatim — a translation reorders words, never a value.

Offline daylight clock:

- Add `TripGeo` (latitude/longitude/utcOffset value type), `TripDaylight` +
  `DaylightPhase` (the solar facts for one trip instant — phase, sunrise/sunset
  HH:MM, reference event, minutes-to-event, deep-dark flag; value-equality DTO),
  and the top-level `evaluateDaylight(instant, geo)` — pure Dart, no network and
  no clock, so the answer survives the compound-failure (no GPS / no maps) path.
  It states only light and time and never infers a road hazard from the clock.
- `CommuteShape` gains an optional `geo` field (**defaults `null`** = feature
  absent, fully backward compatible). When set, `brief(...)` adds one daylight
  note for the darkest of departure/arrival/worst-hazard instant; when `null`,
  output is unchanged.
- No behaviour change for existing callers: verdicts, thresholds, and the
  honesty rule are identical across locales and with no `geo`; only the chip
  wording differs by locale, and the daylight note is opt-in via `geo`.

## 0.2.1

Documentation + example only — no API or behaviour change.

- Replace the example with a runnable end-to-end snippet: a measured
  `VisibilityObservation` + `WeatherForecast` → `mergeObservedVisibility` →
  `SnowAwarePretripAdvisor.brief(...)` → the typed verdict/chips an edge
  developer renders in their own UI (the real captured output is shown in the
  README, not hand-written).
- README: add an "End-to-end: measured source → briefing" section, and a
  "Pair with a measured source" table linking `pretrip_source_jma` /
  `pretrip_source_digitraffic` / `pretrip_source_met_norway` (all emit the same
  `VisibilityObservation` / `WeatherForecast`, so you swap region without
  changing UI code). Point to the standalone Flutter reference integration that
  assembles and renders the briefing from the published packages alone.
- Honesty rules unchanged and preserved verbatim: visibility is never
  estimated; a warning never produces a number; an observation is valid for the
  departure hour only; null = the driver's own judgment.

## 0.2.0

The package is no longer interface-only. It now ships a working reference
advisor and the visibility-merge logic, so `pub add`-ing the package gives a
consumer a usable advisor — not just types.

- Add `SnowAwarePretripAdvisor` — a deterministic, pure-Dart reference
  implementation of `PretripAdvisor`. No LLM, no network, no clock: the same
  typed inputs always produce the same recommendation, so the worst-case path
  stays offline. Null forecast fields contribute nothing to hazard scoring;
  the advisor returns `null` when the forecast does not cover the departure
  window, and honours the contract's honesty rule (required/unknown commutes
  are never urged to delay — `honestyMode`).
- Add `PretripBriefing`, `PretripVerdict`, and `HourHazard` — the richer typed
  verdict the reference advisor exposes via `brief(...)` for UIs that want the
  structured result alongside the contract-shaped `PretripRecommendation`.
- Add `VisibilityObservation` + `mergeObservedVisibility(...)` — a
  source-neutral measured-visibility observation and its departure-hour merge
  (the measured value overrides forecast visibility for the departure hour
  only; it is never projected into later hours). Pure Dart; a source-specific
  fetcher that owns the HTTP dependency stays outside this package.
- The package remains pure Dart (no `http`, no Flutter dependency). The
  numerical thresholds the reference advisor uses are documented at their
  declaration site; consumers may still implement `PretripAdvisor` themselves.

## 0.1.2

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.1.1 — 2026-05-10 — Pana score recovery (Theme α P3)

- Trim pubspec `description` to within the pana 60–180 character target.
- Add minimal `example/main.dart` for pana documentation scoring.
- Apply `dart format` to clear any formatter findings.
- No SDK source changes; metadata + format pass only.


## 0.1.0 — 2026-05-08 — Graduation: interface-only contract

The package transitions from internal-only scaffold to a published
interface-only contract on pub.dev. The interface, DTOs, commute shape,
weather forecast inputs, and decoupled driver profile spec are stable
enough to commit to a public surface; reference implementations remain
out of scope at this version.

Founding motivation: the pre-trip departure-timing decision ("should I
leave now or wait an hour?") is often a larger pain point than in-drive
alerts. Apps focused on alerts during driving address a smaller window
than apps that address departure timing. This package defines the shape
of an advisor that could help with that question, so other packages and
applications can experiment against a common interface.

Reference advisor implementations compose this contract with their own
weather data source, route data, and driver-profile bridge. Concrete
advisors must justify their own numerical thresholds; this package
declares none.

KNOWN_LIMITATIONS.md preserves honesty disclosures: API may evolve;
no numerical thresholds; no taxonomy claims; no driver-profile coupling.

## 0.0.1 — 2026-04-30 — Initial scaffold (not published)

Initial scaffold of the abstract advisor contract, recommendation DTO,
commute shape, weather forecast inputs, and decoupled driver profile
spec. Not published to pub.dev.
