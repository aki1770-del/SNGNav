import 'trip_geo.dart';

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
    this.geo,
  });

  /// Planned trip duration as estimated by the caller.
  final Duration plannedDuration;

  /// Caller-supplied opaque route identifiers.
  final List<String> routeIdentifiers;

  /// Whether the commute is required, discretionary, or unknown.
  final CommuteFlexibility flexibility;

  /// Planned departure time.
  final DateTime plannedDeparture;

  /// Where the trip happens, for the offline daylight clock. Null means the
  /// feature is absent: no daylight chip is emitted and behaviour is exactly as
  /// before this field existed (fully backward compatible).
  final TripGeo? geo;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CommuteShape &&
        other.plannedDuration == plannedDuration &&
        _listEquals(other.routeIdentifiers, routeIdentifiers) &&
        other.flexibility == flexibility &&
        other.plannedDeparture == plannedDeparture &&
        other.geo == geo;
  }

  @override
  int get hashCode => Object.hash(
    plannedDuration,
    Object.hashAll(routeIdentifiers),
    flexibility,
    plannedDeparture,
    geo,
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
