/// The dynamics the filter should expect from whatever is carrying the device.
///
/// ## Why this exists
///
/// Through 0.6.1 the process-noise vector was a private `static const` tuned,
/// in its own words, *"for road driving at ~1 Hz GPS updates"*, with entries
/// annotated *"driver brakes/accelerates"* and *"driver turns"*. There was no
/// injection point. A consumer whose device is carried by a **runner** rather
/// than a car had no supported way to tune it, and the only remaining option
/// was to fork the filter.
///
/// That is not a hypothetical. A verified external consumer pinned this package
/// to an exact version and wrote a fork plan into their own docs, naming a
/// tuning need we had welded shut. **This class exists so that leaving is not
/// the only way to tune.**
///
/// ## The honest bound on [pedestrian]
///
/// [roadVehicle] is the calibrated default: those numbers are unchanged from
/// 0.6.1 and carry whatever validation the road case ever had.
///
/// **[pedestrian] is DERIVED, NOT MEASURED.** It is reasoned from published
/// gait dynamics, not fitted against recorded pedestrian traces, because this
/// package has no such traces — `test/` contains zero trajectory fixtures. It
/// is offered as a **starting point whose derivation is shown so you can check
/// it**, never as a calibrated profile. If you have real traces, fit your own
/// with the unnamed constructor and please tell us what you found.
///
/// Presenting a reasoned guess as a calibration would be worse than shipping
/// nothing: it would read as a warrant this package cannot issue.
class MotionProfile {
  /// Latitude variance growth per second, in deg²/s.
  final double latVariancePerSecond;

  /// Longitude variance growth per second, in deg²/s.
  final double lonVariancePerSecond;

  /// Speed variance growth per second, in (m/s)²/s.
  ///
  /// How fast the carrier's speed can change. A braking car is far more
  /// volatile than a running human.
  final double speedVariancePerSecond;

  /// Heading variance growth per second, in (deg)²/s.
  ///
  /// How fast the carrier's direction can change. This is the entry that
  /// separates a pedestrian from a vehicle most sharply.
  final double headingVariancePerSecond;

  /// A human-readable name, surfaced in diagnostics and [toString].
  final String name;

  const MotionProfile({
    required this.latVariancePerSecond,
    required this.lonVariancePerSecond,
    required this.speedVariancePerSecond,
    required this.headingVariancePerSecond,
    this.name = 'custom',
  });

  /// The 0.6.1 defaults, unchanged. Road driving at ~1 Hz GPS updates.
  ///
  /// This remains the default for every existing caller: nothing about an
  /// existing integration changes by upgrading to a version that has this class.
  static const roadVehicle = MotionProfile(
    latVariancePerSecond: 1e-10,
    lonVariancePerSecond: 1e-10,
    speedVariancePerSecond: 0.5,
    headingVariancePerSecond: 1.0,
    name: 'roadVehicle',
  );

  /// ⚑ **DERIVED, NOT MEASURED.** A starting point for a device carried by a
  /// walking or running human. The derivation, so you can disagree with it:
  ///
  /// **Heading — raised from 1.0 to 100.0.** A car at 50 km/h needs several
  /// seconds to turn 90 degrees; a runner rounding a corner can do it in about
  /// one. Modelling a ~10x faster achievable turn rate as variance scales by
  /// roughly the square, so ~100x. Under-modelling this is the failure that
  /// matters for loop closure: the filter smooths through a real corner, the
  /// track cuts it, and the loop does not close.
  ///
  /// **Speed — lowered from 0.5 to 0.1.** Running speed varies gently around
  /// 3-5 m/s. It has no equivalent of a hard brake, so trusting the
  /// constant-velocity model MORE is correct here.
  ///
  /// **Position — unchanged.** These terms model process drift, not carrier
  /// dynamics, and nothing about being on foot changes them.
  static const pedestrian = MotionProfile(
    latVariancePerSecond: 1e-10,
    lonVariancePerSecond: 1e-10,
    speedVariancePerSecond: 0.1,
    headingVariancePerSecond: 100.0,
    name: 'pedestrian (derived, not measured)',
  );

  /// The vector the filter consumes: `[lat, lon, speed, heading]`.
  List<double> get asVector => [
    latVariancePerSecond,
    lonVariancePerSecond,
    speedVariancePerSecond,
    headingVariancePerSecond,
  ];

  /// Whether every term is finite and positive.
  ///
  /// A non-positive or non-finite process noise breaks the covariance update
  /// silently rather than loudly, so the filter refuses such a profile at
  /// construction instead of producing plausible nonsense.
  bool get isValid => asVector.every((v) => v.isFinite && v > 0);

  @override
  String toString() => 'MotionProfile($name)';
}
