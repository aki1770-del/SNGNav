# kalman_dr

Kalman filter dead reckoning for Dart location services.

A 4D Extended Kalman Filter that predicts position through GPS loss using
covariance-driven accuracy reporting. Pure Dart, no native dependencies.

## Features

- **4D state vector**: latitude, longitude, speed, heading
- **Covariance-driven accuracy**: honestly degrades over time during GPS loss
- **Safety cap**: stops at 500m accuracy — no false confidence
- **Two modes**: EKF (full) and linear extrapolation (lightweight)
- **Decorator pattern**: wraps any `LocationProvider` transparently

## Usage

```dart
import 'package:kalman_dr/kalman_dr.dart';

// Create a Kalman filter
final kf = KalmanFilter();

// Predict position forward by 1 second
final predicted = kf.predict(const Duration(seconds: 1));

// Update with a GPS measurement
final updated = kf.update(
  latitude: 35.1709,
  longitude: 136.8815,
  accuracy: 5.0,
  speed: 12.5,
  heading: 90.0,
);
```

### Wrap a location provider

```dart
final provider = DeadReckoningProvider(
  inner: SimulatedLocationProvider(),
  mode: DeadReckoningMode.kalman,
);

provider.positions.listen((position) {
  // Receives GPS when available, Kalman predictions when GPS is lost
  print('${position.latitude}, ${position.longitude} '
      '(accuracy: ${position.accuracyMetres}m)');
});
```

## Safety Classification

ASIL-QM (display only). The filter provides position estimates for display
purposes. It does not control vehicle systems. When accuracy exceeds the
500m safety cap, the provider stops emitting positions rather than showing
unreliable data.

## See Also

- [routing_engine](https://pub.dev/packages/routing_engine) — Engine-agnostic routing (OSRM + Valhalla, local/public)
- [driving_weather](https://pub.dev/packages/driving_weather) — Weather condition model for driving (snow, ice, visibility)
- [driving_consent](https://pub.dev/packages/driving_consent) — Privacy consent with Jidoka semantics (UNKNOWN = DENIED)
- [fleet_hazard](https://pub.dev/packages/fleet_hazard) — Fleet telemetry hazard model and geographic clustering
- [driving_conditions](https://pub.dev/packages/driving_conditions) — Pure Dart computation models for road surface, visibility, and safety score simulation
- [navigation_safety](https://pub.dev/packages/navigation_safety) — Flutter navigation safety state machine and safety overlay
- [map_viewport_bloc](https://pub.dev/packages/map_viewport_bloc) — Flutter viewport and layer composition state machine
- [routing_bloc](https://pub.dev/packages/routing_bloc) — Flutter route lifecycle state machine and progress UI
- [offline_tiles](https://pub.dev/packages/offline_tiles) — Flutter offline tile manager with MBTiles fallback

All ten extracted packages are part of [SNGNav](https://github.com/aki1770-del/SNGNav), a driver-assisting navigation reference product.

## License

BSD-3-Clause — see [LICENSE](LICENSE).
