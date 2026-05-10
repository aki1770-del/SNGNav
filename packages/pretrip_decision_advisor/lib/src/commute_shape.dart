/// How flexible a planned commute is with respect to departure timing.
enum CommuteFlexibility {
  /// Required commute. Departure delay may incur cost (employer or
  /// other obligation). An advisor must not recommend a strong delay
  /// here; see [RecommendationStrength.honestyMode].
  required,

  /// Discretionary trip. The advisor may suggest delaying.
  discretionary,

  /// Flexibility is unknown. The caller should ask the user before
  /// trusting any advisor output.
  unknown,
}

/// Shape of a planned commute the advisor consumes.
///
/// The advisor does not compute or score routes. [routeIdentifiers] is
/// an opaque list of caller-supplied identifiers used only to
/// distinguish trips from each other.
class CommuteShape {
  CommuteShape({
    required this.plannedDuration,
    required this.routeIdentifiers,
    required this.flexibility,
    required this.plannedDeparture,
  });

  /// Planned trip duration as estimated by the caller.
  final Duration plannedDuration;

  /// Caller-supplied opaque route identifiers.
  final List<String> routeIdentifiers;

  /// Whether the commute is required, discretionary, or unknown.
  final CommuteFlexibility flexibility;

  /// Planned departure time.
  final DateTime plannedDeparture;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CommuteShape &&
        other.plannedDuration == plannedDuration &&
        _listEquals(other.routeIdentifiers, routeIdentifiers) &&
        other.flexibility == flexibility &&
        other.plannedDeparture == plannedDeparture;
  }

  @override
  int get hashCode => Object.hash(
    plannedDuration,
    Object.hashAll(routeIdentifiers),
    flexibility,
    plannedDeparture,
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
