# fleet_hazard

Fleet telemetry hazard model and geographic clustering for driver-assisting navigation.

## Features

- `FleetReport` model with road condition, timestamp, confidence, and position.
- `HazardZone` cluster model with severity, vehicle count, and average confidence.
- `HazardAggregator` pure-Dart clustering algorithm for snowy and icy reports.
- `FleetProvider` abstract interface so apps can swap simulated, local, or remote telemetry backends.
- Pure Dart package with no Flutter dependency.

## Install

```yaml
dependencies:
  fleet_hazard: ^0.1.1
```

## Usage

```dart
import 'package:fleet_hazard/fleet_hazard.dart';
import 'package:latlong2/latlong.dart';

final reports = [
  FleetReport(
    vehicleId: 'V-001',
    position: const LatLng(35.050, 137.250),
    timestamp: DateTime.now(),
    condition: RoadCondition.snowy,
  ),
  FleetReport(
    vehicleId: 'V-002',
    position: const LatLng(35.052, 137.252),
    timestamp: DateTime.now(),
    condition: RoadCondition.icy,
  ),
];

final zones = HazardAggregator.aggregate(reports);

for (final zone in zones) {
  print('${zone.severity.name}: ${zone.vehicleCount} vehicles');
}
```

## Implement a provider

```dart
class MyFleetProvider implements FleetProvider {
  @override
  Stream<FleetReport> get reports => _controller.stream;

  @override
  Future<void> startListening() async {
    // Connect to your telemetry source
  }

  @override
  Future<void> stopListening() async {
    // Stop updates
  }

  @override
  void dispose() {
    // Release resources
  }
}
```

## API Overview

| Type | Purpose |
|------|---------|
| `FleetReport` | Individual vehicle report carrying position, road condition, confidence, and timestamp. |
| `HazardZone` | Clustered geographic hazard summary with severity and confidence rollups. |
| `HazardAggregator` | Pure Dart clustering algorithm that converts reports into hazard zones. |
| `FleetProvider` | Stream-based interface for simulated, local, or remote fleet telemetry sources. |
| `RoadCondition` | Canonical hazard labels such as `dry`, `snowy`, and `icy`. |

## See Also

- [kalman_dr](https://pub.dev/packages/kalman_dr) — Dead reckoning through GPS loss (tunnels, urban canyons)
- [routing_engine](https://pub.dev/packages/routing_engine) — Engine-agnostic routing (OSRM + Valhalla)
- [driving_weather](https://pub.dev/packages/driving_weather) — Weather condition model for driving (snow, ice, visibility)
- [driving_consent](https://pub.dev/packages/driving_consent) — Privacy consent with Jidoka semantics (UNKNOWN = DENIED)
- [driving_conditions](https://pub.dev/packages/driving_conditions) — Pure Dart computation models for road surface, visibility, and safety score simulation
- [navigation_safety](https://pub.dev/packages/navigation_safety) — Flutter navigation safety state machine and safety overlay
- [map_viewport_bloc](https://pub.dev/packages/map_viewport_bloc) — Flutter viewport and layer composition state machine
- [routing_bloc](https://pub.dev/packages/routing_bloc) — Flutter route lifecycle state machine and progress UI
- [offline_tiles](https://pub.dev/packages/offline_tiles) — Flutter offline tile manager with MBTiles fallback

All ten extracted packages are part of [SNGNav](https://github.com/aki1770-del/SNGNav), a driver-assisting navigation reference product.

## License

BSD-3-Clause — see [LICENSE](LICENSE).