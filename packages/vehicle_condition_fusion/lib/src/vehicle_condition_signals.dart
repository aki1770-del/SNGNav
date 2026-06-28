import 'package:equatable/equatable.dart';

/// An immutable, decoded snapshot of the snow-safety vehicle signals.
///
/// All fields are nullable: a signal the vehicle has not (yet) published is
/// `null`, never a fabricated default.
///
/// This is the SDK-free input seam of the package. It is *decoupled* from any
/// transport: construct it directly (e.g. in a test, `const
/// VehicleConditionSignals(roadFriction: 0.2)`), from a KUKSA databroker
/// adapter, from your own CAN reader, or from any other source. The package
/// never depends on how the snapshot was produced.
class VehicleConditionSignals extends Equatable {
  const VehicleConditionSignals({
    this.roadFriction,
    this.tcsEngaged,
    this.absEngaged,
    this.wiperIntensity,
    this.rainIntensity,
    this.airTempC,
    this.speedKmh,
    this.escEngaged,
  });

  /// Most-probable road friction estimate (0.0–1.0) from the ESC.
  final double? roadFriction;

  /// Traction Control System currently engaged (active traction loss).
  final bool? tcsEngaged;

  /// Anti-lock Braking System currently engaged (braking on low friction).
  final bool? absEngaged;

  /// Electronic Stability Control currently regulating vehicle stability
  /// (a traction-loss event, like TCS/ABS — an ice indicator on a cold road).
  final bool? escEngaged;

  /// Front-wiper intensity SETPOINT — an actuator level (`uint8`, relative,
  /// **no fixed max**), i.e. the intensity *requested by the driver/system*,
  /// significant only when the wiper mode is interval / rain-sensor. It is a
  /// coarse precipitation *cue*, NOT a measured precipitation value — the
  /// measured precipitation channel is the separate [rainIntensity] sensor.
  final int? wiperIntensity;

  /// Rain-detection SENSOR intensity (0–100%) — a measured precipitation value.
  final int? rainIntensity;

  /// Ambient outside air temperature (°C).
  final double? airTempC;

  /// Vehicle speed (km/h) — carried for context; not used in classification.
  final double? speedKmh;

  // -------------------------------------------------------------------------
  // COVESA VSS adapter (standard leaf paths → these seven fields).
  // -------------------------------------------------------------------------

  /// VSS leaf path for [roadFriction] — most-probable road-friction estimate.
  /// **PERCENT (0–100)** in VSS, so [fromVss] divides by 100 and clamps to 0–1.
  static const String vssRoadFriction =
      'Vehicle.ADAS.ESC.RoadFriction.MostProbable';

  /// VSS leaf path for [tcsEngaged].
  static const String vssTcsEngaged = 'Vehicle.ADAS.TCS.IsEngaged';

  /// VSS leaf path for [absEngaged].
  static const String vssAbsEngaged = 'Vehicle.ADAS.ABS.IsEngaged';

  /// VSS leaf path for [escEngaged] — ESC currently regulating stability.
  static const String vssEscEngaged = 'Vehicle.ADAS.ESC.IsEngaged';

  /// VSS leaf path for [airTempC] — ambient air temperature, Celsius.
  static const String vssAirTemperature = 'Vehicle.Exterior.AirTemperature';

  /// VSS leaf path for [speedKmh] — vehicle speed, km/h.
  static const String vssSpeed = 'Vehicle.Speed';

  /// VSS leaf path for [wiperIntensity] — front-wiper intensity setpoint.
  /// `Windshield` is an instanced branch (`["Front", "Rear"]`) in VSS, so the
  /// deployed databroker leaf is the **Front**-instance path.
  static const String vssWiperIntensity =
      'Vehicle.Body.Windshield.Front.Wiping.Intensity';

  /// VSS leaf path for [rainIntensity] — rain-detection intensity, PERCENT.
  static const String vssRainIntensity = 'Vehicle.Body.Raindetection.Intensity';

  /// The exact set of COVESA VSS leaf paths [fromVss] reads, for discoverability
  /// (e.g. to build a KUKSA `subscribe` request) and for tests.
  static const List<String> recognizedVssPaths = [
    vssRoadFriction,
    vssTcsEngaged,
    vssAbsEngaged,
    vssEscEngaged,
    vssAirTemperature,
    vssSpeed,
    vssWiperIntensity,
    vssRainIntensity,
  ];

