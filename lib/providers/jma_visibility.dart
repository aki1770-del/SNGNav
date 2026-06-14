/// Re-export shim: the JMA AMeDAS measured-visibility SOURCE now lives in the
/// pure-Dart package `pretrip_source_jma` (extracted 2026-06-14).
///
/// App importers of
/// `package:sngnav_snow_scene/providers/jma_visibility.dart` keep resolving
/// `JmaVisibilityProvider`, `JmaVisibilityException`, `kJmaBosaiApiBase`, and —
/// re-exported by the package barrel — `VisibilityObservation` /
/// `mergeObservedVisibility` (owned by `pretrip_decision_advisor`) unchanged.
/// The honesty rules (visibility NEVER estimated; a warning NEVER produces a
/// number; an observation valid for the departure hour only; null = the
/// driver's own judgment) live verbatim in the package source + SAFETY README.
library;

export 'package:pretrip_source_jma/pretrip_source_jma.dart';
