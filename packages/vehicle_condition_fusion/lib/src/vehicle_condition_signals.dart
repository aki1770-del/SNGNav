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
  });

  /// Most-probable road friction estimate (0.0–1.0) from the ESC.
  final double? roadFriction;

  /// Traction Control System currently engaged (active traction loss).
  final bool? tcsEngaged;

  /// Anti-lock Braking System currently engaged (braking on low friction).
  final bool? absEngaged;

  /// Front wiper intensity level (0–5) — precipitation proxy.
  final int? wiperIntensity;

  /// Rain-detection sensor intensity (0–100%).
  final int? rainIntensity;

  /// Ambient outside air temperature (°C).
  final double? airTempC;

  /// Vehicle speed (km/h) — carried for context; not used in classification.
  final double? speedKmh;

  /// Whether at least one classification-relevant signal has a real value.
  bool get hasAnySignal =>
      roadFriction != null ||
      tcsEngaged != null ||
      absEngaged != null ||
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
  /// (`roadFriction`, `tcsEngaged` / `absEngaged`) **persists** across later
  /// partial frames instead of silently dropping to `null` — closing the
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
        wiperIntensity,
        rainIntensity,
        airTempC,
        speedKmh,
      ];
}
