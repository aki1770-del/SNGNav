# condition_aggregator_nws

NOAA / NWS adapter for the `condition_aggregator` interface. Wraps
`noaa_nws_adapter`'s `NoaaNwsClient.fetchActiveWinterAlerts` and maps
each `WinterAlert` to the source-neutral `Advisory` typed event at the
adapter boundary.

**Phase**: explore (`publish_to: none` in `pubspec.yaml`).
Deploy graduation requires the FDD spike-to-package promotion gate.

Pure Dart. No Flutter dependency. Runtime dependencies:
`condition_aggregator` (interface) + `noaa_nws_adapter` (raw NWS HTTP+
GeoJSON wrapper).

## What this package is

The adapter defines:

- `NwsAdvisoryProvider` — implementation of
  `AdvisoryProvider` for use inside an `AdvisoryAggregator`. Two
  constructors: default (owns its own `NoaaNwsClient`) and
  `withClient` (test-injection).
- `mapWinterAlertToAdvisory(WinterAlert) → Advisory` — direct field
  mapping, exposed at top level for test invocation without HTTP.

## What this package is not

- Not a re-implementation of NWS HTTP / GeoJSON parsing. Those live in
  `noaa_nws_adapter`. This package adds typed-event normalization on
  top.
- Not a multi-region adapter. NWS data is U.S.-region; Japanese-region
  drivers consume the JMA-class adapter (separate package) inside the
  same aggregator.
- Not a renderer. The package returns typed `Advisory` value objects;
  the integrator HMI surfaces them.

## HER-trace (≤4-hop)

```
NWS api.weather.gov /alerts/active
  → noaa_nws_adapter NoaaNwsClient (HTTP + GeoJSON parse)
  → condition_aggregator_nws NwsAdvisoryProvider (typed mapping)
  → AdvisoryAggregator + integrator HMI surfaces the alert to the
    driver in unexpected snow
```

4 hops.

## Driver-facing loom

When NWS has issued a winter alert for the driver's current point
inside the U.S., the integrator HMI surfaces a typed `Advisory` event
with severity / certainty / urgency / area / effective / expires
normalized — as the driver's decision substrate, not as raw GeoJSON
properties. The publisher's vocabulary is preserved verbatim:
`Advisory.eventClass` carries `Winter Storm Warning`, `Blizzard
Warning`, `Ice Storm Warning`, etc. — the words NWS published.
`areaDescription`, `headline`, and `description` are passed through
without app-class re-summarization. The driver always drives.

## Mapping detail

| `Advisory` field | source `WinterAlert` field |
|------------------|----------------------------|
| `source`         | constant `AdvisorySource.nwsUnitedStates` |
| `eventClass`     | `event` (verbatim publisher event-class) |
| `severity`       | `severity` (CAP-class enum, direct mapping) |
| `certainty`      | `certainty` (CAP-class enum, direct mapping) |
| `urgency`        | `urgency` (CAP-class enum, direct mapping) |
| `areaDescription`| `areaDesc` (verbatim) |
| `effective`      | `effective` (nullable, direct) |
| `expires`        | `expires` (nullable, direct) |
| `headline`       | `headline` (verbatim) |
| `description`    | `description` (verbatim) |

`WinterAlert` carries additional fields (`instruction`, `status`,
`messageType`, `senderName`) that are not surfaced at the source-neutral
`Advisory` boundary today; they are available to integrators that
depend directly on `noaa_nws_adapter` if needed.

## Usage

```dart
import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_nws/condition_aggregator_nws.dart';

final agg = AdvisoryAggregator(providers: <AdvisoryProvider>[
  NwsAdvisoryProvider(
    userAgent: '(myapp.example, contact@myapp.example)',
  ),
]);

await agg.init();

final result = await agg.fetchActiveAdvisoriesAtPoint(
  latitude: 47.9253,
  longitude: -97.0329,
);

for (final a in result.advisories) {
  print('[${a.source.name}] ${a.eventClass}: ${a.headline}');
}
```

## Behaviours worth knowing

- **`init()` is a no-op for this adapter.** NWS publishes open
  public-domain data; no schema-version negotiation, no auth
  handshake. Configuration (User-Agent) is fully constructor-injected.
  Calling `init()` more than once is fine.
- **Pass-through for transport / parse exceptions.** Underlying
  `noaa_nws_adapter` raises `NoaaNwsHttpException` (transport) and
  `NoaaNwsParseException` (GeoJSON shape mismatch). At fan-out time
  inside `AdvisoryAggregator`, these are captured into
  `result.providerErrors` so the integrator surfaces staleness
  honestly.
- **`actualOnly` filter is delegated to the underlying client.**
  `NoaaNwsClient` defaults to `actualOnly: true` (Test / Exercise /
  System / Draft entries excluded). Production driver-facing flows
  inherit that default through this adapter.
- **`close()` releases HTTP resources.** Call `provider.close()` when
  finished; no-op when `withClient(...)` was used (caller owns the
  client).

## Dependency posture

- Pure Dart. No Flutter dependency.
- Runtime: `condition_aggregator` (path), `noaa_nws_adapter` (path).
- Dev: `test`, `lints`.
- Strict-cast / strict-inference / strict-raw-types analyser settings.

## License

BSD-3-Clause. See [LICENSE](LICENSE) (matches the rest of SNGNav).
