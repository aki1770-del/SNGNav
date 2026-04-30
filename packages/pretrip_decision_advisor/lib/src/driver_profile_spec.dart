/// Lightweight driver profile spec consumed by [PretripAdvisor].
///
/// This spec is intentionally decoupled from any larger driver-profile
/// package so that consumers using only this advisor do not have to
/// take on an unrelated runtime dependency. Consumers who already
/// carry a richer profile model can adapt to this spec at their
/// boundary.
class DriverProfileSpec {
  const DriverProfileSpec({
    required this.profileTag,
    required this.reactionTimeSeconds,
    this.unfamiliarRouteFlag,
  });

  /// Caller-supplied profile tag, for example `"ageingRural"` or
  /// `"noviceUrban"`. Opaque to the advisor.
  final String profileTag;

  /// Driver reaction-time estimate in seconds. Used by an
  /// implementation as a calibration input only; it does not change
  /// the strength of the recommendation.
  final double reactionTimeSeconds;

  /// True if the driver is on an unfamiliar route. Null if unknown.
  final bool? unfamiliarRouteFlag;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DriverProfileSpec &&
        other.profileTag == profileTag &&
        other.reactionTimeSeconds == reactionTimeSeconds &&
        other.unfamiliarRouteFlag == unfamiliarRouteFlag;
  }

  @override
  int get hashCode => Object.hash(
        profileTag,
        reactionTimeSeconds,
        unfamiliarRouteFlag,
      );
}