  /// Build a snapshot from **standard COVESA VSS** (Vehicle Signal Specification,
  /// **v6.0**) leaf paths — the map a KUKSA databroker `get` / `subscribe`
  /// yields: each key is a VSS leaf-path string, each value is that leaf's value.
  ///
  /// This is the zero-glue seam: hand a KUKSA reader's decoded `{path: value}`
  /// map straight in and get a typed [VehicleConditionSignals], with no
  /// per-field mapping code of your own. The paths read are exactly
  /// [recognizedVssPaths]; unknown / extra keys are ignored.
  ///
  /// **Honesty (never fabricate).** A path **absent** from the map — or present
  /// with a `null` value — leaves that field `null`. A path present with a
  /// non-coercible value (wrong type / garbage frame) also degrades to `null`
  /// for that field; this never throws, so a single malformed leaf cannot crash
  /// the safety pipeline.
  ///
  /// **Mapping notes.**
  ///  * [vssRoadFriction] (`ESC.RoadFriction.MostProbable`) is a **PERCENT
  ///    (0–100)** in VSS, so it is divided by 100 and clamped to `0.0..1.0`.
  ///  * [vssRainIntensity] is a PERCENT, rounded to `int` and clamped `0..100`.
  ///  * [vssWiperIntensity] is a relative `uint8` level with **no fixed max** in
  ///    VSS, so it is rounded to `int` and clamped `>= 0` only (not to any upper
  ///    bound — the classifier buckets it).
  ///  * numeric leaves accept either `int` or `double` (a non-finite `double`
  ///    such as `NaN`/`Infinity` degrades to `null`, never a fabricated value).
  ///  * the VSS-typed **boolean** leaves ([vssTcsEngaged] / [vssAbsEngaged] /
  ///    [vssEscEngaged]) accept a Dart `bool`, or an int `1`/`0` (faithful
  ///    decoding of a `boolean` leaf from a CAN bridge / non-SDK source — so a
  ///    traction-loss ice signal is not silently dropped); any other value →
  ///    `null`. This `1`/`0`→`bool` leniency is scoped to these boolean leaves
  ///    only; numeric leaves never accept a `bool`.
  ///
  /// **Now mapped (v0.3.0).**
  ///  * `Vehicle.ADAS.ESC.IsEngaged` → [escEngaged]; like TCS/ABS it contributes
  ///    to cold-slip ice risk (see `vehicleSignalsToWeatherCondition`).
  ///
  /// **Intentionally NOT mapped.**
  ///  * The `Vehicle.Exterior.RoadSurfaceCondition` family (VSS `master` /
  ///    unreleased v7) is **not** used because it is not in any released VSS
  ///    spec.
  ///
  /// **Partial-frame transports (KUKSA `subscribe`).** A `subscribe` re-sends
  /// only the leaves that changed. Build a `fromVss` snapshot **per frame**, then
  /// drive [VehicleConditionFusion.fromPartialFrames] (or merge with
  /// [carriedForwardOnto]) so a once-seen ice signal is held across later partial
  /// frames — do **not** feed partial frames to the complete-snapshot rail.
  factory VehicleConditionSignals.fromVss(Map<String, Object?> leaves) {
    final frictionPct = _asDouble(leaves[vssRoadFriction]);
    return VehicleConditionSignals(
      roadFriction:
          frictionPct == null ? null : (frictionPct / 100.0).clamp(0.0, 1.0),
      tcsEngaged: _asVssBool(leaves[vssTcsEngaged]),
      absEngaged: _asVssBool(leaves[vssAbsEngaged]),
      escEngaged: _asVssBool(leaves[vssEscEngaged]),
      airTempC: _asDouble(leaves[vssAirTemperature]),
      speedKmh: _asDouble(leaves[vssSpeed]),
      wiperIntensity: _clampMinInt(_asInt(leaves[vssWiperIntensity]), 0),
      rainIntensity: _clampInt(_asInt(leaves[vssRainIntensity]), 0, 100),
    );
  }

