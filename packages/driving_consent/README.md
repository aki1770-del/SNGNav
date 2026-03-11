# driving_consent

Automotive-grade privacy consent model with Jidoka semantics — UNKNOWN equals DENIED.

## Features

- **Jidoka gate**: `ConsentStatus.unknown` is treated as denied. The pipeline stops itself.
- **Per-purpose consent**: fleet location, weather telemetry, diagnostics — each independently controlled.
- **Multi-jurisdiction**: GDPR, CCPA, APPI — design for GDPR, deploy everywhere.
- **Pluggable storage**: abstract `ConsentService` interface. Bring your own persistent backend.
- **Pure Dart**: no Flutter dependency. Works in CLI tools, servers, and Flutter apps.

## Usage

```dart
import 'package:driving_consent/driving_consent.dart';

final service = InMemoryConsentService();

// Jidoka gate — check before any data leaves the device
final consent = await service.getConsent(ConsentPurpose.fleetLocation);
if (!consent.isEffectivelyGranted) {
  // UNKNOWN or DENIED — pipeline stops. No data sent.
  return;
}

// Driver explicitly grants consent
await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.appi);

// Driver revokes — pipeline stops again
await service.revoke(ConsentPurpose.fleetLocation);
```

### Implement a persistent service

```dart
class MyPersistentConsentService implements ConsentService {
  @override
  Future<ConsentRecord> getConsent(ConsentPurpose purpose) async {
    // Read from your database
  }

  @override
  Future<List<ConsentRecord>> getAllConsents() async {
    // Read all purposes from your database
  }

  @override
  Future<ConsentRecord> grant(
    ConsentPurpose purpose,
    Jurisdiction jurisdiction,
  ) async {
    // Write granted record + audit trail
  }

  @override
  Future<ConsentRecord> revoke(ConsentPurpose purpose) async {
    // Write denied record + audit trail
  }

  @override
  Future<void> dispose() async {
    // Close database
  }
}
```

## See Also

- [kalman_dr](https://pub.dev/packages/kalman_dr) — Dead reckoning through GPS loss (tunnels, urban canyons)
- [routing_engine](https://pub.dev/packages/routing_engine) — Engine-agnostic routing (OSRM, Valhalla, local/public)
- [driving_weather](https://pub.dev/packages/driving_weather) — Weather condition model for driving (snow, ice, visibility)
- [fleet_hazard](https://pub.dev/packages/fleet_hazard) — Fleet telemetry hazard model and geographic clustering
- `navigation_safety` — Flutter navigation safety state machine with pure Dart `_core` models (currently in the SNGNav monorepo)
- `map_viewport_bloc` — Flutter viewport state machine with pure Dart `_core` models (currently in the SNGNav monorepo)
- `routing_bloc` — Flutter route lifecycle state machine with pure Dart `_core` models (currently in the SNGNav monorepo)
- `offline_tiles` — Flutter offline tile manager with pure Dart `_core` models (currently in the SNGNav monorepo)

All nine extracted packages are part of [SNGNav](https://github.com/aki1770-del/SNGNav), a driver-assisting navigation reference product.

## License

BSD-3-Clause — see [LICENSE](LICENSE).
