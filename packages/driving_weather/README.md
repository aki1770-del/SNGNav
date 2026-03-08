# driving_weather

Weather condition model and provider abstraction for driving applications.

## Features

- **WeatherCondition** — Equatable model with precipitation type/intensity,
  temperature, visibility, wind speed, and ice risk
- **WeatherProvider** — Abstract interface for pluggable weather data sources
- **OpenMeteoWeatherProvider** — Real weather from [Open-Meteo](https://open-meteo.com/)
  (free, no API key) with offline fallback
- **SimulatedWeatherProvider** — Demo provider with a realistic mountain-pass
  snow scenario

## Usage

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

### Custom weather source

```dart
class MyFleetWeatherProvider implements WeatherProvider {
  // Implement the 4 methods: conditions, startMonitoring,
  // stopMonitoring, dispose
}
```

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

ASIL-QM — display and advisory only. Not for vehicle control.
