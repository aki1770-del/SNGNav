# navigation_safety_core

[![pub package](https://img.shields.io/pub/v/navigation_safety_core.svg)](https://pub.dev/packages/navigation_safety_core)
[![CI](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml/badge.svg)](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/aki1770-del/SNGNav/blob/main/LICENSE)

**Pure-Dart core models for driving-navigation safety.** Threshold
configuration, road-surface vocabulary, alert severity, alert-density
throttle, and an action-coupled alert explainer — tuned per
driver-class, optionally tuned to live driving conditions and live
driver state. Suitable for navigation apps that surface advisory
alerts (winter weather, low visibility, hazardous surface) over a base
map. No Flutter dependency: the Pure-Dart shape lets CLI tools,
server-side logic, test fixtures, and other pure-Dart packages depend
on the safety vocabulary without inheriting Flutter or
`flutter_bloc`. The companion package
[`navigation_safety`](https://pub.dev/packages/navigation_safety)
re-exports everything here and adds a Flutter BLoC layer.

## Quick start

### a. Install + import

Add to `pubspec.yaml`:

```yaml
dependencies:
  navigation_safety_core: ^0.11.0
```

Then import:

```dart
import 'package:navigation_safety_core/navigation_safety_core.dart';
```

### b. Basic usage — `forProfile`

Pick a driver-class profile; receive a config tuned for that class:

```dart
final config = NavigationSafetyConfig.forProfile(
  DriverProfile.snowZoneExperienced,
);

print(config.warningVisibilityMeters);    // 200
print(config.warningTemperatureCelsius);  // 0
```

The six profiles (`ageingRural`, `snowZoneExperienced`, `noviceUrban`,
`professional`, `agriculturalForestry`, `foreignTouristSnowZone`) ship
default thresholds for visibility, temperature, and score floors. The
values are recorded decisions, not population-validated (see
[`KNOWN_LIMITATIONS.md`](KNOWN_LIMITATIONS.md)). Pick the profile
closest to the active driver context; fall back to
`snowZoneExperienced` (the historical default) when uncertain.

### c. Advanced usage — context-aware factories

When the app has live driving conditions (current speed, humidity,
ambient temperature, time-since-precipitation), pass a `DrivingContext`
to `forProfileWithContext` and the relevant thresholds adjust:

```dart
final config = NavigationSafetyConfig.forProfileWithContext(
  DriverProfile.snowZoneExperienced,
  context: const DrivingContext(
    speedMps: 22.2,                                 // ~80 km/h
    humidityRH: 0.92,
    ambientTempCelsius: 1.0,
    timeSincePrecipitation: Duration(minutes: 30),
  ),
);
```

When the app additionally has a live driver-state signal (fatigued,
distracted, sensorily-impaired), pair it with the profile in a
`DriverContext` and pass to `forDriverContext`:

```dart
final config = NavigationSafetyConfig.forDriverContext(
  const DriverContext(
    profile: DriverProfile.snowZoneExperienced,
    state: DriverState.fatigued,
  ),
  environmentalContext: const DrivingContext(speedMps: 22.2),
);
```

### d. Vehicle-class threshold tuning (0.9.0)

When the app has a vehicle-class signal (e.g. a fleet integrator
serving kei-cars in rural Hokkaido), implement
`VehicleClassProvider` and pass the token through `DrivingContext`:

```dart
class MyVehicleClassProvider implements VehicleClassProvider {
  @override
  String? get vehicleClassToken => 'kei-car';
}

final provider = MyVehicleClassProvider();
final config = NavigationSafetyConfig.forProfileWithContext(
  DriverProfile.ageingRural,
  context: DrivingContext(
    speedMps: 18.0,
    vehicleClassToken: provider.vehicleClassToken,
  ),
  vehicleOverrides: VehicleThresholdOverrides.withKeiCarDefault(),
);
```

The built-in `withKeiCarDefault()` registry adds caution to the
warning visibility floor (+50m) and warning temperature (+1°C) for
the `'kei-car'` token; integrators with their own measured
vehicle-class data should build their own registry with
`VehicleThresholdOverrides.validated(...)`. Tokens are advisory
strings, NOT control inputs.

The live driving conditions and the driver state are
**conservative-only** for thresholds: they can make the thresholds warn
earlier than the per-profile baseline, never later. An earlier threshold
has its own cost: `DriverState.impairedVisibility` also moves the info
and critical visibility thresholds earlier, and info and critical alerts
take slots in `AlertDensityThrottle`'s rolling window as warnings do, so
a later warning can be dropped. Vehicle-class overrides apply
AFTER the baseline AND AFTER the live-context adjustments. For a
registry built with a `VehicleThresholdOverrides` constructor, an
override may move only the two warning thresholds, and only earlier;
every other field comes back at its un-overridden value. That is
checked in every build mode, not only in debug builds:
`VehicleThresholdOverrides.validated(...)` refuses a violating
transform at registration, and on the drive path each refused field
goes back to its un-overridden value and is reported. A registry whose
class implements `VehicleThresholdOverrides`, or extends it and
replaces `applyOverrideForToken`, gets these checks only if its method
returns what this package's `applyOverrideForToken` returns. Otherwise
what it returns is applied unchecked and unreported, in every build
mode, even a warning threshold below the per-profile baseline or a
changed critical threshold or cap.

A runnable end-to-end walkthrough lives in
[`example/main.dart`](example/main.dart).

## Concepts

The package separates three orthogonal axes:

| Axis | Type | Question | Lifetime |
|---|---|---|---|
| **Trait** | `DriverProfile` | Who is the driver (class)? | Per-trip / per-session |
| **State** | `DriverState`   | What state are they in right now? | Sub-trip; can change mid-trip |
| **Live conditions** | `DrivingContext` | What does the road / weather look like right now? | Real-time; updates on every sample |

The trait + state pairing is `DriverContext`. The trait/state split is
this package's design. Regan and Strayer 2014 (PMC4001671) list driver
conditions (e.g. young, inexperienced, old) and driver states
(e.g. bored, sleepy, fatigued, drugged, emotional) as factors in
driver inattention. Trait is who the driver is; state is
what state the driver is in right now. The two are independent inputs
to threshold tuning. State adjustments at 0.6.0 are intentionally
small — the API shape is stable; the magnitudes are flagged
UNVERIFIED in [`KNOWN_LIMITATIONS.md`](KNOWN_LIMITATIONS.md) pending
state-axis calibration.

Two runtime helpers ship alongside the threshold config:

- **`AlertDensityThrottle`** — per-profile alerts/min cap with a
  rolling 60-second window. Critical alerts always fire (documented
  invariant); info and warning alerts are gated by the cap, which is
  meant to limit driver desensitisation; that effect has not been
  measured (see [`KNOWN_LIMITATIONS.md`](KNOWN_LIMITATIONS.md)).
  Per-profile cap defaults are a recorded decision; no source is cited
  for the values (see [`KNOWN_LIMITATIONS.md`](KNOWN_LIMITATIONS.md)).
- **`AlertExplainer`** — pre-localised
  `(condition, action, verbosity, locale)` tuple for each
  `(RoadSurfaceCondition, DriverProfile)` pair. The action wording is
  the package's own (a recorded decision). Action mood is advisory
  ("reduce", "avoid", "maintain"), never imperative-on-control.

## Calibration formulas

Three context-dependent calibrations are provided by the standalone
[`navigation_safety_calibration`](https://pub.dev/packages/navigation_safety_calibration)
package (the single source of truth for the meteorological / kinematic
design-default baseline). Since 0.11.0 core **depends on** that package
and **re-exports** it from the barrel, so the three functions are
available directly via
`package:navigation_safety_core/navigation_safety_core.dart` — you do
not need a separate import:

- **Speed-dependent visibility** (`computeSpeedAdjustedVisibilityMeters`)
  — the reaction distance (the per-profile reaction-time default times
  the live speed) plus the braking distance at the default deceleration
  of 5.5 m/s², a dry-pavement value, REPLACES the per-profile warning
  visibility floor when it is longer; it is not added to it. With the
  per-profile floors that happens only above about 134 km/h
  (`agriculturalForestry`) to 179 km/h (`foreignTouristSnowZone`), so at
  ordinary speeds a speed sample leaves the floor unchanged, and
  `forProfileWithContext` has no parameter for a lower snow or ice
  deceleration. (`forDriverContext` adds a further margin of speed
  times a reaction-time penalty for a fatigued or distracted driver.)
- **Humidity-dependent effective temperature**
  (`computeEffectiveTemperatureCelsius`) — black ice forms at
  road-surface temperature ≤ 0 °C. The effective temperature is the
  dew point (Magnus formula), which sits further below ambient the
  DRIER the air: at 2 °C ambient it is 1.28 °C at 95 % RH and
  −7.35 °C at 50 % RH. It therefore covers the dry-to-moderate-humidity
  radiative-frost case and, as the calibration package states, not
  saturated freezing fog above about +1 °C. When the effective
  temperature is at or below the per-profile warning temperature, the
  warning temperature rises by `baseline − floor(effective)`, at most
  10 °C. The effective temperature does not replace ambient in the
  comparison: at 3.0 °C and 70 % RH the effective temperature is
  −1.94 °C, the warning temperature rises from 0 °C to 2 °C, and a
  3.0 °C ambient reading is still above it.
- **Time-since-precipitation surface moisture**
  (`computeSurfaceMoistureFraction`) — surface moisture decays
  exponentially after the last rain or snowfall; the residual moisture
  fraction adds a margin to the visibility floor proportional to
  how wet the road still is.

Each calibration source file's header comment in the
`navigation_safety_calibration` package names the sources cited for its
formula and states which of its values are recorded decisions.

**Determinism note (safety-class).** These constants are the
design-default baseline the driver relies on (Magnus black-ice constants; the
surface-moisture half-life; the braking-distance default, 5.5 m/s², a
dry-pavement value and not a worst case for snow or ice; the
per-profile visibility floor). The calibration package is **caution-add-only — the per-profile
floor never lowers** across its releases. Core pins it at `^0.1.2`;
integrators shipping a product SHOULD commit a `pubspec.lock` so the
exact calibration version is reproducible across builds rather than
floating within the `0.1.x` range.

## Standards mapping

This package is intended for **SAE J3016 Level 0 and Level 1
supportive use** — the driver performs the dynamic driving task at
all times; the package's surfaces inform the driver but never actuate
the vehicle and never close a control loop.

| Standard | Mapping |
|---|---|
| **SAE J3016** | L0 / L1 supportive. **No L2+ claim.** |
| **ISO 26262** | Product-quality scope at the package boundary, not functional-safety scope. The integrator performs the hazard analysis and decides the final ASIL classification for their integration. The package's wording discipline is consistent with QM at the application layer. |
| **JIS / JASO** (Japanese-domestic automotive standards) | Not mapped at this scope. Consult a qualified Japanese-domestic functional-safety partner before any IVI-vendor or OEM-pilot integration that targets the Japanese-domestic certification surface. |

Full standards-mapping detail and the per-formula UNVERIFIED-magnitude
flags live in
[`KNOWN_LIMITATIONS.md`](KNOWN_LIMITATIONS.md#standards-mapping-current-advisory-framing).

## Vehicle Data Integration

Real driving conditions can come from sensors the host app already
has access to. For embedded Linux IVI integrations that read vehicle
CAN traffic, [`j1939`](https://pub.dev/packages/j1939) and the wider
[`can_dart`](https://github.com/jwinarske/can_dart) family (including
`nmea2000`, `nmea2000_bus`, `rvc`, `rvc_bus`) ship the bus-level
plumbing — address claiming, multi-packet transport, DM1 diagnostics
— as Pure-Dart packages on pub.dev. `navigation_safety_core`
composes downstream of those bus events: an integrator decodes the
signals `DrivingContext` has fields for (vehicle speed, ambient air
temperature, relative humidity, time since precipitation), leaves
`null` any it does not measure, which keeps the per-profile baseline
for that dimension, and the safety vocabulary handles the rest. Engine
coolant temperature is not ambient air temperature: passed as
`ambientTempCelsius`, it compares the engine's temperature with the
warning temperature, so once the engine has warmed past it the
temperature warning cannot fire, whatever the air outside. ABS / TCS
engagement and wiper status have no `DrivingContext` field.

`example/can_bus_integration.dart` walks through the pattern with one
J1939/71 PGN decoded from the bus (CCVS1 0xFEF1 wheel-based vehicle
speed) as an illustrative anchor. It decodes no ambient-air, humidity
or precipitation signal: the ambient-air reading comes from a
placeholder labelled as one, for the integrator to replace, and
humidity and precipitation history stay `null`. The composition seam
is the load-bearing part — the same shape applies to other vehicle-bus
signal sources.

## What this is NOT

- **Not an L2+ automation or handover-class supervision package.** Any
  deployment where alert acknowledgment is part of an
  automation-handover safety contract requires the integrator to add
  their own handover-class driver-attention monitoring,
  take-over-request signalling, and minimum-risk-manoeuvre fallback.
- **Not ASIL-certified.** No functional-safety case is asserted at
  the package boundary; the integrator owns the hazard analysis and
  the certification path for their integration.
- **Not JIS / JASO conformant.** Japanese-domestic certification is
  out of scope at this layer.
- **Not a control surface.** Action verbs in `AlertExplainer` are advisory;
  speed numbers are advisory reference points chosen by the package, not system-enforced limits.
  The driver retains full control authority.
- **Not a routing engine.** `NavigationRoute` is a typed route
  representation independent of any specific routing engine; it
  describes a route, it does not compute one.

## Equal-dignity invariant

Alert visibility, severity ordering, and plane-allocation priority in
the consuming HMI MUST be **severity-driven, never profile-driven**.
Per-profile differentiation belongs in verbosity, locale, and
density-cap surfaces (provided by `AlertExplainer` and
`AlertDensityThrottle`); it MUST NOT enter the visibility or
preemption path. See [`KNOWN_LIMITATIONS.md`](KNOWN_LIMITATIONS.md)
for the full discussion.

## Public API surface

- **`NavigationSafetyConfig`** — threshold configuration with three
  factories: `forProfile`, `forProfileWithContext`,
  `forDriverContext`. As of 0.9.0, `forProfileWithContext` accepts an
  optional `vehicleOverrides` parameter for vehicle-class
  threshold tuning.
- **`DriverProfile`** — six driver-class profiles (trait axis).
- **`DriverState`** — four live-state values (transient state axis).
- **`DriverContext`** — trait + state composite.
- **`DrivingContext`** — live driving-conditions value-object. As of
  0.9.0, carries an optional `vehicleClassToken` field.
- **`VehicleClassProvider`** (0.9.0) — abstract interface returning
  `String? get vehicleClassToken` for integrator-supplied
  vehicle-class signals.
- **`VehicleThresholdOverrides`** (0.9.0) — registry of
  vehicle-class-token → caution-adding-only threshold-transform
  mappings; ships a built-in `'kei-car'` default via
  `VehicleThresholdOverrides.withKeiCarDefault()`.
- **`AlertDensityThrottle`** — per-profile alerts/min cap with
  critical-bypass invariant.
- **`AlertExplainer`** — action-coupled per-(condition, profile)
  text with verbosity + locale.
- **`AlertSeverity`** — `info` / `warning` / `critical`. Declaration
  order is load-bearing.
- **`RoadSurfaceCondition`** — eight road-surface vocabulary values
  with a published glossary.
- **`SafetyScore`** — an `overall` score the caller supplies, carried
  with `gripScore`, `visibilityScore` and `fleetConfidenceScore`; each
  is clamped to 0–1, and a non-finite value becomes 0.
  `toAlertSeverity` maps `overall` alone against a config's score
  floors.
- **`SafetyScenario`** — a named, versioned id for the kind of hazard
  an alert describes (a class, not an enum); `WellKnownScenarios`
  holds ready-made ids in the sensing, routing, signal, dynamics and
  hmi categories. Nothing in this package's score uses it.
- **`NavigationRoute`** — typed route representation independent of
  any specific routing engine.

## Further reading

- [`example/main.dart`](example/main.dart) — runnable walkthrough of
  the threshold factories (profile, live context, driver state),
  `AlertDensityThrottle`, `AlertExplainer` and `AlertSeverity`
  ordering. It does not cover `VehicleThresholdOverrides`,
  `VehicleClassProvider`, the circadian, session and confidence
  inputs, `SafetyScore`, `SafetyScenario`, `NavigationRoute`,
  `RoadSurfaceConditionGlossary`, `LoomFitTelemetry`,
  `registerUxDifferentiator` or the calibration functions.
- [`example/can_bus_integration.dart`](example/can_bus_integration.dart)
  — `VehicleThresholdOverrides.withKeiCarDefault()` on a vehicle-bus
  frame stream.
- [`CHANGELOG.md`](CHANGELOG.md) — per-version behaviour deltas.
- [`KNOWN_LIMITATIONS.md`](KNOWN_LIMITATIONS.md) — UNVERIFIED-magnitude
  disclosures, standards-mapping detail, and the full
  equal-dignity-invariant discussion.
- [`LOOMS.md`](LOOMS.md) — runtime-loom catalog (the
  `AlertDensityThrottle` and `AlertExplainer` pair).

## License

BSD-3-Clause. See [LICENSE](LICENSE).
