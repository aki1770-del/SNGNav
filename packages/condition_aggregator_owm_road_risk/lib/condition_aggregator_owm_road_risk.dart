/// condition_aggregator_owm_road_risk — OpenWeatherMap Road Risk
/// adapter for the condition_aggregator interface.
///
/// **Status: 0.1.0 ships the adapter pattern + lower-level HTTP
/// client.** The user supplies their own publisher API key
/// (`appid`); this package does not bundle one. Tests run against
/// `MockClient` golden fixtures so the package is exercised on CI
/// without burning publisher quota.
///
/// HER-trace (≤4-hop) end-to-end:
///   OWM Road Risk endpoint (api.openweathermap.org/data/2.5/roadrisk)
///     → `OwmRoadRiskProvider` (this adapter; HTTP + JSON parse + map)
///     → `AdvisoryAggregator` typed merge with sibling adapters
///       (e.g. `condition_aggregator_jma`, `condition_aggregator_nws`)
///     → integrator HMI surfaces the advisory to the driver in
///       unexpected snow on a US/EU road.
/// 4 hops.
///
/// Composition with sibling packages:
///   `condition_aggregator_jma`   — JMA (Japan)
///   `condition_aggregator_nws`   — NOAA NWS (United States)
///   `condition_aggregator_owm_road_risk` — OWM (US / EU; commercial)
///
/// The aggregator umbrella `condition_aggregator` has no dedicated
/// OpenWeatherMap `AdvisorySource` enum value, so this adapter reports
/// `AdvisorySource.other`. Consumers consuming via the
/// `AdvisoryAggregator` type handle it like any other advisory.
///
/// When the publisher is silent, this adapter keeps the reasons apart. An
/// empty result means the publisher answered and reported nothing; a read it
/// could not complete throws rather than returning an empty list; a partially
/// unreadable answer comes back with an in-band incomplete-read notice; and a
/// field the publisher did not state maps to `AdvisorySeverity.unknown` rather
/// than to the bottom of the severity scale. The one silence this adapter
/// cannot represent is a declared coverage gap — the publisher's response shape
/// has no way to say "not covered here" — and the README states that bound
/// rather than simulating the signal.
///
/// Surface published in this package:
/// - [OwmRoadRiskClient] — lower-level HTTP client around the
///   publisher's `/data/2.5/roadrisk` endpoint; returns raw alerts.
/// - [OwmRoadRiskProvider] — `AdvisoryProvider` implementation;
///   one-shot point query mapped to source-neutral [Advisory]s.
/// - [OwmRoadRiskWaypoint] — request waypoint type.
/// - [OwmRoadRiskAlert] — response alert type.
/// - [OwmRoadRiskRead] — one read's alerts together with what could not be
///   read, so a partial read is never mistaken for an empty one.
/// - [OwmRoadRiskMapper] — alert → Advisory mapping primitives.
/// - [kOwmRoadRiskIncompleteReadEventClass] — `Advisory.eventClass` identity
///   of the incomplete-read notice, for consumers that filter or render it
///   differently from a hazard.
/// - [OwmRoadRiskHttpException] / [OwmRoadRiskParseException] —
///   error types for caller-side discrimination.
library;

export 'src/owm_road_risk_mapper.dart';
export 'src/owm_road_risk_models.dart';
export 'src/owm_road_risk_provider.dart';
