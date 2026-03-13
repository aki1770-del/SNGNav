# driving_consent

Automotive-grade privacy consent model with Jidoka semantics — UNKNOWN equals DENIED.

## When to use this package

Use `driving_consent` when a data pipeline must stop itself unless the driver
has explicitly granted the exact sharing purpose.

## Features

- **Jidoka gate**: `ConsentStatus.unknown` is treated as denied. The pipeline stops itself.
- **Per-purpose consent**: fleet location, weather telemetry, diagnostics — each independently controlled.
- **Multi-jurisdiction**: GDPR, CCPA, APPI — design for GDPR, deploy everywhere.
- **Pluggable storage**: abstract `ConsentService` interface. Bring your own persistent backend.
- **Pure Dart**: no Flutter dependency. Works in CLI tools, servers, and Flutter apps.

## Install

```yaml
dependencies:
  driving_consent: ^0.1.1
```

## Quick Start

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

## API Overview

| Type | Purpose |
|------|---------|
| `ConsentRecord` | Stores consent status, purpose, jurisdiction, and audit timestamp. |
| `ConsentService` | Abstract interface for reading, granting, revoking, and listing consent state. |
| `InMemoryConsentService` | Ready-to-run in-memory implementation for tests, demos, and offline flows. |
| `ConsentPurpose` | Enumerates independently controlled data-sharing purposes. |
| `ConsentStatus` | Three-state consent gate where `unknown` is treated as denied. |
| `Jurisdiction` | Captures the policy context for the recorded consent decision. |

## See Also

- [kalman_dr](https://pub.dev/packages/kalman_dr) — Dead reckoning through GPS loss (tunnels, urban canyons)
- [routing_engine](https://pub.dev/packages/routing_engine) — Engine-agnostic routing (OSRM, Valhalla, local/public)
- [driving_weather](https://pub.dev/packages/driving_weather) — Weather condition model for driving (snow, ice, visibility)
- [fleet_hazard](https://pub.dev/packages/fleet_hazard) — Fleet telemetry hazard model and geographic clustering
- [driving_conditions](https://pub.dev/packages/driving_conditions) — Pure Dart computation models for road surface, visibility, and safety score simulation
- [navigation_safety](https://pub.dev/packages/navigation_safety) — Flutter navigation safety state machine and safety overlay
- [map_viewport_bloc](https://pub.dev/packages/map_viewport_bloc) — Flutter viewport and layer composition state machine
- [routing_bloc](https://pub.dev/packages/routing_bloc) — Flutter route lifecycle state machine and progress UI
- [offline_tiles](https://pub.dev/packages/offline_tiles) — Flutter offline tile manager with MBTiles fallback

## Part of SNGNav

`driving_consent` is one of the 10 packages in
[SNGNav](https://github.com/aki1770-del/SNGNav), an offline-first,
driver-assisting navigation reference product for embedded Linux.

## License

BSD-3-Clause — see [LICENSE](LICENSE).
