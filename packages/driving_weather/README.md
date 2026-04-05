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

## Install

```yaml
dependencies:
  driving_weather: ^0.3.0
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

provider.conditions.listen((condition) {
  print('${condition.precipType.name} ${condition.intensity.name}');
  print('Visibility: ${condition.visibilityMeters}m');

  if (condition.isHazardous) {
    print('⚠ Hazardous conditions detected');
  }
  if (condition.iceRisk) {
    print('⚠ Ice risk — temperature: ${condition.temperatureCelsius}°C');
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
    return StreamBuilder<WeatherCondition>(
      stream: provider.conditions,
      builder: (context, snapshot) {
        final condition = snapshot.data;
        if (condition == null) {
          return const Text('Loading weather...');
        }

        return ListTile(
          title: Text(
            '${condition.precipType.name} '
            '${condition.intensity.name}',
          ),
          subtitle: Text(
            'Visibility ${condition.visibilityMeters.toStringAsFixed(0)}m • '
            'Ice risk ${condition.iceRisk ? 'yes' : 'no'}',
          ),
          trailing: condition.isHazardous
              ? const Icon(Icons.warning_amber_rounded)
              : const Icon(Icons.cloud_outlined),
        );
      },
    );
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
| `WeatherCondition` | Snapshot of precipitation, temperature, visibility, wind, and ice risk. |
| `WeatherProvider` | Abstract interface for live or simulated weather sources. |
| `OpenMeteoWeatherProvider` | Pulls real weather data with offline fallback behavior. |
| `SimulatedWeatherProvider` | Provides deterministic demo and test weather sequences. |

## Model

| Field | Type | Description |
|-------|------|-------------|
| `precipType` | `PrecipitationType` | none, rain, snow, sleet, hail |
| `intensity` | `PrecipitationIntensity` | none, light, moderate, heavy |
| `temperatureCelsius` | `double` | Temperature in °C |
| `visibilityMeters` | `double` | 10000 = clear, <1000 = reduced, <200 = hazardous |
| `windSpeedKmh` | `double` | Wind speed |
| `iceRisk` | `bool` | Black ice / road icing risk |
| `timestamp` | `DateTime` | Observation time |

### Convenience getters

- `isSnowing` — snow at any intensity
- `hasReducedVisibility` — visibility < 1 km
- `isHazardous` — heavy precip, very low visibility, or ice
- `isFreezing` — temperature ≤ 0°C

## Safety

Display and advisory only — does not control vehicle systems.
Built with automotive-grade test discipline, usable in any Flutter app.

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
