/// pretrip_source_digitraffic — Fintraffic Digitraffic measured-visibility
/// source for the `pretrip_decision_advisor` briefing.
///
/// This package emits a MEASUREMENT: the nearest fresh measured road-network
/// visibility (`NÄKYVYYS_M`, metres) on the Finnish road network, as a
/// source-neutral [VisibilityObservation]. It is the measurement half of the
/// Digitraffic family; its sibling `condition_aggregator_digitraffic` emits a
/// WARNING (an `Advisory` from traffic announcements). See README.md for which
/// to depend on for which need.
///
/// Service trace (driver in unexpected snow; ≤4-hop) end-to-end:
///   Fintraffic Digitraffic road-weather network (real NÄKYVYYS_M sensors)
///     → `DigitrafficVisibilityProvider` (this package)
///     → `mergeObservedVisibility` onto the departure-hour forecast slot
///       (`pretrip_decision_advisor`)
///     → an edge developer's pre-trip briefing UI/XI warns HER (Nagoya) and
///       HER mother (Akita) before she drives into the whiteout.
///
/// Honesty rules survive VERBATIM from the contract (binding — README.md):
/// - visibility NEVER estimated
/// - a warning NEVER produces a number
/// - an observation valid for the departure hour only
/// - null = the driver's own judgment, never a fabricated hazard
library;

export 'src/digitraffic_visibility_provider.dart'
    show
        DigitrafficVisibilityException,
        DigitrafficVisibilityProvider,
        kDigitrafficVisibilityAttributionString,
        kDigitrafficWeatherApiBase;

// The measured-visibility observation type and its departure-hour merge are
// owned by the published pure-Dart `pretrip_decision_advisor` package and are
// source-neutral (shared with the JMA AMeDAS source). Re-exported so a
// consumer of this barrel resolves the MEASUREMENT this package produces
// (`VisibilityObservation`) and the merge it is designed to feed
// (`mergeObservedVisibility`) without a second import.
export 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart'
    show VisibilityObservation, mergeObservedVisibility;
