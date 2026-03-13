# kalman_dr

[![pub package](https://img.shields.io/pub/v/kalman_dr.svg)](https://pub.dev/packages/kalman_dr)
[![CI](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml/badge.svg)](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/aki1770-del/SNGNav/blob/main/LICENSE)

Kalman filter dead reckoning for Dart location services.

A 4D Extended Kalman Filter that predicts position through GPS loss using
covariance-driven accuracy reporting. Pure Dart, no native dependencies.

## When to use this package

Use `kalman_dr` when your app already has a location provider and you need GPS
loss survivability with explicit uncertainty reporting instead of a blank map.

## Features

- **4D state vector**: latitude, longitude, speed, heading
- **Covariance-driven accuracy**: honestly degrades over time during GPS loss
- **Safety cap**: stops at 500m accuracy — no false confidence
- **Two modes**: EKF (full) and linear extrapolation (lightweight)
- **Decorator pattern**: wraps any `LocationProvider` transparently

## Install

```yaml
dependencies:
  kalman_dr: ^0.2.0
```

## Quick Start

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

## Integration Pattern

The package becomes most useful when it sits between your raw location source
and the rest of the Flutter app. The pattern is: create the underlying GPS
provider once, wrap it with `DeadReckoningProvider`, then surface the stream in
UI code that can explain when the app is running on prediction instead of live
GPS.

```dart
import 'package:flutter/material.dart';
import 'package:kalman_dr/kalman_dr.dart';

class DeadReckoningStatusCard extends StatefulWidget {
  const DeadReckoningStatusCard({
    super.key,
    required this.gpsProvider,
  });

  final LocationProvider gpsProvider;

  @override
  State<DeadReckoningStatusCard> createState() =>
      _DeadReckoningStatusCardState();
}

class _DeadReckoningStatusCardState extends State<DeadReckoningStatusCard> {
  late final DeadReckoningProvider provider;

  @override
  void initState() {
    super.initState();
    provider = DeadReckoningProvider(
      inner: widget.gpsProvider,
      mode: DeadReckoningMode.kalman,
    );
    provider.start();
  }

  @override
  void dispose() {
    provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<GeoPosition>(
      stream: provider.positions,
      builder: (context, snapshot) {
        final position = snapshot.data;
        if (position == null) {
          return const Text('Waiting for location...');
        }

        final degraded = position.accuracyMetres > 25;
        return ListTile(
          title: Text(
            '${position.latitude.toStringAsFixed(5)}, '
            '${position.longitude.toStringAsFixed(5)}',
          ),
          subtitle: Text(
            degraded
                ? 'Predicted path — accuracy '
                    '${position.accuracyMetres.toStringAsFixed(0)}m'
                : 'Live GPS lock — accuracy '
                    '${position.accuracyMetres.toStringAsFixed(0)}m',
          ),
        );
      },
    );
  }
}
```

This is the tunnel pattern: keep the location pipeline alive, surface the
degraded confidence honestly, and let the rest of the map/navigation stack keep
rendering instead of freezing.

## API Overview

| Type | Purpose |
|------|---------|
| `KalmanFilter` | Predicts and updates the 4D state vector for dead reckoning. |
| `DeadReckoningProvider` | Wraps a location provider and emits predicted positions during GPS loss. |
| `DeadReckoningMode` | Selects EKF or linear extrapolation mode. |
| `KalmanPosition` | Carries predicted position, speed, heading, timestamp, and accuracy. |

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

## Part of SNGNav

`kalman_dr` is one of the 10 packages in
[SNGNav](https://github.com/aki1770-del/SNGNav), an offline-first,
driver-assisting navigation reference product for embedded Linux.

## License

BSD-3-Clause — see [LICENSE](LICENSE).
