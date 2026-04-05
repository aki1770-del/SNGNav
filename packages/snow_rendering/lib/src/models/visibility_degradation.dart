/// Visibility degradation parameters derived from weather visibility.
///
/// Computes opacity and blur sigma values for fog/weather overlay effects.
/// Pure computation — application code decides how to apply these values.
library;

import 'package:equatable/equatable.dart';

class VisibilityDegradation extends Equatable {
  /// Overlay opacity (0.0 = fully transparent, 1.0 = fully opaque).
  ///
  /// Clamped to the range 0.0–0.9 — never fully occludes the view.
  final double opacity;

  /// Gaussian blur sigma for fog effect.
  /// 0.0 = no blur. Higher values = more blur.
  final double blurSigma;

  const VisibilityDegradation({
    required this.opacity,
    required this.blurSigma,
  });

  /// No degradation — fully clear.
  static const clear = VisibilityDegradation(opacity: 0.0, blurSigma: 0.0);

  /// Compute degradation from visibility in meters.
  ///
  /// Opacity formula: `1.0 - clamp(visibility / 1000, 0.1, 1.0)`.
  /// Blur formula: `max(0.0, (500 - visibility) / 50)`.
  ///
  /// At 1000m+ visibility: opacity 0.0, blur 0.0 (clear).
  /// At 100m visibility: opacity 0.9, blur 8.0 (dense fog).
  /// At 0m visibility: opacity 0.9, blur 10.0 (whiteout).
  factory VisibilityDegradation.compute(double visibilityMeters) {
    if (visibilityMeters < 0) {
      visibilityMeters = 0;
    }

    final normalised = (visibilityMeters / 1000).clamp(0.1, 1.0);
    final opacity = (1.0 - normalised).clamp(0.0, 0.9);
    final blurSigma = ((500 - visibilityMeters) / 50).clamp(0.0, 10.0);

    return VisibilityDegradation(opacity: opacity, blurSigma: blurSigma);
  }

  @override
  List<Object?> get props => [opacity, blurSigma];
}
