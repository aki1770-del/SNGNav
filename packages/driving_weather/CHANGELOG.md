# Changelog

## 0.5.0

### Safety defect in 0.4.4 and earlier — please read

**Versions up to and including 0.4.4 could report weather this package had
never measured.**

* `WeatherCondition.clear()` hardcoded `temperatureCelsius = 5.0`,
  `visibilityMeters = 10000`, `windSpeedKmh = 0.0` and `iceRisk = false`.
* `DigitrafficWeatherProvider` returned exactly that value whenever the advisory
  feed came back **empty**. An empty feed means "no advisory was published". It
  does not mean the road is clear and +5 °C. **If you read temperature or
  `iceRisk` from a Digitraffic-backed provider, you may have been shown +5 °C
  and "no ice" for a road that was in fact freezing.**
* The Digitraffic severity mapping also invented temperature, visibility and
  wind figures (`-4.0 °C`, `150 m`, `40 km/h` for a severe advisory) that
  Digitraffic does not publish at all. It announces road *situations*, and
  measures no weather.
* `OpenMeteoWeatherProvider` fell back to `visibility = 10000` (i.e. "clear")
  and `snowfall = 0` when the hourly block of the response was empty — values
  the API never sent.
* On a **failed** fetch, providers silently re-emitted the last condition with
  no staleness marker, so old data was indistinguishable from fresh data. With
  no previous data they emitted nothing at all, which a UI cannot tell apart
  from "still loading".

pub.dev versions are immutable: we cannot withdraw the affected releases. **This
note is the recall.** If you shipped 0.4.4 or earlier to drivers, assume any
temperature, visibility, wind or ice-risk value that did not come from
`OpenMeteoWeatherProvider`'s `current` block may have been manufactured.

### Breaking: absence of data can no longer be mistaken for good conditions

Measured fields are now **nullable** — `null` means NOT MEASURED, never zero and
never benign. Safety getters are now **tri-state** (`SafetyVerdict`), so
`if (condition.isHazardous)` **no longer compiles**: you will get a compile error
at every site where absent data used to fall through to the "clear road" branch,
and you must decide what to do when the answer is `unknown`.

That compile error is deliberate. It is the whole fix. A deprecation warning
does not stop a loom; it annotates it while it keeps weaving defective cloth.

The verdicts carry a deliberate **asymmetry**: positive evidence of a hazard
fires even when other fields are absent, but the negative verdict ("all clear")
requires complete knowledge. Being offline therefore does not mean "hazard" — it
means `unknown`, which is a state you can tell the driver about, rather than a
green light. (Making absence raise a hazard instead would alert on every coverage
gap, teach the driver the alert means nothing, and get it ignored on the night it
is real.)

#### Migration

| 0.4.4 | 0.5.0 | What to do on `unknown` |
|---|---|---|
| `WeatherCondition.clear()` | **removed** | Use `WeatherCondition.unknown()` for absent data. Use `WeatherCondition.simulatedClear()` only in a simulator. |
| `bool get isHazardous` | `SafetyVerdict get hazard` | Tell the driver the road could not be assessed. Do not render "conditions normal". |
| `bool get isFreezing` | `SafetyVerdict get freezing` | Unknown temperature is not "above freezing". |
| `bool get hasReducedVisibility` | `SafetyVerdict get reducedVisibility` | Unknown visibility is not "you can see fine". |
| `bool get isSnowing` | `SafetyVerdict get snowing` | Unknown precipitation is not "not snowing". |
| `double temperatureCelsius` | `double? temperatureCelsius` | Do not substitute a value. Show "unknown". |
| `double visibilityMeters` | `double? visibilityMeters` | As above. |
| `double windSpeedKmh` | `double? windSpeedKmh` | As above. |
| `bool iceRisk` | `bool? iceRisk` | `null` is not "no ice". |
| `Stream<WeatherCondition> conditions` | `Stream<WeatherReading> conditions` | Switch on `WeatherObserved` / `WeatherStale` / `WeatherUnavailable`. |

**Do not write `?? false` or `?? 0.0` at these sites.** That restores the exact
defect this release exists to remove, in one keystroke, and greps as nothing.

### Also fixed in this release (found while hardening the contract)

- **A malformed 200-response is a FAILURE, not an all-null observation.**
  `parseWeatherResponse` read `json['current']` as a nullable map, so a garbage
  or empty body parsed cleanly into a condition with every field null — and was
  then emitted as `WeatherObserved` (a reading that observed nothing) AND written
  over the last real observation, so the next genuine fetch failure would emit a
  `WeatherStale` carrying an empty husk instead of the driver's last real
  weather. It now throws `WeatherParseException` and routes to
  `WeatherStale` / `WeatherUnavailable` like any other failure. Belt-and-braces:
  a fully-unknown condition never overwrites the last real one.
- **The current hour is no longer substituted by a different hour.**
  `_hourlyValue` clamped the current-hour index into the list, so a TRUNCATED
  `hourly` array (a partial response, a stale cache) silently returned a
  DIFFERENT hour's snowfall or visibility and presented it as "now". A value we
  do not have for this hour is absent — not the last hour we happen to hold.
- **An unstated advisory severity is no longer sorted onto the benign end.** The
  worst-advisory reduce in `DigitrafficWeatherProvider` compared
  `AdvisorySeverity.index`, and `unknown` is declared FIRST in
  `condition_aggregator` — i.e. index 0, the LOWEST. So an advisory whose
  severity the authority never stated silently LOST to a `minor` one and was
  discarded. It now ranks above `minor`/`moderate` (something was declared; how
  bad it is was not) and below the stated `severe`/`extreme`.
- **A declared advisory is not overruled by benign measurements.**
  `WeatherCondition.hazard` returns `unknown` (not `notHazardous`) when a
  `hazardAssertion` of `minor` / `moderate` / `unknown` is present, even if every
  measured field is complete and benign. An authority may know something our
  sensors cannot see.

### Also

* `WeatherCondition` gains `ObservationSource source` (measured / derived /
  simulated) and `HazardAssertion? hazardAssertion`. A hazard **declared** by a
  road authority is now carried as an assertion instead of being laundered into
  fake sensor readings — the alert still reaches the driver (a severe or extreme
  assertion returns `SafetyVerdict.hazardous` even with every measured field
  absent), but nothing is invented to carry it.
* An advisory whose severity the feed does not state maps to
  `HazardAssertion.unknown`, not to `minor` — downgrading an unstated severity to
  the benign end of the scale is the same defect in miniature.
* Fetch failure now emits `WeatherStale` (carrying the real age of the last
  observation, and the cause) or `WeatherUnavailable`, instead of a silently
  re-dated re-emit or silence.
* `SimulatedWeatherProvider` is unchanged in behaviour: a simulator *asserting* a
  scenario is honest, because it is not a claim about the world. Its conditions
  now say so via `ObservationSource.simulated`.
* `SAFETY_BOUNDARY.md` corrected. The 0.4.4 record claimed the package
  "surfaces the data as received" and "never asserts more than it observes".
  Both were false. The record has been corrected downward in the same commit as
  the code — a document claiming a property the code lacks is worse than no
  document.

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

