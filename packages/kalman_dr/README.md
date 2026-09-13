# kalman_dr

[![pub package](https://img.shields.io/pub/v/kalman_dr.svg)](https://pub.dev/packages/kalman_dr)
[![CI](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml/badge.svg)](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/aki1770-del/SNGNav/blob/main/LICENSE)

**Your app goes blank when GPS drops out.** kalman_dr keeps the position alive.

Use it alongside [geolocator](https://pub.dev/packages/geolocator) — when GPS
fails in tunnels, urban canyons, or parking garages, kalman_dr maintains your
position estimate by extrapolating from your last known speed and heading
(constant-velocity dead reckoning), with honestly-growing uncertainty until
GPS returns.

4D Extended Kalman Filter with covariance-driven accuracy reporting.
Pure Dart, no native dependencies.

## Features

- **4D state vector**: latitude, longitude, speed, heading
- **Provenance, not accuracy, tells you what you are holding**: `position.source`
  answers *"is this real?"*; `position.accuracy` only ever answers *"how
  confident?"*. **Never infer liveness from the accuracy number** — 1 s of dead
  reckoning off a clean 8 m fix reports ~13 m, which reads *better* than a
  genuine 40 m fix under tree cover. See "Reading a position" below.
- **Covariance-driven accuracy**: the uncertainty estimate grows during GPS loss
  rather than freezing — an honest *confidence* number, never a liveness signal
- **Safety cap**: stops at 500m accuracy — no false confidence. **The stream
  emits a terminal error at the cap; register `onError`** (see Quick Start)
- **Two modes**: EKF (full) and linear extrapolation (lightweight)
- **Decorator pattern**: wraps any `LocationProvider` without changing your
  wiring — but the positions it emits are *not* interchangeable with the ones
  it received. Read `source` (see "Reading a position")

## Install

```yaml
dependencies:
  kalman_dr: ^0.6.0
```

## Quick Start

```dart
import 'package:kalman_dr/kalman_dr.dart';

// Create a filter with an initial GPS fix
final filter = KalmanFilter.withState(
  latitude: 35.1709,
  longitude: 136.8815,
  speed: 12.5,
  heading: 90.0,
  timestamp: DateTime.now(),
  initialAccuracy: 5.0,
);

// Predict position forward by 1 second (GPS lost)
final predicted = filter.predict(const Duration(seconds: 1));
print('${predicted.lat}, ${predicted.lon} '
    '(accuracy: ${predicted.accuracy.toStringAsFixed(0)}m)');

// Update when GPS returns
filter.update(
  lat: 35.1710,
  lon: 136.8820,
  speed: 12.8,
  heading: 91.0,
  accuracy: 4.5,
  timestamp: DateTime.now(),
);
```

### Wrap a location provider

```dart
// oracle:placeholders SimulatedLocationProvider
final provider = DeadReckoningProvider(
  inner: SimulatedLocationProvider(), // your own LocationProvider
  mode: DeadReckoningMode.kalman,
);

provider.positions.listen(
  (position) {
    // Receives GPS when available, Kalman predictions when GPS is lost.
    // `source` says which one you are holding; accuracy does not.
    print('${position.latitude}, ${position.longitude} '
        '(${position.source.name}, accuracy: ${position.accuracy}m)');
  },
  // REQUIRED, not optional. When dead reckoning drifts past the 500 m safety
  // cap this stream emits a terminal DeadReckoningAccuracyExceededException.
  // Without onError that becomes an UNCAUGHT error in your zone — and it
  // fires precisely when DR has drifted furthest, which is the deepest point
  // of a GPS outage. That is the worst possible moment for your app to die.
  onError: (Object error) {
    if (error is DeadReckoningAccuracyExceededException) {
      // The estimate is no longer trustworthy and DR has stopped.
      // Tell the driver you no longer know where she is. Do not guess.
    }
  },
);
```

## Reading a position

Every `GeoPosition` states where its coordinate came from. Read `source` before
you use the value for anything a driver depends on.

| `position.source` | What you are holding |
|---|---|
| `PositionSource.measured` | The raw sensor value, unmodified. |
| `PositionSource.fused` | A real reading combined with the filter's prediction. Real evidence contributed, but the blend can still sit several times its own stated `accuracy` from the truth on the first fix after an outage — `extrapolatedFor` tells you how far it has run from evidence. |
| `PositionSource.deadReckoned` | **Pure prediction. No sensor reading contributed.** Where the driver *would* be if nothing had changed. |
| `PositionSource.unknown` | Provenance unstated. |

Three getters ask the question directly:

```dart
// oracle:placeholders position
position.isMeasured;          // raw sensor only
position.containsMeasurement; // measured OR fused — a sensor contributed
position.isDeadReckoned;      // pure prediction, nothing behind it
```

`containsMeasurement` is the one a safety consumer usually means.

### Do not accumulate what was never travelled

The provider keeps emitting on the same stream through a GPS outage — that is
the point of it. Those emissions are *predictions*. If you integrate every
position into a distance total, a path, or a geofence, a stationary device in a
tunnel or an underpass will accumulate distance it did not travel, and a loop
can close on movement that never happened.

Gate on provenance, not on accuracy:

```dart
// oracle:placeholders track, metresBetween, showDegradedGpsQuality, provider
var distanceMeters = 0.0;
GeoPosition? lastFix;
provider.positions.listen((position) {
  if (!position.containsMeasurement) {
    // Prediction. Show it if you like — never bank it.
    showDegradedGpsQuality();
    return;
  }
  final previous = lastFix;
  if (previous != null) {
    distanceMeters += metresBetween(previous, position); // your own haversine
  }
  track.add(position);
  lastFix = position;
});
```

**Never infer liveness from `accuracy`.** One second of dead reckoning off a
clean 8 m fix reports about 13 m, which reads *better* than a genuine 40 m fix
under tree cover. `accuracy` answers *"how confident?"*; only `source` answers
*"is this real?"*.

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

        // Ask the position where it came from. Do NOT infer this from
        // accuracy: one second of dead reckoning off a clean 8 m fix reports
        // ~13 m, which reads *better* than a genuine 40 m fix under tree
        // cover. Accuracy answers "how confident", never "is this real".
        final predicted = position.isDeadReckoned;

        // Provenance is not the whole story, and `false` here is not the same
        // as "fresh". The first fix back out of a tunnel is `fused` — a real
        // reading DID contribute — while the prediction it was blended with
        // ran blind for the whole outage and can still dominate the result.
        // `extrapolatedFor` is the only field that carries that, so read it on
        // this branch too. Since 0.6.0 it is the real gap on every emit, so
        // compare it against a threshold you choose; do not test it for zero.
        final stale = (position.extrapolatedFor ?? Duration.zero) >
            const Duration(seconds: 2);
        return ListTile(
          title: Text(
            '${position.latitude.toStringAsFixed(5)}, '
            '${position.longitude.toStringAsFixed(5)}',
          ),
          subtitle: Text(
            predicted
                ? 'Predicted path — no fix for '
                    '${position.extrapolatedFor?.inSeconds ?? 0}s, accuracy '
                    '${position.accuracy.toStringAsFixed(0)}m'
                : stale
                    ? 'Re-acquiring — first fix after '
                        '${position.extrapolatedFor?.inSeconds ?? 0}s without '
                        'one; accuracy '
                        '${position.accuracy.toStringAsFixed(0)}m is not yet '
                        'settled'
                    : 'Live GPS lock — accuracy '
                        '${position.accuracy.toStringAsFixed(0)}m',
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
| `GeoPosition` | A coordinate that states its own provenance: `source`, `isMeasured`, `containsMeasurement`, `isDeadReckoned`, `extrapolatedFor`. |
| `PositionSource` | `measured` / `fused` / `deadReckoned` / `unknown` — what produced this coordinate. |

## Safety

Display-only position estimates — does not control vehicle systems.
When accuracy exceeds 500m, the provider stops emitting rather than showing
unreliable data. Built with automotive-grade test discipline (77 unit tests),
usable in any Flutter app.

## Works With

| Package | How |
|---------|-----|
| [geolocator](https://pub.dev/packages/geolocator) | Feed geolocator's position stream into `DeadReckoningProvider` |
| [flutter_map](https://pub.dev/packages/flutter_map) | Render predicted positions on the map during GPS loss |
| [latlong2](https://pub.dev/packages/latlong2) | Shared coordinate types |

## See Also

- [routing_engine](https://pub.dev/packages/routing_engine) — Engine-agnostic routing (OSRM + Valhalla)
- [navigation_safety](https://pub.dev/packages/navigation_safety) — Navigation safety state machine
- [offline_tiles](https://pub.dev/packages/offline_tiles) — Offline tile management with MBTiles

Part of [SNGNav](https://github.com/aki1770-del/SNGNav) — 11 packages for
offline-first navigation on Flutter.

## License

BSD-3-Clause — see [LICENSE](LICENSE).
