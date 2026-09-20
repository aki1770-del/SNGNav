/// condition_aggregator — source-neutral interface for multi-source
/// meteorological-advisory aggregation.
///
/// The interface package defines the [Advisory] typed event,
/// [AdvisoryProvider] adapter contract, [AdvisoryAggregator] multi-source
/// fan-out primitive, and supporting error types. Per-source adapter
/// packages (e.g. `condition_aggregator_nws`, `condition_aggregator_jma`)
/// implement [AdvisoryProvider] and depend on this package.
///
/// Published to pub.dev. It became a published package once the interface
/// tests and the first adapter wired against it were green, which is this
/// project's bar for promoting a spike to a package.
///
/// From publisher to driver, end to end (4 hops):
///   publisher advisory feed (NWS / JMA / etc.)
///     → per-source adapter (`condition_aggregator_<source>`)
///     → `AdvisoryAggregator` typed merge
///     → integrator HMI surfaces advisory to the driver in unexpected snow
/// 4 hops.
///
/// What the driver experiences: when a publisher (NWS, JMA, etc.) has issued an
/// advisory for the driver's current point, the integrator HMI surfaces
/// a typed `Advisory` event with severity / certainty / urgency / area /
/// effective / expires normalized across sources — as the driver's
/// decision substrate, not as raw GeoJSON or XML feed text. The driver
/// always drives.
///
/// Composition with sibling packages:
///   `noaa_nws_adapter` (raw NWS HTTP+GeoJSON adapter)
///     → `condition_aggregator_nws` (maps WinterAlert → Advisory)
///     → `condition_aggregator` (this package; AdvisoryAggregator merges)
///     → `driving_conditions` / `driving_weather` integrators
///     → SNGNav app HMI / driver
library;

export 'src/advisory.dart'
    show
        Advisory,
        AdvisorySource,
        AdvisorySourceAttribution,
        AdvisorySeverity,
        AdvisoryCertainty,
        AdvisoryUrgency,
        AdvisoryDeserializationException;
export 'src/advisory_provider.dart'
    show AdvisoryProvider, AdvisoryProviderInitException;
export 'src/advisory_absence.dart' show AdvisoryUnavailableReason;
export 'src/advisory_feed_freshness.dart'
    show AdvisoryFeedStaleness, AdvisoryFeedFreshnessReporting;
export 'src/advisory_lookup.dart'
    show
        AdvisoryLookup,
        AdvisoryLookupComplete,
        AdvisoryLookupPartial,
        AdvisoryLookupUnavailable,
        AdvisorySourceFailure;
export 'src/advisory_aggregator.dart'
    show
        AdvisoryAggregator,
        AdvisoryAggregateResult,
        AdvisoryProviderError,
        AdvisoryLookupIncompleteException;