  /// Coerce a VSS numeric leaf to `double`; returns `null` on null, a
  /// non-numeric value, OR a non-finite `double` (`NaN`/`Infinity`). The
  /// non-finite guard is load-bearing: a `NaN` friction would otherwise survive
  /// `(NaN/100).clamp(0,1) == 1.0` and fabricate MAX grip — a dangerous
  /// under-warn. A garbage frame degrades to `null`, never throws.
  static double? _asDouble(Object? v) {
    if (v is double) return v.isFinite ? v : null;
    if (v is int) return v.toDouble();
    return null;
  }

  /// Coerce a VSS numeric leaf to `int` (rounding a `double`); returns `null` on
  /// null, a non-numeric value, or a non-finite `double` (`NaN`/`Infinity`,
  /// whose `.round()` throws — guarded here so the contract never throws).
  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is double) return v.isFinite ? v.round() : null;
    return null;
  }

  /// Coerce a VSS-typed **boolean** leaf: a Dart `bool` passes through, and an
  /// int `1`→`true` / `0`→`false` (faithful decoding of a `boolean` leaf from a
  /// CAN bridge / non-SDK source, so a traction-loss signal is not dropped).
  /// Anything else (including a non-1/0 int or a `"true"` string) → `null`.
  /// Scoped to boolean leaves; numeric leaves never accept a `bool`.
  static bool? _asVssBool(Object? v) {
    if (v is bool) return v;
    if (v is int) {
      if (v == 1) return true;
      if (v == 0) return false;
    }
    return null;
  }

  static int? _clampInt(int? v, int lo, int hi) => v?.clamp(lo, hi);

  static int? _clampMinInt(int? v, int lo) => v == null ? null : (v < lo ? lo : v);

  /// Whether at least one classification-relevant signal has a real value.
  bool get hasAnySignal =>
      roadFriction != null ||
      tcsEngaged != null ||
      absEngaged != null ||
      escEngaged != null ||
      wiperIntensity != null ||
      rainIntensity != null ||
      airTempC != null;

  /// Carry-forward merge for **partial-frame** transports.
  ///
  /// Treats `this` as a newer *partial frame* from a source that re-sends only
  /// the signals that changed (the documented-primary KUKSA `subscribe` path),
  /// and returns a new, complete snapshot laid over [previous]: for **each of
  /// the seven fields**, `this` (the newer frame)'s value is used when non-null,
  /// otherwise [previous]'s value is carried forward.
  ///
  /// A `null` in a partial frame therefore means **"unchanged — not re-sent this
  /// cycle"**, NOT "this signal is now unknown". This reproduces a partial-frame
  /// transport's last-known-value semantics, so a once-seen ice-risk signal
  /// (`roadFriction`, `tcsEngaged` / `absEngaged` / `escEngaged`) **persists**
  /// across later partial frames instead of silently dropping to `null` — closing the
  /// under-warn gap where the picture would look safe precisely while the ice
  /// hazard on the road persists unchanged.
  ///
  /// This is the OPPOSITE of complete-snapshot semantics. For a source where a
  /// `null` genuinely means "this signal is no longer valid" (a CAN reader, a
  /// sensor-fusion source, or a test), do NOT carry forward — feed complete
  /// snapshots to the default [VehicleConditionFusion] constructor, which treats
  /// every snapshot as complete and never carries forward, so it never
  /// stale-over-warns. The carry-forward decision belongs to whoever knows the
  /// transport's framing semantics, which is why it is an explicit, opt-in step
  /// (used for you by [VehicleConditionFusion.fromPartialFrames]).
  VehicleConditionSignals carriedForwardOnto(VehicleConditionSignals previous) {
    return VehicleConditionSignals(
      roadFriction: roadFriction ?? previous.roadFriction,
      tcsEngaged: tcsEngaged ?? previous.tcsEngaged,
      absEngaged: absEngaged ?? previous.absEngaged,
      escEngaged: escEngaged ?? previous.escEngaged,
      wiperIntensity: wiperIntensity ?? previous.wiperIntensity,
      rainIntensity: rainIntensity ?? previous.rainIntensity,
      airTempC: airTempC ?? previous.airTempC,
      speedKmh: speedKmh ?? previous.speedKmh,
    );
  }

  @override
  List<Object?> get props => [
        roadFriction,
        tcsEngaged,
        absEngaged,
        escEngaged,
        wiperIntensity,
        rainIntensity,
        airTempC,
        speedKmh,
      ];
}
