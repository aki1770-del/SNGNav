# noaa_nws_adapter

Pure-Dart client that fetches active U.S. winter-weather alerts (Winter
Storm / Blizzard / Ice Storm, etc.) for a lat/lon from the free NOAA / NWS
public API. No API key, no account.

```sh
dart pub add noaa_nws_adapter
```

(pulls peer deps `http` + `equatable` automatically — no manual peer install.)

## Quick start

```dart
import 'package:noaa_nws_adapter/noaa_nws_adapter.dart';

void main() async {
  final client = NoaaNwsClient(userAgent: '(myapp.example.com, you@example.com)');
  try {
    // Active winter alerts near these coordinates (Grand Forks, ND).
    final alerts = await client.fetchActiveWinterAlerts(
      latitude: 47.9253,
      longitude: -97.0329,
    );
    print('Active winter alerts: ${alerts.length}');
    for (final a in alerts) {
      print('• ${a.event} [${a.severity.name}] — ${a.headline}');
    }
  } on NoaaNwsHttpException catch (e) {
    print('NWS unreachable: $e'); // honest failure; never a fake "all clear"
  } finally {
    client.close();
  }
}
```

You get back a `List<WinterAlert>` — typed, severity-qualified winter alerts
for that point (empty when none are active), parsed from NWS GeoJSON for you.

Note: NWS requires a `User-Agent` of the form `(yourapp.com, contact@email.com)`;
the client raises `ArgumentError` up-front if omitted, so substitute your own contact.

---

## Background & provenance

