/// condition_aggregator_jma — JMA (Japan Meteorological Agency) adapter
/// for the condition_aggregator interface.
///
/// **Status: explore-phase scaffold (`publish_to: none`).** Deploy
/// graduation blocks on a separate engagement-shape election for the
/// upstream parser substrate (jmaxml). The public API here is a STUB
/// implementation: [JmaAdvisoryProvider.fetchActiveAdvisoriesAtPoint]
/// returns an empty list at all points until the upstream parser
/// integration lands. The shape is locked so consuming packages
/// can wire against the interface today and the underlying mapping
/// graduates without API churn.
///
/// HER-trace (≤4-hop) end-to-end (deploy-state target):
///   JMA disaster-info XML feed (気象庁防災情報XML)
///     → `JmaAdvisoryProvider` (this adapter) maps to `Advisory`
///     → `AdvisoryAggregator` typed merge with sibling adapters
///     → integrator HMI surfaces the advisory to the driver in
///       unexpected snow on a Japanese road.
/// 4 hops.
///
/// Driver-facing loom: when JMA has issued a 大雪 / 暴風雪 / 雪 advisory
/// for the driver's current point in Japan, the integrator HMI surfaces
/// a typed `Advisory` event with severity / certainty / urgency / area /
/// effective / expires normalized at the boundary, with JMA's exact
/// wording preserved verbatim per Article 17 (β) verbatim-relay
/// discipline. The driver always drives.
///
/// Composition target (deploy-state):
///   JMA disaster-info XML feed
///     → upstream parser (currently no Dart binding; engagement-shape
///       election pending — WASM bridge OR Dart binding port both on
///       the table per UPA T3 substrate prep)
///     → `condition_aggregator_jma` (this package; maps parsed feed to
///       `Advisory`)
///     → `condition_aggregator` (`AdvisoryAggregator` merges across
///       publishers including NWS)
///     → integrator HMI / driver
library;

export 'src/jma_advisory_provider.dart' show JmaAdvisoryProvider;
export 'src/jma_advisory_mapper.dart' show mapJmaForecastToAdvisory;
