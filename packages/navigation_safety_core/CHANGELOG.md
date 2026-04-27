# Changelog

## 0.3.0 — 2026-04-27

Closes the V100 gap surfaced by post-0.2.0 autoresearch: the previous
5-profile taxonomy mis-mapped foreign-tourists-in-snow-zone, and two
threshold magnitudes were calibrated by intuition rather than published
literature.

### Added

- **`DriverProfile.foreignTouristSnowZone`** — sixth profile, closes the
  Hokkaido-foreign-tourist class. Combines novice-equivalent
  unfamiliarity with local conditions + likely non-winterised rental
  vehicle + language-localization gaps in road signage. Most-conservative
  defaults across every dimension; previously mis-mapped to either
  `snowZoneExperienced` (catastrophically wrong) or `noviceUrban`
  (location-wrong).
- **`assertUxDifferentiated(profile)`** — advisory hook stub for
  consuming Flutter packages. No-op in 0.3.0; v0.4+ will fire a runtime
  advisory when a profile is selected but the consuming UX layer has
  not registered profile-aware differentiation. Forward-compatible:
  integration code can call it today; it activates when v0.4+ ships.
- **`KNOWN_LIMITATIONS.md`** — honest disclosure of remaining defects
  the 0.3.0 ship does not close, with citations to public sources.

### Changed (calibration corrections per literature)

- **`ageingRural` `infoTemperatureCelsius`**: 5°C → 4°C. The 0.2.0
  value combined with `infoVisibilityMeters` 1500m fired the info tier
  on most autumn evenings in Hokkaido / Tohoku — V14 alert-fatigue
  risk per [arxiv 2410.06388](https://arxiv.org/html/2410.06388) +
  [AAA-FTS ADAS-exposure report](https://aaafoundation.org/wp-content/uploads/2023/09/202309-AAAFTS-ADAS-Exposure-and-Driver-Workload.pdf).
  Lowered to preserve information-tier signal without firing on
  routine cold autumn evenings.
- **`ageingRural` `warningTemperatureCelsius`**: 1°C → 2°C. Black ice
  forms with road-surface ≤0°C even when ambient air is several
  degrees warmer ([Wikipedia black ice](https://en.wikipedia.org/wiki/Black_ice)).
  1°C left no margin above the formation envelope. Raised for
  meaningful margin.
- **`noviceUrban` `warningVisibilityMeters`**: 250m → 320m. Novice
  hazard-perception RT is 3.58s vs 1.32s experienced
  ([PubMed 16313881](https://pubmed.ncbi.nlm.nih.gov/16313881/)); at
  60 km/h that's ~37m additional reaction-distance from RT alone, so
  +50m over standard left no braking margin. 320m gives RT-margin +
  braking margin per
  [Konstantopoulos PubMed 22664714](https://pubmed.ncbi.nlm.nih.gov/22664714/).

### Backwards-compatibility

Default constructor `NavigationSafetyConfig()` is unchanged. All five
0.2.0 profiles still exist and still resolve via `forProfile()`. Only
the *magnitudes* for `ageingRural` (two thresholds) and `noviceUrban`
(one threshold) shift; direction of every shift is preserved.

### Known limitations not closed in 0.3.0

See `KNOWN_LIMITATIONS.md`. Notably: sensory-disability axis,
trait/state separation (Regan-Hallett-Gordon 2011), frailty-vs-robust
split inside `ageingRural`, and the wrong-dimensions concern (UFOV /
glance-budget govern crash risk more strongly than score floors do —
both require coordination with consuming Flutter packages and are
deferred).

## 0.2.0 — 2026-04-27

Added `DriverProfile` enum + `NavigationSafetyConfig.forProfile()` factory
constructor for per-driver-class threshold defaults.

Five profiles in v1, each tuned to a coherent point in the cognitive-load /
experience / role / vehicle-type space:

- `DriverProfile.ageingRural` — older drivers (typically 65+) who may be
  commuting in rural areas; often novice with EV or modern ADAS-equipped
  vehicles. More conservative thresholds (warn earlier on weather +
  visibility; higher score floor for "safe" classification).
- `DriverProfile.snowZoneExperienced` — drivers experienced with
  snow-zone commute conditions. Standard thresholds (the historical
  default profile equivalent).
- `DriverProfile.noviceUrban` — newly-licensed or low-mileage drivers
  (typically first 3 years). Warn earlier on visibility; higher score
  floor; threshold-only shift (explainer-friendly UX surfaces are a
  downstream Flutter-package concern).
- `DriverProfile.professional` — commercial drivers (taxi, freight,
  delivery, rideshare). Standard thresholds; minimum-distraction UX
  optimization is a downstream concern.
- `DriverProfile.agriculturalForestry` — drivers operating off-road
  in agricultural or forestry contexts. Standard thresholds today;
  off-route-awareness semantic is a downstream extension.

Use:

```dart
final config = NavigationSafetyConfig.forProfile(DriverProfile.ageingRural);
```

Backwards-compatible: existing `NavigationSafetyConfig()` call sites
continue to work unchanged (returns the historical default profile
equivalent).

## 0.1.0 — 2026-04-27

Initial release.

Pure Dart core extracted from `navigation_safety` so non-Flutter
consumers (CLI tools, servers, test fixtures, pure-Dart packages
like `driving_conditions`) can depend on the safety-model vocabulary
without inheriting Flutter + flutter_bloc.

Exports:

- `AlertSeverity` (info / warning / critical; declaration order is load-bearing)
- `NavigationRoute`
- `NavigationSafetyConfig`
- `SafetyScenario`
- `SafetyScore`

The full `navigation_safety` Flutter package re-exports everything
here for back-compatibility.
