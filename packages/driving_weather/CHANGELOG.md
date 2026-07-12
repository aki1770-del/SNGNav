# Changelog

## 0.4.5

### Safety defect in 0.4.4 and earlier — please read

**Versions up to and including 0.4.4 could report weather this package had
never measured.** When it had no data, it did not say so — it produced a
value that looked like a clear, warm, ice-free road.

* `DigitrafficWeatherProvider` returned `WeatherCondition.clear()` —
  hardcoded `temperatureCelsius = 5.0`, `visibilityMeters = 10000`,
  `windSpeedKmh = 0.0`, `iceRisk = false` — **whenever the advisory feed came
  back empty**. An empty feed means *no advisory was published*. It does not
  mean the road is clear and +5 °C. **If you read temperature or `iceRisk`
  from a Digitraffic-backed provider, you may have been shown +5 °C and
  "no ice" for a road that was in fact freezing.** Black ice is routine with
  zero advisories published.
* On a **failed** fetch, both `DigitrafficWeatherProvider` and
  `OpenMeteoWeatherProvider` silently re-emitted the last condition with no
  staleness marker, so ten-minute-old data was indistinguishable from fresh.
  With no prior data they emitted nothing at all — which a UI cannot tell
  apart from "still loading".
* `OpenMeteoWeatherProvider.parseWeatherResponse` fell back to
  `visibilityMeters = 10000` (i.e. "you can see 10 km") whenever the response's
  `hourly` block was missing, empty or truncated — a figure the API never sent,
  feeding `hasReducedVisibility` and `isHazardous` directly. It also *clamped*
  the current-hour index into a short `hourly` array, so a truncated response
  returned a **different hour's** snowfall or visibility and presented it as now.

pub.dev versions are immutable: we cannot withdraw the affected releases.
**This note is the recall.**

### What changed — absence now STOPS instead of fabricating (non-breaking)

The `WeatherCondition` type in the 0.4.x line has non-nullable fields, so it
cannot represent "unknown". Rather than invent numbers, a provider that has no
data now stops and says why, on the channel it already uses:

* **A new exception type**, `WeatherDataUnavailableException` (with
  `WeatherAbsenceReason.{noAdvisoryPublished, feedUnreachable,
  incompleteResponse}`). Its `message` says what happened, why we will not
  guess, and how to move forward.
* **`DigitrafficWeatherProvider`** now emits this exception as a stream error
  when the advisory feed is empty (`noAdvisoryPublished`) or unreachable
  (`feedUnreachable`), instead of a manufactured clear condition or a
  silently re-dated old one. **Listen with `onError`.**
* **`OpenMeteoWeatherProvider`** now emits the exception on a failed
  (`feedUnreachable`) or incomplete (`incompleteResponse`) fetch. It no longer
  substitutes `visibility = 10000` for a missing hour, and no longer clamps the
  hour index onto a different hour's reading.
* **An unstated advisory severity is no longer sorted onto the benign end.**
  `AdvisorySeverity.unknown` is index 0 in `condition_aggregator`, so the
  worst-advisory reduce made an advisory whose severity the authority never
  stated *lose* to a `minor` one and be discarded. It now ranks above
  `minor`/`moderate` (something was declared; how bad was not) and below the
  stated `severe`/`extreme`.

### This is a source-compatible patch — nothing is removed or re-typed

No field became nullable, no parameter became required, no enum gained a
value, no return type or public member changed. Code that compiled against
0.4.4 compiles against 0.4.5 unchanged. The one behavioural change you must
handle: on absence, the providers' streams now deliver an **error** where they
used to deliver a fabricated condition (or nothing). If your listener has no
`onError`, add one and tell the driver the road could not be assessed — do not
render "conditions normal", and do not substitute a value.

### Migration (two lines)

```dart
provider.conditions.listen(
  showWeather,
  onError: (e) { if (e is WeatherDataUnavailableException) showUnknownRoadState(); },
);
```

To treat absence as a first-class *value* (nullable fields, tri-state safety
verdicts) rather than a stream error, move to the 0.5.x line.

### What this release does NOT fix

* The Digitraffic severity mapping still puts advisory-carrier numbers
  (`-4.0 °C`, `150 m`, `40 km/h`) into a `WeatherCondition` when an advisory is
  present — Digitraffic announces road *situations* and measures no weather, but
  the non-nullable type cannot carry the declaration without them. They err
  toward caution (never a manufactured all-clear); do not read them as
  measurements. The 0.5.x line carries the declaration as an assertion and
  leaves the unmeasured fields null.
* An absent humidity reading still falls through on the radiative-frost path in
  downstream classifiers, as noted in 0.4.4.
* Nothing here has run on a device or been driven from a live feed; every
  absence case is exercised by fixtures.

## 0.4.4

- Add optional `WeatherCondition.humidityRH` (relative humidity in PERCENT,
  nullable). This is the input the in-drive road-surface classifier needs to
  detect radiative-frost black ice — clear-sky cooling that freezes the road
  while the air is still a few degrees above 0 °C. `null` means "not measured",
  never "dry", so absence never fabricates or suppresses a hazard.
- `OpenMeteoWeatherProvider` now requests `relative_humidity_2m` and populates
  `humidityRH`; responses that omit it resolve to `null`. Other providers that
  construct `WeatherCondition` are unaffected (the field defaults to `null`).

## 0.4.3
- docs: correct stale README install pin to current version (no API change).

## 0.4.2 — 2026-06-14 — Dependency hygiene

- Track latest `condition_aggregator` (`^0.0.4`→`^0.0.5`) + `condition_aggregator_digitraffic` (`^0.0.3`→`^0.0.5`).
- No source or behaviour change.


## 0.4.1

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.4.0 — 2026-05-10 — Pana score recovery + dart format alignment

- Trim pubspec `description` to ≤180 characters so search-engine
  snippets surface the package's purpose cleanly.
- Apply `dart format` across `lib/` and `test/` (6 files reformatted)
  to clear pana static-analysis formatter findings.
- No SDK source changes; metadata + formatter pass only.

## 0.3.0

- Harmonize package version to 0.3.0 for Sprint 80 Direction F.
- Align internal ecosystem dependency constraints to ^0.3.0 where applicable.
- No breaking API changes in this package for this release.

