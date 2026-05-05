/// Instrumentation events — feedback-class records for on-device calibration.
///
/// Sealed class hierarchy: `InstrumentationEvent` is the closed-set parent
/// type and only the four subtypes declared in this file may extend it.
/// Each subtype carries the minimum field set needed for the driver's own
/// calibration loop. Zero GPS, zero destination, zero PII.
///
/// The events are gated by per-purpose consent at the
/// `InstrumentationService.recordEvent` boundary. UNKNOWN equals DENIED:
/// recording an event for a purpose whose consent is not explicitly granted
/// throws `StateError`. The line stops itself.
///
/// Driver-facing-loom posture: instrumentation is feedback-class, not
/// control-loop-class. The driver always drives; instrumentation only
/// shapes the driver's own next-trip experience.
library;

import 'package:equatable/equatable.dart';

/// Sealed parent for the closed set of instrumentation event subtypes.
///
/// Subtypes:
///   * [AlertFired]
///   * [VoicePaceAdjusted]
///   * [CohortMultiplierObserved]
///   * [TripContextCaptured]
///
/// Consumers exhaust the set via switch-class pattern matching; adding a
/// new subtype is a deliberate API change at the package boundary.
sealed class InstrumentationEvent extends Equatable {
  /// Wall-clock timestamp at which the event was observed.
  final DateTime timestamp;

  /// Per-device-install opaque identifier for the driver. Stable for the
  /// life of the install; never linked across installs by the package.
  final String driverPseudonym;

  const InstrumentationEvent({
    required this.timestamp,
    required this.driverPseudonym,
  });
}

/// Severity-class enum for `AlertFired` events.
///
/// Profile-blind: severity decides whether/what; the integrator's HMI
/// renders the same severity differently per driver profile, but the gate
/// itself reads severity, never profile.
enum AlertSeverity {
  /// Advisory information; no action required.
  info,

  /// Caution; the driver should be aware.
  caution,

  /// Warning; the driver should adjust behavior.
  warning,

  /// Critical; immediate attention.
  critical,
}

/// How the driver dismissed the alert (or did not).
enum AlertDismissalState {
  /// The alert ran its full intended modal duration before clearing.
  ranToCompletion,

  /// The driver dismissed the alert before its modal duration elapsed.
  dismissedEarly,

  /// The alert was suppressed by a downstream gate (e.g. severity-cap).
  suppressed,

  /// The driver acknowledged the alert via an explicit input.
  acknowledged,
}

/// Why a voice-pace adjustment occurred.
enum VoicePaceAdjustmentReason {
  /// The driver adjusted voice pace via an explicit setting.
  driverPreference,

  /// The integrator's HMI applied a per-profile default.
  profileDefault,

  /// A cohort-class default applied at session start.
  cohortDefault,

  /// A context-aware adjustment (e.g. quieter cabin context).
  contextAware,
}

/// Cohort-class multiplier classes the integrator may apply.
///
/// Profile-aware at the rendering layer; the gate stays profile-blind.
enum CohortMultiplierClass {
  /// Default cohort; no multiplier applied.
  defaultCohort,

  /// Snow-zone-experienced driver cohort.
  snowZoneExperienced,

  /// Aging-rural driver cohort.
  ageingRural,

  /// Foreign-tourist driver in a snow zone.
  foreignTouristSnowZone,

  /// Other / unspecified cohort class.
  other,
}

/// How well the cohort-class default fit the driver's actual preference.
enum ObservedFitClass {
  /// The default fit the driver well; no override observed.
  goodFit,

  /// The driver overrode the default upward (more aggressive).
  overrodeUpward,

  /// The driver overrode the default downward (less aggressive).
  overrodeDownward,

  /// The driver disabled the feature entirely after the default.
  disabled,
}

/// Vehicle-class enum populated by the integrator's `VehicleClass` provider.
enum VehicleClass {
  /// Passenger car.
  passengerCar,

  /// Light commercial / van.
  lightCommercial,

  /// Heavy goods vehicle / truck.
  heavyGoodsVehicle,

  /// Two-wheeler.
  motorcycle,

  /// Other / unspecified.
  other,
}

/// Passenger-presence class populated by the integrator.
enum PassengerPresenceClass {
  /// Driver only.
  driverOnly,

  /// Driver plus one passenger.
  driverPlusOne,

  /// Driver plus multiple passengers.
  driverPlusMany,

  /// Unknown / not provided.
  unknown,
}

/// Coarse time-of-day class for context-aware calibration.
enum TimeOfDayClass {
  /// Pre-dawn / early morning.
  earlyMorning,

  /// Daytime.
  day,

  /// Evening / dusk.
  evening,

  /// Night.
  night,
}

/// Coarse driving-day-streak class.
enum ConsecutiveDrivingDayClass {
  /// First driving day in the current streak.
  firstDay,

  /// Two-to-three consecutive driving days.
  twoToThree,

  /// Four-to-six consecutive driving days.
  fourToSix,

  /// Seven or more consecutive driving days.
  sevenPlus,
}

/// Coarse driver-profile class.
///
/// The package never branches the gate decision on this field; profile
/// awareness lives upstream at the integrator's HMI rendering layer.
enum DriverProfileClass {
  /// Default / unspecified driver profile.
  defaultProfile,

