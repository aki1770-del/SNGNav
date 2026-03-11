# fleet_hazard

Fleet telemetry hazard model and geographic clustering for driver-assisting navigation.

## Features

- `FleetReport` model with road condition, timestamp, confidence, and position.
- `HazardZone` cluster model with severity, vehicle count, and average confidence.
- `HazardAggregator` pure-Dart clustering algorithm for snowy and icy reports.
- `FleetProvider` abstract interface so apps can swap simulated, local, or remote telemetry backends.
- Pure Dart package with no Flutter dependency.

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

## See Also

- [kalman_dr](https://pub.dev/packages/kalman_dr) - Dead reckoning through GPS loss
- [routing_engine](https://pub.dev/packages/routing_engine) - Engine-agnostic routing
- [driving_weather](https://pub.dev/packages/driving_weather) - Driving weather condition model
- [driving_consent](https://pub.dev/packages/driving_consent) - Privacy consent with Jidoka semantics
- `navigation_safety` - Flutter navigation safety state machine with pure Dart `_core` models (currently in the SNGNav monorepo)

All six extracted packages are part of [SNGNav](https://github.com/aki1770-del/SNGNav), a driver-assisting navigation reference product.

## License

BSD-3-Clause - see [LICENSE](LICENSE).