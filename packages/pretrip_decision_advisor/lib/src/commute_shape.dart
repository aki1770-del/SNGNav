/// How flexible the caller's commute is.
///
/// This is the load-bearing input that prevents the advisor from
/// silently translating a non-negotiable obligation into a delay
/// suggestion. See [PretripAdvisor]'s class-level contract.
enum CommuteFlexibility {
  /// The driver must be at the destination at the planned time
  /// (school run, shift start, medical appointment). The advisor
  /// MUST NOT recommend a delay; only honesty-mode or null is valid.
  required,

  /// The driver has flexibility (errand, optional meeting, leisure).
  /// The advisor may suggest a delay if conditions warrant.
  discretionary,

  /// Flexibility is unknown. The advisor should treat this as the
  /// safer of the two by defaulting toward honesty-mode rather than
  /// strong delay suggestions.
  unknown,
}

/// Caller-supplied description of the commute being planned.
class CommuteShape {
  const CommuteShape({
    required this.flexibility,
    required this.estimatedDriveDuration,
    this.plannedDepartureLocalTime,
  });

  /// How negotiable the arrival time is. See [CommuteFlexibility].
  final CommuteFlexibility flexibility;

  /// Caller's estimate of how long the drive will take under
  /// nominal conditions. The advisor uses this only as a horizon
  /// over which to evaluate the forecast.
  final Duration estimatedDriveDuration;

  /// Caller's planned local departure time, if known. The advisor
  /// uses this to align forecast hours with the trip window.
  final DateTime? plannedDepartureLocalTime;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CommuteShape &&
        other.flexibility == flexibility &&
        other.estimatedDriveDuration == estimatedDriveDuration &&
        other.plannedDepartureLocalTime == plannedDepartureLocalTime;
  }

  @override
  int get hashCode => Object.hash(
        flexibility,
        estimatedDriveDuration,
        plannedDepartureLocalTime,
      );
}
