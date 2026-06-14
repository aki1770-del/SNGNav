/// Re-export shim: the Digitraffic measured-visibility SOURCE now lives in the
/// pure-Dart package `pretrip_source_digitraffic` (extracted 2026-06-14).
///
/// App importers of
/// `package:sngnav_snow_scene/providers/digitraffic_visibility.dart` keep
/// resolving `DigitrafficVisibilityProvider`, `DigitrafficVisibilityException`,
/// and `kDigitrafficWeatherApiBase` unchanged. The package barrel also
/// re-exports the source-neutral `VisibilityObservation` and
/// `mergeObservedVisibility` (owned by `pretrip_decision_advisor`), so the
/// original re-export of those symbols from this file is preserved. The
/// honesty rules survive verbatim in the package source + SAFETY README.
library;

export 'package:pretrip_source_digitraffic/pretrip_source_digitraffic.dart';
