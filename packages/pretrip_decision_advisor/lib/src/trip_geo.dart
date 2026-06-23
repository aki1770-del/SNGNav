/// Where a planned trip happens, and how its wall clock relates to UTC.
///
/// This is the ONLY geographic input the daylight clock needs. It carries no
/// person, no track, no history — a latitude/longitude pair and the civil
/// offset of the route's wall clock. A clock about HER trip's light watches no
/// one: nothing here identifies, locates, or follows any driver between trips.
///
/// Conventions (kept explicit because sign errors here are silent and only
/// surface as a sunrise on the wrong side of noon):
///   * [latitude]  — degrees, NORTH positive (Akita ≈ +39.72).
///   * [longitude] — degrees, EAST  positive (Akita ≈ +140.10). The NOAA solar
///     formulas in `daylight.dart` are written in this east-positive form.
///   * [utcOffset] — the route-local civil offset from UTC (Japan ≈ +9 h). The
///     [CommuteShape] departure/arrival fields are NAIVE wall-clock times in
///     this offset; the astronomy converts them to UTC and back.
class TripGeo {
  const TripGeo({
    required this.latitude,
    required this.longitude,
    required this.utcOffset,
  });

  /// Degrees north of the equator (north positive).
  final double latitude;

  /// Degrees east of the prime meridian (east positive).
  final double longitude;

  /// Route-local civil offset from UTC (e.g. `Duration(hours: 9)` for JST).
  final Duration utcOffset;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TripGeo &&
        other.latitude == latitude &&
        other.longitude == longitude &&
        other.utcOffset == utcOffset;
  }

  @override
  int get hashCode => Object.hash(latitude, longitude, utcOffset);
}
