/// pretrip_source_jma — Japan Meteorological Agency (AMeDAS) measured-visibility
/// source for the `pretrip_decision_advisor` pre-trip "Before you drive"
/// briefing.
///
/// Emits a MEASUREMENT (`VisibilityObservation`) — a real surface-visibility
/// reading in metres from the JMA AMeDAS network — that the advisor merges into
/// the departure hour via `mergeObservedVisibility`. This is the
/// measurement-emitting sibling of `condition_aggregator_jma`, which emits a
/// WARNING (`Advisory`) from the JMA winter-warning feed. Same upstream
/// provider (気象庁 / Japan Meteorological Agency); two different products —
/// pub-add this one for a measured number, the sibling for a warning event.
///
/// Service trace (driver in unexpected snow; ≤4 hops):
///   JMA AMeDAS visibility sensor (e.g. 秋田/Akita 32402)
///     → `JmaVisibilityProvider` (this package)
///     → `mergeObservedVisibility` into the departure-hour forecast slot
///     → `pretrip_decision_advisor` briefing an edge developer renders so a
///       driver in unexpected snow — in Japan, including HER mother in Akita —
///       can decide before she sets out.
///
/// Pure Dart. Only `http` and `pretrip_decision_advisor` runtime dependencies.
///
/// Honesty rules are binding (see `JmaVisibilityProvider` dartdoc + the
/// SAFETY-class README): visibility is NEVER estimated; a warning NEVER
/// produces a number; an observation is valid for the departure hour ONLY;
/// `null` returns the decision to the driver's own judgement — never a
/// fabricated hazard.
library;

export 'src/jma_visibility.dart'
    show
        JmaVisibilityProvider,
        JmaVisibilityException,
        VisibilityObservation,
        mergeObservedVisibility,
        kJmaBosaiApiBase;
