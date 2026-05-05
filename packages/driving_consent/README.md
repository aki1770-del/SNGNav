# driving_consent

[![pub package](https://img.shields.io/pub/v/driving_consent.svg)](https://pub.dev/packages/driving_consent)
[![CI](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml/badge.svg)](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/aki1770-del/SNGNav/blob/main/LICENSE)

**No consent? No data leaves the device.** Privacy-first consent gate where
UNKNOWN equals DENIED — the pipeline stops itself until the user explicitly
grants the exact sharing purpose.

Use `driving_consent` when your app handles location, telemetry, or diagnostic
data and you need GDPR/CCPA/APPI-ready consent management with a safe default.

## Features

- **Jidoka gate**: `ConsentStatus.unknown` is treated as denied. The pipeline stops itself.
- **Per-purpose consent**: fleet location, weather telemetry, diagnostics — each independently controlled.
- **Multi-jurisdiction**: GDPR, CCPA, APPI — design for GDPR, deploy everywhere.
- **Pluggable storage**: abstract `ConsentService` interface. Bring your own persistent backend.
- **Pure Dart**: no Flutter dependency. Works in CLI tools, servers, and Flutter apps.

## Install

```yaml
dependencies:
  driving_consent: ^0.4.0
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

## Integration Pattern

The package is designed to sit at the entrance to any data-sharing feature.
Typical app wiring: query consent before enabling telemetry, render the current
state, and only activate the upstream provider after the driver grants the exact
purpose.

```dart
import 'package:driving_consent/driving_consent.dart';
import 'package:flutter/material.dart';

class FleetConsentGate extends StatefulWidget {
  const FleetConsentGate({super.key});

  @override
  State<FleetConsentGate> createState() => _FleetConsentGateState();
}

class _FleetConsentGateState extends State<FleetConsentGate> {
  final service = InMemoryConsentService();
  late Future<ConsentRecord> consentFuture;

  @override
  void initState() {
    super.initState();
    consentFuture = service.getConsent(ConsentPurpose.fleetLocation);
  }

  Future<void> _grant() async {
    await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.appi);
    setState(() {
      consentFuture = service.getConsent(ConsentPurpose.fleetLocation);
    });
  }

  @override
  void dispose() {
    service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ConsentRecord>(
      future: consentFuture,
      builder: (context, snapshot) {
        final consent = snapshot.data;
        if (consent == null) {
          return const Text('Checking consent...');
        }

        if (consent.isEffectivelyGranted) {
          return const Text('Fleet telemetry enabled');
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Fleet telemetry is blocked: ${consent.status.name}'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _grant,
              child: const Text('Grant consent'),
            ),
          ],
        );
      },
    );
  }
}
```

This is the Jidoka posture in UI form: `unknown` and `denied` both stop the
line until the human makes an explicit choice.

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

## Instrumentation-class consent (0.4.0)

`driving_consent` 0.4.0 adds four instrumentation-class purposes that gate
on-device feedback loops. The driver's app keeps a small per-install record
of how alerts and voice guidance fit her, and the next trip benefits.
Default scope at v0.4.0 is **on-device**; off-device aggregation requires
explicit future scope decisions and is not opened by these purposes.

| Purpose | What it gates |
|---------|---------------|
| `ConsentPurpose.alertExperienceInstrumentation` | Alert-firing records: alert class, severity, modal duration, dismissal pattern. |
| `ConsentPurpose.voiceExperienceInstrumentation` | Voice-pace adjustments: previous and new speech rates, reason for the change. |
| `ConsentPurpose.cohortCalibrationInstrumentation` | Cohort-multiplier observations: which default applied, how well it fit. |
| `ConsentPurpose.tripContextInstrumentation` | Coarse trip context: vehicle class, passenger presence, time of day, driving-day streak. **Zero GPS, zero destination.** |

Each purpose is independent. The driver grants alert-instrumentation
without granting voice-instrumentation. The gate stays per-purpose.

### Recording an event behind the gate

```dart
import 'package:driving_consent/driving_consent.dart';

final consent = InMemoryConsentService();
final instrumentation = InMemoryInstrumentationService(consent);

// Driver explicitly grants alert-instrumentation
await consent.grant(
  ConsentPurpose.alertExperienceInstrumentation,
  Jurisdiction.appi,
);

