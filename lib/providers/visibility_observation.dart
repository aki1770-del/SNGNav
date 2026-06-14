/// Re-export shim: the source-neutral measured-visibility observation and its
/// departure-hour merge now live in the published pure-Dart package
/// `pretrip_decision_advisor` (0.2.0+).
///
/// `digitraffic_visibility.dart` and `jma_visibility.dart` `import` and
/// re-`export` this file; they keep resolving `VisibilityObservation` and
/// `mergeObservedVisibility` unchanged via this re-export.
library;

export 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart'
    show VisibilityObservation, mergeObservedVisibility;
