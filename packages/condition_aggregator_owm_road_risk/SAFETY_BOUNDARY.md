# SAFETY_BOUNDARY — condition_aggregator_owm_road_risk

## What this package does

`condition_aggregator_owm_road_risk` adapts OpenWeatherMap's Road Risk
endpoint into the source-neutral `Advisory` typed event consumed by
the `condition_aggregator` umbrella. Output is advisory information
the driver may consider; the package does not actuate the vehicle and
does not close a control loop.

## What this package does NOT do

- **Does not author or relay any control input** to the vehicle —
  steering, braking, accelerator, transmission, or any other actuator.
- **Does not take over the dynamic driving task.** Per SAE J3016, this
  package operates at L0 / L1 supportive scope only. The driver
  performs all dynamic driving subtasks at all times.
- **Does not assert a functional-safety case.** No ISO 26262 ASIL
  classification is claimed at the package boundary. The integrator
  performs the hazard analysis and decides the certification path
  for their integration.
- **Does not vouch for publisher accuracy.** The OpenWeatherMap Road
  Risk feed is the publisher's signal; this package preserves the
  publisher's wording verbatim per Article 17 (β) discipline. Whether
  the publisher's signal is accurate, timely, or complete for a given
  point is the publisher's question, not this adapter's.
- **Does not bundle a publisher API key.** Operators register at
  openweathermap.org and supply their own `appid` at provider
  construction time. The OpenWeatherMap terms of service govern key
  usage and data redistribution.
- **Does not cache or persist alerts** beyond the duration of a
  single `fetchActiveAdvisoriesAtPoint` call. The integrator decides
  cache and offline-fallback policy.

## Caution-add-only invariant

When the publisher's `event_level` integer is at a bucket boundary,
`OwmRoadRiskMapper` rounds to the lower (more conservative) of the
two adjacent CAP severity buckets so the consumer warns earlier, not
later. This invariant is asserted by tests and applies to every
mapping path between publisher payload and source-neutral
`Advisory`.

## Compound-failure surface

The OpenWeatherMap Road Risk endpoint is internet-only and commercial.
In a compound-failure scenario where internet connectivity is lost,
this provider throws `OwmRoadRiskHttpException`. Sibling adapters
operating against different publishers (e.g., `condition_aggregator_jma`
in Japan, `condition_aggregator_nws` in the United States) remain
available if their feeds are reachable. The integrator's app decides
the cache, fallback, and degradation policy.

## Driver retains authority

Every output of this package is advisory. The driver retains full
authority over braking, steering, lane choice, and routing. The
adapter does not encode any handover, take-over-request, or
minimum-risk-manoeuvre fallback because none of those are within
its scope.

## Version compatibility note

`AdvisorySource.other` is reported in 0.1.0 because the umbrella
`condition_aggregator` 0.0.3 does not yet name OpenWeatherMap as a
dedicated `AdvisorySource` value. A forward-additive enum bump in
`condition_aggregator` 0.0.4+ will introduce a dedicated value;
consumers consuming via the `AdvisoryAggregator` interface do not
need to change. The `AdvisorySource.attributionString` getter on the
umbrella enum can be extended at the same minor bump to surface the
publisher attribution string the consumer surface should display.
