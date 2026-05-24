/// condition_aggregator_digitraffic — Fintraffic Digitraffic adapter for
/// the `condition_aggregator` interface.
///
/// Wraps the open Digitraffic traffic-announcements endpoint
/// (`https://tie.digitraffic.fi/api/traffic-message/v2/traffic-announcements`;
/// no authentication required per Digitraffic swagger `security: []`)
/// and maps each GeoJSON feature to a source-neutral `Advisory` typed
/// event at the adapter boundary.
///
/// Phase: explore — v0.0.1.
///
/// HER-trace (≤4-hop) end-to-end:
///   Fintraffic Digitraffic traffic-announcements feed
///     → `DigitrafficAdvisoryProvider` (this package)
///     → `AdvisoryAggregator` typed merge
///     → integrator HMI surfaces advisory to the driver in unexpected
///       snow on Finnish roads.
/// 4 hops.
///
/// Source attribution: `AdvisorySource.other` (placeholder). The
/// `condition_aggregator` interface enum does not yet carry a Finland
/// member; v0.0.1 uses `other` per the enum's own
/// "early-scaffold-without-locking-surface" documented use. A future
/// interface release adding `AdvisorySource.fintrafficFinland` is a
/// known carry-forward; this adapter rebases when that lands.
library;

export 'src/digitraffic_advisory_provider.dart'
    show
        DigitrafficAdvisoryProvider,
        DigitrafficHttpException,
        DigitrafficParseException,
        mapTrafficAnnouncementFeatureToAdvisory;
