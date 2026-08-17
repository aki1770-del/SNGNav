# driving_weather

[![pub package](https://img.shields.io/pub/v/driving_weather.svg)](https://pub.dev/packages/driving_weather)
[![CI](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml/badge.svg)](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/aki1770-del/SNGNav/blob/main/LICENSE)

**Know when road conditions turn dangerous.** Real-time weather monitoring with
snow, ice, and visibility hazard detection — no API key required.

Use `driving_weather` when your app needs to warn drivers about hazardous
conditions. Pluggable providers: real weather from Open-Meteo (free) or
simulated scenarios for demos and testing.

## Features

- **WeatherCondition** — Equatable model with precipitation type/intensity,
  temperature, visibility, wind speed, and ice risk
- **WeatherProvider** — Abstract interface for pluggable weather data sources
- **OpenMeteoWeatherProvider** — Real weather from [Open-Meteo](https://open-meteo.com/)
  (free, no API key) with offline fallback
- **SimulatedWeatherProvider** — Demo provider with a realistic mountain-pass
  snow scenario

## It will not tell you something it did not measure

This is the package's central promise, and in versions up to 0.4.4 it was
broken — an empty advisory feed produced a fabricated `+5.0 °C, no ice`. See
[CHANGELOG 0.5.0](CHANGELOG.md) for the full disclosure and migration table.

- Every measured field is **nullable**. `null` means NOT MEASURED — never zero,
  never benign, never "clear".
- Safety verdicts are **tri-state** (`SafetyVerdict`), never `bool`. A `bool`
  cannot say "I don't know", so it resolves absence into its `false` branch —
  which for a hazard question is the *clear road* branch.
- A failed fetch is a `WeatherStale` or `WeatherUnavailable` reading, not a
  silently re-dated old value.

Positive hazard evidence fires even on partial data; only the *negative* verdict
("all clear") requires complete data. So going offline does not raise a false
alarm — it reports `unknown`, which you can actually tell the driver.

## Install

```yaml
dependencies:
  driving_weather: ^0.5.0
```

## Quick Start

```dart
import 'package:driving_weather/driving_weather.dart';

// Real weather from Open-Meteo (Nagoya region default)
final provider = OpenMeteoWeatherProvider(
  latitude: 35.18,
  longitude: 136.91,
);
await provider.startMonitoring();

provider.conditions.listen((reading) {
  switch (reading) {
    case WeatherObserved(:final condition):
      switch (condition.hazard) {
        case SafetyVerdict.hazardous:
          print('⚠ Hazardous conditions detected');
        case SafetyVerdict.notHazardous:
          print('Assessed: no hazard');
        case SafetyVerdict.unknown:
          // NOT a green light. Nobody measured the road — say so.
          print('Conditions unavailable — drive to what you can see');
      }
    case WeatherStale(:final lastKnown, :final age):
      print('Stale (${age.inMinutes} min old): ${lastKnown.precipType?.name}');
    case WeatherUnavailable():
      print('No weather data');
  }
});
```

### Simulated weather (for demos and testing)

```dart
final sim = SimulatedWeatherProvider(
  interval: Duration(seconds: 5),
);
await sim.startMonitoring();
// Cycles: clear → light snow → moderate → heavy → ice → clearing
```

## Integration Pattern

The usual app pattern is: start one weather provider in `initState`, subscribe
through `StreamBuilder`, and convert the raw condition into a compact status bar
or alert strip. This keeps the weather source swappable while the UI stays
stable.

```dart
import 'package:driving_weather/driving_weather.dart';
import 'package:flutter/material.dart';

class WeatherBanner extends StatefulWidget {
  const WeatherBanner({super.key});

  @override
  State<WeatherBanner> createState() => _WeatherBannerState();
}

class _WeatherBannerState extends State<WeatherBanner> {
  late final WeatherProvider provider;

  @override
  void initState() {
    super.initState();
    provider = SimulatedWeatherProvider(
      interval: const Duration(seconds: 5),
    )..startMonitoring();
  }

  @override
  void dispose() {
    provider.stopMonitoring();
    provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WeatherReading>(
      stream: provider.conditions,
      builder: (context, snapshot) {
        final reading = snapshot.data;
        if (reading == null) {
          return const Text('Loading weather...');
        }

        return switch (reading) {
          WeatherObserved(:final condition) => ListTile(
              title: Text(
                '${condition.precipType?.name ?? 'unknown'} '
                '${condition.intensity?.name ?? ''}',
              ),
              subtitle: Text(_describe(condition)),
              trailing: switch (condition.hazard) {
                SafetyVerdict.hazardous =>
                  const Icon(Icons.warning_amber_rounded),
                SafetyVerdict.notHazardous =>
                  const Icon(Icons.cloud_outlined),
                // Absence is shown as absence — never as a calm sky.
                SafetyVerdict.unknown => const Icon(Icons.help_outline),
              },
            ),
          WeatherStale(:final age) => ListTile(
              title: const Text('Weather data is stale'),
              subtitle: Text('Last observed ${age.inMinutes} min ago'),
              trailing: const Icon(Icons.history),
            ),
          WeatherUnavailable() => const ListTile(
              title: Text('No weather data'),
              subtitle: Text('Conditions unknown — drive to what you can see'),
              trailing: Icon(Icons.cloud_off),
            ),
        };
      },
    );
  }

  // Render absence as absence. Never substitute a value.
  String _describe(WeatherCondition c) {
    final visibility = c.visibilityMeters == null
        ? 'Visibility unknown'
        : 'Visibility ${c.visibilityMeters!.toStringAsFixed(0)}m';
    final ice = switch (c.iceRisk) {
      true => 'Ice risk yes',
      false => 'Ice risk no',
      null => 'Ice risk unknown',
    };
    return '$visibility • $ice';
  }
}
```

Swap `SimulatedWeatherProvider` for `OpenMeteoWeatherProvider` when you move
from demo mode to live weather. The widget contract does not have to change.

### Custom weather source

```dart
class MyFleetWeatherProvider implements WeatherProvider {
  // Implement the 4 methods: conditions, startMonitoring,
  // stopMonitoring, dispose
}
```

## API Overview

| Type | Purpose |
|------|---------|
| `WeatherCondition` | Snapshot of precipitation, temperature, visibility, wind, and ice risk — each of which may be *absent*. |
| `WeatherReading` | Sealed: `WeatherObserved` \| `WeatherStale` \| `WeatherUnavailable`. What a provider actually hands you. |
| `SafetyVerdict` | `hazardous` \| `notHazardous` \| `unknown`. The third one is the point. |
| `ObservationSource` | `measured` \| `derived` \| `simulated` — provenance of the fields that are present. |
| `HazardAssertion` | A hazard *declared* by a road authority, as distinct from one *measured* by a sensor. |
| `WeatherProvider` | Abstract interface for live or simulated weather sources. |
| `OpenMeteoWeatherProvider` | Pulls real weather data; reports staleness rather than concealing it. |
| `DigitrafficWeatherProvider` | Finnish road-authority advisories, carried as an assertion — never as invented sensor values. |
| `SimulatedWeatherProvider` | Deterministic demo/test sequences, labelled `simulated`. |

## Model

**Every measured field is nullable, and `null` means NOT MEASURED.**

| Field | Type | Description |
|-------|------|-------------|
| `precipType` | `PrecipitationType?` | none, rain, snow, sleet, hail. `null` ≠ `none`. |
| `intensity` | `PrecipitationIntensity?` | none, light, moderate, heavy |
| `temperatureCelsius` | `double?` | °C. `null` never means "above freezing". |
| `visibilityMeters` | `double?` | 10000 = clear, <1000 = reduced, <200 = hazardous. `null` never means "clear". |
| `windSpeedKmh` | `double?` | `null` never means "calm". |
| `iceRisk` | `bool?` | Black ice / road icing risk. `null` never means "no ice". |
| `humidityRH` | `double?` | Relative humidity %, for radiative-frost black ice. |
| `hazardAssertion` | `HazardAssertion?` | Severity *declared* by an authority. |
| `source` | `ObservationSource` | Provenance of the present fields (required). |
| `timestamp` | `DateTime` | Observation time |

### Safety verdicts (tri-state — never `bool`)

- `hazard` — heavy precip, visibility < 200 m, ice risk, or a severe/extreme
  authority assertion. Fires on **partial** data. Returns `notHazardous` only
  when ice risk, intensity *and* visibility are all known and none fired;
  otherwise `unknown`.
- `snowing` — `unknown` when precipitation was not reported.
- `reducedVisibility` — `unknown` when visibility was not measured.
- `freezing` — `unknown` when temperature was not measured.

`unknown` is not a green light. Show it to the driver.

## Safety

Display and advisory only — does not control vehicle systems.
Built with automotive-grade test discipline, usable in any Flutter app.

See [`SAFETY_BOUNDARY.md`](SAFETY_BOUNDARY.md) for the full safety-class boundary
record, including the §0 correction notice and a known SOTIF performance
insufficiency that is *not* fixed in 0.5.0 (sub-zero clear-sky residual ice).

## Works With

| Package | How |
|---------|-----|
| [driving_conditions](https://pub.dev/packages/driving_conditions) | Converts weather into road surface, grip, and safety scores |
| [navigation_safety](https://pub.dev/packages/navigation_safety) | Displays weather-driven safety alerts to the driver |
| [fleet_hazard](https://pub.dev/packages/fleet_hazard) | Correlates weather with fleet-reported road hazards |

## See Also

- [kalman_dr](https://pub.dev/packages/kalman_dr) — Dead reckoning through GPS loss
- [routing_engine](https://pub.dev/packages/routing_engine) — Engine-agnostic routing (OSRM + Valhalla)
- [driving_consent](https://pub.dev/packages/driving_consent) — Privacy consent with Jidoka semantics

Part of [SNGNav](https://github.com/aki1770-del/SNGNav) — 11 packages for
offline-first navigation on Flutter.

## License

BSD-3-Clause — see [LICENSE](LICENSE).
