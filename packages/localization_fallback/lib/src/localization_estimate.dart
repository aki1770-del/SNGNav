/// The single honest position estimate this package emits.
library;

import 'estimate_basis.dart';
import 'localization_mode.dart';

/// The one localization estimate the controller hands the app for a given
/// moment. There is exactly one of these per input — never a confident dot and
/// a hidden caveat, just one position carrying its own honesty.
class LocalizationEstimate {
  /// Best-estimate latitude in decimal degrees (WGS-84).
  ///
  /// May be `double.nan` when [mode] is `lost` and [basis] is
  /// `unanchoredGuess` — i.e. nothing has ever been trusted and there is no
  /// coordinate to guess from. ALWAYS check [hasPosition] (or [mode]) before
  /// plotting, or a `NaN` dot will be drawn.
  final double latitude;

  /// Best-estimate longitude in decimal degrees (WGS-84).
  ///
  /// May be `double.nan`; see [latitude] and [hasPosition].
  final double longitude;

  /// The radius, in metres, within which the true position is believed to lie.
  ///
  /// While GPS is not trusted this only ever GROWS — you cannot become more
  /// certain without a fresh trusted fix. Read it as: "the dot could be
  /// anywhere within this circle."
  final double confidenceRadiusMeters;

  /// How much to believe the position. See [LocalizationMode].
  final LocalizationMode mode;

  /// Seconds elapsed since the last trusted fix. `0.0` while [mode] is
  /// `gpsTrusted`; grows while degraded. `double.infinity` if a trusted fix has
  /// never been seen.
  final double secondsSinceTrustedFix;

  /// Which input actually produced [latitude]/[longitude]. See [EstimateBasis].
  final EstimateBasis basis;

  const LocalizationEstimate({
    required this.latitude,
    required this.longitude,
    required this.confidenceRadiusMeters,
    required this.mode,
    required this.secondsSinceTrustedFix,
    required this.basis,
  });

  /// Whether this estimate may be presented as a confident position.
  ///
  /// True only in `gpsTrusted`. In every other mode the app must signal
  /// uncertainty to the driver (grow the dot, show the mode, etc.).
  bool get isConfident => mode == LocalizationMode.gpsTrusted;

  /// Whether [latitude]/[longitude] are real, plottable coordinates.
  ///
  /// `false` only in the bootstrap "nothing seen yet" state, where the position
  /// is `NaN`. Integrators should fail safe on `!hasPosition` (draw nothing /
  /// keep the last dot) rather than plot a `NaN`.
  bool get hasPosition => latitude.isFinite && longitude.isFinite;

  @override
  String toString() => 'LocalizationEstimate(${mode.name}, '
      'lat: ${latitude.toStringAsFixed(5)}, '
      'lon: ${longitude.toStringAsFixed(5)}, '
      'radius: ${confidenceRadiusMeters.toStringAsFixed(0)}m, '
      'sinceTrusted: ${secondsSinceTrustedFix.toStringAsFixed(0)}s, '
      'basis: ${basis.name})';
}
