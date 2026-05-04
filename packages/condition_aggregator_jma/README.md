# condition_aggregator_jma

Japan Meteorological Agency (気象庁 / JMA) adapter for the
`condition_aggregator` interface. Maps JMA disaster-info XML feeds
to the source-neutral `Advisory` typed event shape so integrators
consume one shape across publishers (NWS / JMA / etc.) without
caring which publisher authored which advisory.

## Status

**Explore-phase scaffold.** `publish_to: none` is set in
`pubspec.yaml`. The package compiles, tests pass, and the
`AdvisoryProvider` interface is satisfied — but the
`fetchActiveAdvisoriesAtPoint` method is a stub returning an empty
list at every point until the upstream parser integration lands.

Deploy-graduation BLOCKS on a separate engagement-shape election
(alpha / beta / gamma) for the upstream parser substrate. The
election produces one of: WASM bridge to the existing Rust
parser crate, OR a Dart-native codegen port of the parser
pipeline. Both shapes were canvassed in the substrate prep; the
election picks one.

This package is shipped at scaffold-state today so consuming
packages (driving_weather, integrators) can wire against the
interface, write integration tests against the stub, and flip to
real-data on graduation without any API churn.

## What this package does (at deploy-state)

When JMA has issued a 大雪 / 暴風雪 / 雪 advisory for the driver's
current point in Japan:

1. The provider fetches the regional JMA disaster-info XML feed.
2. The upstream parser binding (engagement-shape elected — WASM
   bridge OR Dart-native codegen port) parses the XML to typed
   report records.
3. Snow / blizzard / heavy-snow report families
   (`VPWW54` / `VPCJ51` / `VPAW51` / `VPFD60` / `VPBS50` / etc.)
   are filtered through.
4. Each record is mapped to a source-neutral `Advisory` via
   `mapJmaForecastToAdvisory`.
5. The `AdvisoryAggregator` merges the JMA records with sibling
   adapters' records (e.g. `condition_aggregator_nws` records
   when the driver crosses an international boundary or relies
   on multi-source corroboration).
6. The integrator HMI surfaces the typed `Advisory` event with
   severity / certainty / urgency / area / effective / expires
   normalized at the boundary, with JMA's exact wording preserved
   verbatim per the verbatim-relay discipline.

## Driver-facing loom

When JMA has issued a snow / heavy-snow / blizzard advisory for the
driver's current point on a Japanese road, the integrator HMI
surfaces a typed `Advisory` event normalized into the same shape as
NWS records. The driver sees JMA's authoritative wording verbatim
(report family code, headline, area description, multi-paragraph
description) without aggregator-class re-summarization. The driver
always drives.

## HER-trace (≤4 hops; deploy-state target)

```
JMA disaster-info XML feed (気象庁防災情報XML)
  → JmaAdvisoryProvider (this package; maps to Advisory)
  → AdvisoryAggregator (typed merge with sibling adapters)
  → integrator HMI surfaces advisory to driver in unexpected snow.
```

4 hops. D3 anchor: helps the driver in unexpected snow on a
Japanese road. D5 value chain: evidence → contribution →
architecture → edge developer → driver.

## Composition

```
JMA disaster-info XML feed
  ↓
[upstream parser; engagement-shape election pending]
  ↓
condition_aggregator_jma (this package)
  ↓
condition_aggregator (AdvisoryAggregator merges across publishers)
  ↓
driving_weather / driving_conditions / integrator HMI
  ↓
Driver in unexpected snow.
```

## What this package does NOT do

- **No retry inside this adapter**: transient failure handling
  belongs to the underlying parser/HTTP layer at deploy-time;
  the aggregator's `warn-and-continue` posture captures the error
  through the standard `AdvisoryAggregateResult.providerErrors`
  surface.
- **No cache, no stream, no polling at this layer**: stateless
  beyond construction-time configuration; consumer owns refresh
  cadence.
- **No app-class re-summarization**: JMA's `headline`,
  `description`, `areaDescription` pass through verbatim.
- **No profile-driven branching**: profile-aware UX rendering
  composes downstream against `navigation_safety_core` thresholds;
  this layer preserves the severity-not-profile invariant.
- **No road-surface inference**: JMA's domain is meteorological
  advisory; road-surface measurement lives in JARTIC / NEXCO /
  prefectural feeds. This adapter renders the meteorological-
  advisory leg only; sibling road-surface adapters are out of
  scope.

## Getting started

This package is explore-phase; the API surface is locked but the
behavior is a stub. Once it graduates, integrators wire it into an
`AdvisoryAggregator`:

```dart
final jma = JmaAdvisoryProvider();
final nws = NwsAdvisoryProvider(userAgent: '...');
final aggregator = AdvisoryAggregator(<AdvisoryProvider>[jma, nws]);
await aggregator.init();
final result = await aggregator.fetchAtPoint(
  latitude: 39.7186,
  longitude: 140.1024,
);
// result.advisories is the typed merged stream from both publishers.
```

Today (`0.0.1` scaffold), the JMA leg of that stream is empty at
every point.

## Substrate prep + license / engagement context

The upstream parser repository (jmaxml) is permissively dual-licensed
(MIT OR Apache-2.0; verified on the source-of-truth root manifest).
Engagement-receptiveness baseline: lifetime issues = 0 on the
upstream repo at substrate-prep time, so any engagement is
high-care first-engagement-class. Maintainer surface: senior
domain-professional in the Japanese geospatial space.

The substrate prep is recorded in the unit's research outputs;
this package does not duplicate that material here. Graduation
will surface a one-line citation in this README to the
substrate-prep document at the same time as the engagement-shape
election ratifies.

## License

BSD-3-Clause. See `LICENSE`.