// Record an event — Jidoka throws StateError if consent is not granted.
await instrumentation.recordEvent(
  ConsentPurpose.alertExperienceInstrumentation,
  AlertFired(
    timestamp: DateTime.now(),
    driverPseudonym: instrumentation.driverPseudonym,
    alertClass: 'snow_road_warning',
    severity: AlertSeverityClass.warning,
    modalDuration: const Duration(seconds: 6),
    dismissalState: AlertDismissalState.ranToCompletion,
    driverProfile: DriverProfileClass.snowZoneExperienced,
  ),
);

// Read back for on-device calibration
final recent = await instrumentation.readEvents(
  purpose: ConsentPurpose.alertExperienceInstrumentation,
  since: DateTime.now().subtract(const Duration(days: 7)),
);
```

### `AlertInstrumentationGateway` pattern

Wrap `InstrumentationService` behind a per-feature gateway so feature code
stays free of consent-checking boilerplate while the gateway concentrates
the Jidoka discipline at one boundary.

```dart
class AlertInstrumentationGateway {
  AlertInstrumentationGateway(this._instrumentation);
  final InstrumentationService _instrumentation;

  Future<void> onAlertFired({
    required String alertClass,
    required AlertSeverityClass severity,
    required Duration modalDuration,
    required AlertDismissalState dismissalState,
    required DriverProfileClass driverProfile,
  }) async {
    try {
      await _instrumentation.recordEvent(
        ConsentPurpose.alertExperienceInstrumentation,
        AlertFired(
          timestamp: DateTime.now(),
          driverPseudonym: _instrumentation.driverPseudonym,
          alertClass: alertClass,
          severity: severity,
          modalDuration: modalDuration,
          dismissalState: dismissalState,
          driverProfile: driverProfile,
        ),
      );
    } on StateError {
      // Consent not granted — drop silently. The line stops itself.
    }
  }

  Future<List<InstrumentationEvent>> recentAlerts({Duration? window}) {
    final since =
        window == null ? null : DateTime.now().subtract(window);
    return _instrumentation.readEvents(
      purpose: ConsentPurpose.alertExperienceInstrumentation,
      since: since,
    );
  }
}
```

The gateway is the only place that mentions the consent purpose. The
feature code calls `gateway.onAlertFired(...)` and never reasons about
consent at all.

## API Overview

| Type | Purpose |
|------|---------|
| `ConsentRecord` | Stores consent status, purpose, jurisdiction, and audit timestamp. |
| `ConsentService` | Abstract interface for reading, granting, revoking, and listing consent state. |
| `InMemoryConsentService` | Ready-to-run in-memory implementation for tests, demos, and offline flows. |
| `ConsentPurpose` | Enumerates independently controlled data-sharing purposes. |
| `ConsentStatus` | Three-state consent gate where `unknown` is treated as denied. |
| `Jurisdiction` | Captures the policy context for the recorded consent decision. |
| `InstrumentationService` | Abstract interface for recording, reading, retaining, and deleting instrumentation events. |
| `InMemoryInstrumentationService` | Ready-to-run in-memory implementation; **not for production**. |
| `InstrumentationEvent` | Sealed parent for the closed set of event subtypes. |
| `AlertFired` / `VoicePaceAdjusted` / `CohortMultiplierObserved` / `TripContextCaptured` | The four event subtypes. |

## Works With

| Package | How |
|---------|-----|
| [fleet_hazard](https://pub.dev/packages/fleet_hazard) | Gate fleet location sharing with per-purpose consent |
| [driving_weather](https://pub.dev/packages/driving_weather) | Gate weather telemetry sharing with per-purpose consent |
| [navigation_safety](https://pub.dev/packages/navigation_safety) | Consent state informs which safety data pipelines are active |

## See Also

- [kalman_dr](https://pub.dev/packages/kalman_dr) — Dead reckoning through GPS loss
- [routing_engine](https://pub.dev/packages/routing_engine) — Engine-agnostic routing
- [offline_tiles](https://pub.dev/packages/offline_tiles) — Offline tile management with MBTiles

Part of [SNGNav](https://github.com/aki1770-del/SNGNav) — 11 packages for
offline-first navigation on Flutter.

## License

BSD-3-Clause — see [LICENSE](LICENSE).