Smallest-slice direct-consume wrapper around the
[NOAA / National Weather Service public API](https://www.weather.gov/documentation/services-web-api)
(`https://api.weather.gov`).

## Why this package exists

A driver entering an unexpected snow or ice region inside the United
States needs winter-hazard signal that is timely, authoritative, and
free of vendor lock-in. The NWS publishes exactly that signal as
public-domain GeoJSON. This package consumes one endpoint of that API
and returns Dart objects an app can show to the driver.

### Driver impact chain (≤4 hops)

```
NWS API (api.weather.gov)
  -> NoaaNwsClient (this package)
    -> SNGNav weather/condition consumer (forward)
      -> driver in unexpected snow region (US)
```

Four hops, with the driver as the terminal beneficiary. Each hop is a
single Dart call or stream; no analytics layer, no profiling layer, no
intermediate cloud service.

### What the driver experiences when this package fires

Every SNGNav package states, at its surface, what the driver actually
experiences when the package does its job. For this package:

When `api.weather.gov` returns an active winter alert near her
coordinates — Winter Storm Warning, Ice Storm Warning, Blizzard
Warning, or one of the other 11 catalogued winter event types — and
that alert carries CAP severity `Moderate` or higher, certainty
`Likely` or higher, and urgency `Expected` or higher, this package
emits a typed `WinterAlert` into the consuming SNGNav layer. The
driver, in her decision moment a few minutes before the snow band
crosses her route, sees a severity-qualified alert in her own
language at the surface of her navigation app — without ever parsing
CAP XML herself, without an account, without an analytics ping
identifying her, and without a vendor between her and the U.S.
National Weather Service. If the API is unreachable the consumer is
told so honestly; the package does not fabricate a "no alert" state
out of a transport failure.

The thread the package watches: a winter event the driver did not
expect. The action when the thread breaks: surface it before she
enters it.

## Smallest slice

ONE endpoint:

```
GET https://api.weather.gov/alerts/active?point={lat},{lon}
Accept: application/geo+json
User-Agent: (myappname.com, contact@email.com)
```

ONE alert class focus: the 14 catalogued
[winter event types](https://api.weather.gov/alerts/types) — Winter
Storm Warning / Watch, Winter Weather Advisory, Blizzard Warning, Ice
Storm Warning, Heavy Freezing Spray Warning / Watch, Lake Effect Snow
Warning, Freeze Warning / Watch, Freezing Fog Advisory, Cold Weather
Advisory, Extreme Cold Warning / Watch.

Other endpoints (`/points`, `/gridpoints/.../forecast`, `/stations`,
`/zones`, etc.) and other event classes (severe weather, flood, fire,
marine) are intentionally out of scope for this slice.

## API

| Type | Purpose |
|------|---------|
| `NoaaNwsClient` | Stateless HTTP wrapper around `/alerts/active?point=`. |
| `WinterAlert` | Equatable model carrying CAP-class fields relevant to a winter-driving consumer. |
| `kNwsWinterEventTypes` | The 14-string catalogue used to filter the response. |
| `AlertSeverity` / `AlertCertainty` / `AlertUrgency` | CAP enums with an `unknown` default. |
| `AlertStatus` / `AlertMessageType` | CAP enums; `actualOnly: true` (default) keeps only `Actual`. |
| `NoaaNwsHttpException` | Non-2xx or transport failure. |
| `NoaaNwsParseException` | GeoJSON shape mismatch. |

### Behaviours worth knowing

- **No retry inside the client.** On 429 the call throws; the caller
  decides whether and how to back off. Keeping retry policy in the
  caller keeps logs honest about what was actually attempted.
- **Stateless: no polling, no cache, no stream.** A consumer that
  wants periodic refresh wraps this in their own `Timer.periodic` /
  `Stream.periodic`. This composes cleanly with the eventual
  multi-feed aggregator interface.
- **User-Agent is mandatory.** Empty value throws `ArgumentError` at
  construction. The publisher uses User-Agent for rate-limit
  accounting and security contact; an anonymous request is a
  programmer error.
- **Default filter: winter event types AND `Actual` status.** Pass
  `actualOnly: false` to keep `Test` / `Exercise` / `System` /
  `Draft` entries (rarely needed outside debug builds).
- **Malformed features are skipped, not fatal.** One bad feature in a
  batch (e.g. a CAP `Cancel` with no `event`) does not abort the
  whole response.

## Authentication, rate limiting, license

- **Auth:** none. A `User-Agent` header in the form
  `(yourapp.example, contact@yourapp.example)` is required by the
  publisher; no API key, no registration.
- **Rate limit:** not publicly documented. The publisher describes a
  "generous amount for typical use" and a 5-second retry-after on
  429. Expect proxy-class IPs to hit limits sooner than direct
  client-class IPs.
- **License:** the API documentation states the data is "open data,
  free to use for any purpose." Attribution is not required by the
  publisher. Consumers may still wish to cite the source for end-user
  trust ("Source: U.S. National Weather Service").

## Tests

```bash
dart pub get
dart analyze
dart test
```

There are no live-network tests; the HTTP path is covered with
`package:http`'s `MockClient` so the suite runs in any environment.

## What this package deliberately does not do

- It does NOT provide forecasts (`/gridpoints/.../forecast`,
  `/forecast/hourly`).
- It does NOT provide observations (`/stations`,
  `/stations/{id}/observations/latest`).
- It does NOT provide aviation products (CWA / SIGMET / AIRMET / TAF).
- It does NOT provide road-surface state (NWS does not publish that;
  it lives at FHWA and state-DOT level).
- It does NOT auto-poll, auto-retry, or cache.
- It does NOT translate or summarise alerts; consumers compose their
  own UX layer.
- It is NOT a Flutter package and does NOT depend on Flutter.

These boundaries keep the slice small enough to verify by reading the
code in one sitting.

## Coverage

US contiguous + Alaska + Hawaii + Puerto Rico + territories, at the
publisher's ~2.5 km grid for forecasts and CAP-zone or per-county
granularity for alerts. Outside that footprint the endpoint returns an
empty `FeatureCollection`.

For Japan, see jmaxml-class adapters (separate package). For New
Zealand, see MetService adapters (separate package). For VSS-aligned
vehicle-signal vocabulary (e.g. `Vehicle.Exterior.RoadSurfaceCondition`),
see `navigation_safety_core`.

## License

Source code: BSD-3-Clause (matches the rest of SNGNav).
NWS data consumed at runtime: U.S. Federal public-domain.
