/// A point on HER hazard map plus whether the fix can be trusted.
///
/// [trusted] is false for a stale or wide-uncertainty dead-reckoned guess; it
/// drives the hold-caution fail-safe below.
class HazardFix {
  final double lat;
  final double lon;
  final bool trusted;
  const HazardFix(this.lat, this.lon, {this.trusted = true});
}

/// A hazard zone: a spatial membership test and the advisory for being inside it.
class AdvisoryZone<T> {
  final Object id;
  final T advisory;
  final bool Function(HazardFix fix) contains;
  const AdvisoryZone({
    required this.id,
    required this.advisory,
    required this.contains,
  });
}

/// Hazard-zone advisory state machine — refactored from the nav2 ZoneParameterFilter
/// (ros-navigation/navigation2 #6104).
///
/// In nav2 a costmap-mask cell selects a state whose parameter overrides are
/// *applied to the robot*. Here HER position selects a hazard zone whose advisory
/// is *offered to her*: SNGNav is a display aid (ASIL-QM), so the control semantics
/// become delivery semantics — we counsel, we do not command the vehicle. The
/// reusable element is the same: a spatial region maps to a response, transitions
/// are clean (only the active zone's advisory ever applies, so no warning from a
/// zone she has left lingers), and it stays generic over the advisory type `T` —
/// nothing winter-specific lives here; the caller supplies the advisories.
///
/// Two properties HER compound-failure world demands, which the nav2 original did
/// not have:
///  - Hold caution on an uncertain fix. nav2 threw out of its update loop on a
///    stray mask value, aborting navigation; here an untrusted or absent position
///    HOLDS her last advisory — a bad GPS pixel must never silently un-warn her.
///  - Never below [uncertain] at baseline. With an untrusted fix and no prior
///    caution to hold, surface [uncertain] rather than [baseline]: uncertainty is
///    shown, not painted over as safe (honest degradation).
class ZoneAdvisor<T> {
  /// Zones in priority order — the first zone that contains the fix wins, so order
  /// them most-cautious-first: the strongest hazard she is inside is the one she
  /// hears.
  final List<AdvisoryZone<T>> zones;

  /// Advisory when she is inside no hazard zone (nav2's state-0 baseline).
  final T baseline;

  /// Advisory when the fix is untrusted and there is no prior caution to hold.
  final T uncertain;

  Object? _currentZoneId;
  late T _current;

  ZoneAdvisor({
    required this.zones,
    required this.baseline,
    T? uncertain,
  })  : uncertain = uncertain ?? baseline {
    _current = baseline;
  }

  /// The advisory currently in effect.
  T get current => _current;

  /// The id of the zone in effect, or null when at baseline.
  Object? get currentZoneId => _currentZoneId;

  /// Feed a new fix; returns the advisory HER should receive now.
  T update(HazardFix? fix) {
    if (fix == null || !fix.trusted) {
      // Uncertain: hold. A bad fix may not reduce her warning. If she had no
      // caution to hold, surface `uncertain` rather than leaving her at baseline.
      if (_current == baseline) {
        _current = uncertain;
      }
      return _current;
    }
    for (final z in zones) {
      if (z.contains(fix)) {
        _currentZoneId = z.id;
        _current = z.advisory;
        return _current;
      }
    }
    // Trusted fix inside no hazard zone: she is out; revert cleanly to baseline.
    _currentZoneId = null;
    _current = baseline;
    return _current;
  }
}
