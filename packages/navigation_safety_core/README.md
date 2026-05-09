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
  navigation_safety_core: ^0.6.0
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
literature-anchored thresholds for visibility, temperature, and score
floors. Pick the one closest to the active driver context; fall back
to `snowZoneExperienced` (the historical default) when uncertain.

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
vehicle-class data should compose their own
`VehicleThresholdOverrides`. Tokens are advisory strings, NOT
control inputs: vehicle-class tunes the warning TIMING only, never
the alert SEVERITY.

Every context input is **conservative-only**: it can make the
thresholds warn earlier than the per-profile baseline, never later.
The per-profile baseline is the floor; vehicle-class overrides apply
AFTER the baseline AND AFTER the live-context adjustments and are
themselves caution-add-only (asserted at runtime in debug builds).

A runnable end-to-end walkthrough lives in
[`example/main.dart`](example/main.dart).

## Concepts

The package separates three orthogonal axes:

| Axis | Type | Question | Lifetime |
|---|---|---|---|
| **Trait** | `DriverProfile` | Who is the driver (class)? | Per-trip / per-session |
| **State** | `DriverState`   | What state are they in right now? | Sub-trip; can change mid-trip |
| **Live conditions** | `DrivingContext` | What does the road / weather look like right now? | Real-time; updates on every sample |

The trait + state pairing is `DriverContext`, anchored to the
trait/state distinction in the driver-distraction literature
(Regan, Hallett & Gordon, 2011). Trait is who the driver is; state is
what state the driver is in right now. The two are independent inputs
to threshold tuning. State adjustments at 0.6.0 are intentionally
small — the API shape is stable; the magnitudes are flagged
UNVERIFIED in [`KNOWN_LIMITATIONS.md`](KNOWN_LIMITATIONS.md) pending
state-axis literature anchoring.

Two runtime helpers ship alongside the threshold config:

- **`AlertDensityThrottle`** — per-profile alerts/min cap with a
  rolling 60-second window. Critical alerts always fire (documented
  invariant); info and warning alerts are gated to prevent driver
  desensitisation. Per-profile cap defaults are anchored to the
  alarm-fatigue and ADAS driver-workload literature.
- **`AlertExplainer`** — pre-localised
  `(condition, action, verbosity, locale)` tuple for each
  `(RoadSurfaceCondition, DriverProfile)` pair. Action vocabulary
  sourced from JAF / MLIT / NEXCO published driver-guidance
  materials. Action mood is advisory ("reduce", "avoid", "maintain"),
  never imperative-on-control.

## Calibration formulas

Three context-dependent calibrations live in
`lib/src/calibration/`:

- **Speed-dependent visibility** (`speed_dependent_visibility.dart`)
  — at higher speed the warning visibility floor must cover reaction
  time + braking distance; the per-profile reaction-time default is
  used to translate a live speed sample into an additional visibility
  margin.
- **Humidity-dependent effective temperature**
  (`humidity_dependent_temperature.dart`) — black ice forms at
  road-surface temperature ≤ 0 °C, which can be several degrees below
  ambient when humidity is high; the dew-point-aware effective
  temperature replaces ambient when it crosses the warning threshold
  earlier.
- **Time-since-precipitation surface moisture**
  (`precipitation_history_decay.dart`) — surface moisture decays
  exponentially after the last rain or snowfall; the residual moisture
  fraction adds a margin to the visibility floor proportional to
  how wet the road still is.

Per-formula citations live in each calibration module's header
comment.

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
PGN payloads they care about (vehicle speed, engine coolant, ambient
air temperature, ABS / TCS engagement, wiper status), maps them into
a `DrivingContext`, and the safety vocabulary handles the rest.

`example/can_bus_integration.dart` walks through the pattern end to
end with two J1939/71 PGNs (CCVS1 0xFEF1 wheel-based vehicle speed;
ET1 0xFEEE engine coolant temperature) as illustrative anchors. The
composition seam is the load-bearing part — the same shape applies
to other vehicle-bus signal sources.

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
- **Not a control surface.** Action verbs in `AlertExplainer` are
  advisory; speed numbers are published reference points, not
  system-enforced limits. The driver retains full control authority.
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
- **`SafetyScore`** — composite score across road-surface,
  visibility, hazard-density, and route-condition axes.
- **`SafetyScenario`** — enumeration of driving-condition scenarios
  used by the score computation.
- **`NavigationRoute`** — typed route representation independent of
  any specific routing engine.

## Further reading

- [`example/main.dart`](example/main.dart) — runnable walkthrough of
  every public surface.
- [`CHANGELOG.md`](CHANGELOG.md) — per-version behaviour deltas.
- [`KNOWN_LIMITATIONS.md`](KNOWN_LIMITATIONS.md) — UNVERIFIED-magnitude
  disclosures, standards-mapping detail, and the full
  equal-dignity-invariant discussion.
- [`LOOMS.md`](LOOMS.md) — runtime-loom catalog (the
  `AlertDensityThrottle` and `AlertExplainer` pair).

## License

BSD-3-Clause. See [LICENSE](LICENSE).
