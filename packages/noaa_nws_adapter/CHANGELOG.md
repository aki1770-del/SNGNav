# Changelog

## 0.0.1 — 2026-05-03

Initial publish.

- `NoaaNwsClient` stateless HTTP wrapper for
  `https://api.weather.gov/alerts/active?point={lat},{lon}` (User-Agent
  required; mandatory at construction).
- `WinterAlert` Equatable model carrying CAP-class fields (`event`,
  `severity`, `certainty`, `urgency`, `status`, `messageType`,
  `headline`, `areaDesc`, `effective`, `expires`, `description`,
  `instruction`).
- CAP enums with safe `unknown` default: `AlertSeverity`,
  `AlertCertainty`, `AlertUrgency`, `AlertStatus`, `AlertMessageType`.
- `kNwsWinterEventTypes` 14-string catalogue (Winter Storm Warning /
  Watch, Winter Weather Advisory, Blizzard Warning, Ice Storm Warning,
  Heavy Freezing Spray Warning / Watch, Lake Effect Snow Warning,
  Freeze Warning / Watch, Freezing Fog Advisory, Cold Weather
  Advisory, Extreme Cold Warning / Watch).
- `NoaaNwsHttpException`, `NoaaNwsParseException` typed error surfaces.
- Default filter `actualOnly: true` excludes `Test` / `Exercise` /
  `System` / `Draft` entries from production driver-facing flow.
- Malformed CAP features skipped (warn-and-continue) rather than
  aborting the whole response.
- 25 tests covering value-object, CAP-enum mapping, parse-layer error
  surfaces, MockClient round-trip, header propagation, transport
  failure surfaces.
- BSD-3-Clause license (matches the rest of SNGNav).
- Pure Dart, no Flutter dependency.