  /// Snow-zone-experienced driver.
  snowZoneExperienced,

  /// Aging-rural driver.
  ageingRural,

  /// Foreign-tourist driver in a snow zone.
  foreignTouristSnowZone,

  /// Other.
  other,
}

/// An alert fired through the integrator's HMI.
///
/// Records the alert-class, severity, modal-duration, and how the driver
/// responded. Used to calibrate the driver's per-profile alert experience.
final class AlertFired extends InstrumentationEvent {
  /// Integrator-class identifier for the alert (e.g. `snow_road_warning`).
  final String alertClass;

  /// Severity at firing time.
  final AlertSeverity severity;

  /// Intended modal duration on the HMI.
  final Duration modalDuration;

  /// How the alert ended.
  final AlertDismissalState dismissalState;

  /// The driver's profile class at firing time (for downstream rendering;
  /// the gate itself does not branch on profile).
  final DriverProfileClass driverProfile;

  const AlertFired({
    required super.timestamp,
    required super.driverPseudonym,
    required this.alertClass,
    required this.severity,
    required this.modalDuration,
    required this.dismissalState,
    required this.driverProfile,
  });

  @override
  List<Object?> get props => [
        timestamp,
        driverPseudonym,
        alertClass,
        severity,
        modalDuration,
        dismissalState,
        driverProfile,
      ];

  @override
  String toString() =>
      'AlertFired(at $timestamp, class=$alertClass, severity=${severity.name}, '
      'duration=$modalDuration, end=${dismissalState.name})';
}

/// A voice-guidance pace adjustment event.
final class VoicePaceAdjusted extends InstrumentationEvent {
  /// Previous speech rate (multiplier; 1.0 = baseline).
  final double previousRate;

  /// New speech rate (multiplier; 1.0 = baseline).
  final double newRate;

  /// Why the adjustment was applied.
  final VoicePaceAdjustmentReason adjustmentReason;

  /// The driver's profile class at adjustment time.
  final DriverProfileClass driverProfile;

  const VoicePaceAdjusted({
    required super.timestamp,
    required super.driverPseudonym,
    required this.previousRate,
    required this.newRate,
    required this.adjustmentReason,
    required this.driverProfile,
  });

  @override
  List<Object?> get props => [
        timestamp,
        driverPseudonym,
        previousRate,
        newRate,
        adjustmentReason,
        driverProfile,
      ];

  @override
  String toString() =>
      'VoicePaceAdjusted(at $timestamp, $previousRate -> $newRate, '
      'reason=${adjustmentReason.name})';
}

/// A cohort-multiplier observation event.
final class CohortMultiplierObserved extends InstrumentationEvent {
  /// The driver's profile class at observation time.
  final DriverProfileClass driverProfile;

  /// The cohort-multiplier class applied.
  final CohortMultiplierClass cohortMultiplierClass;

  /// The numeric multiplier applied (e.g. 1.0, 1.25).
  final double appliedMultiplier;

  /// How well the default fit the driver's actual preference.
  final ObservedFitClass observedFitClass;

  const CohortMultiplierObserved({
    required super.timestamp,
    required super.driverPseudonym,
    required this.driverProfile,
    required this.cohortMultiplierClass,
    required this.appliedMultiplier,
    required this.observedFitClass,
  });

  @override
  List<Object?> get props => [
        timestamp,
        driverPseudonym,
        driverProfile,
        cohortMultiplierClass,
        appliedMultiplier,
        observedFitClass,
      ];

  @override
  String toString() =>
      'CohortMultiplierObserved(at $timestamp, '
      'cohort=${cohortMultiplierClass.name}, x$appliedMultiplier, '
      'fit=${observedFitClass.name})';
}

/// A trip-context capture event.
///
/// Coarse classes only; no GPS, no destination, no PII.
final class TripContextCaptured extends InstrumentationEvent {
  /// Vehicle class as provided by the integrator.
  final VehicleClass vehicleClass;

  /// Passenger-presence class as provided by the integrator.
  final PassengerPresenceClass passengerPresenceClass;

  /// Coarse time-of-day class.
  final TimeOfDayClass timeOfDayClass;

  /// Coarse consecutive-driving-day class.
  final ConsecutiveDrivingDayClass consecutiveDrivingDayClass;

  /// The driver's profile class at capture time.
  final DriverProfileClass driverProfile;

  const TripContextCaptured({
    required super.timestamp,
    required super.driverPseudonym,
    required this.vehicleClass,
    required this.passengerPresenceClass,
    required this.timeOfDayClass,
    required this.consecutiveDrivingDayClass,
    required this.driverProfile,
  });

  @override
  List<Object?> get props => [
        timestamp,
        driverPseudonym,
        vehicleClass,
        passengerPresenceClass,
        timeOfDayClass,
        consecutiveDrivingDayClass,
        driverProfile,
      ];

  @override
  String toString() =>
      'TripContextCaptured(at $timestamp, vehicle=${vehicleClass.name}, '
      'passengers=${passengerPresenceClass.name}, '
      'tod=${timeOfDayClass.name}, '
      'streak=${consecutiveDrivingDayClass.name})';
}
