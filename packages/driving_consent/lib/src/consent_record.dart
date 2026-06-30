/// Consent record — the atomic unit of privacy consent.
///
/// Fleet telemetry requires explicit, revocable consent — Jidoka semantics:
/// UNKNOWN = DENIED. The pipeline stops itself.
///
/// Three enums:
///   [ConsentStatus]  — granted / denied / unknown (3-state gate)
///   [ConsentPurpose] — what the data is used for (per-purpose, not blanket)
///   [Jurisdiction]   — which legal regime the integrator operates under (a per-record label)
library;

import 'package:equatable/equatable.dart';

/// Three-state consent gate.
///
/// Jidoka (自働化): UNKNOWN is treated as DENIED.
/// The machine stops and waits for the human.
enum ConsentStatus {
  /// Driver has explicitly granted consent for this purpose.
  granted,

  /// Driver has explicitly denied consent for this purpose.
  denied,

  /// Consent has never been requested or recorded.
  /// Treated as DENIED — the safe default.
  unknown,
}

/// What the data is used for — per-purpose consent.
///
/// Each purpose has its own consent state. The driver grants
/// fleet location sharing without granting diagnostics.
/// Edge developers add purposes without changing the gate.
enum ConsentPurpose {
  /// Share vehicle position with fleet aggregation server.
  /// The primary use case: hazard detection from fleet data.
  fleetLocation,

  /// Share local weather observations for crowd-sourced forecasting.
  weatherTelemetry,

  /// Share vehicle diagnostic data for fleet maintenance.
  diagnostics,

  // Instrumentation-class additions (v0.4.0)
  // Each value gates a feedback-class data flow used by the driver's
  // own on-device calibration. Default scope: stays on the device.
  // Off-device data flows require integrator-side substrate-class
  // decisions and are not opened by these enum values alone.

  /// The driver's alert-firing experience: how often alerts fire, how
  /// the driver responds (dismissal-pattern, modal-duration adherence).
  /// Used for the driver's own per-profile calibration. Stays on the
  /// driver's device by default at v0.4.0.
  alertExperienceInstrumentation,

  /// The driver's voice-guidance experience: voice-pace adjustments,
  /// speech-rate preferences. Used for the driver's own per-profile
  /// voice calibration. Stays on the driver's device by default at
  /// v0.4.0.
  voiceExperienceInstrumentation,

  /// The driver's cohort-multiplier effectiveness: did the per-cohort
  /// defaults produce the driver's preferred UX state? Used for the
  /// driver's own profile-default recalibration. Stays on the driver's
  /// device by default at v0.4.0.
  cohortCalibrationInstrumentation,

  /// The driver's trip-context capture: coarse vehicle-class + coarse
  /// time-of-day + driver-profile class, all integrator-supplied. Used
  /// for context-aware calibration. Stays on the driver's device by
  /// default. (Occupant-presence and consecutive-driving-day capture were
  /// removed in 0.5.0 — see CHANGELOG; the package does not instrument the
  /// cabin or the driver's body.)
  tripContextInstrumentation,
}

/// Legal jurisdiction governing this consent record.
///
/// A per-record label naming which legal regime the integrator is
/// operating under. This package provides per-purpose, jurisdiction-aware
/// consent STATE + Jidoka gates; it does NOT assert legal compliance.
/// Meeting GDPR / CCPA / APPI obligations is the integrator's
/// responsibility at their persistence and jurisdiction layer.
enum Jurisdiction {
  /// EU General Data Protection Regulation.
  gdpr,

  /// California Consumer Privacy Act.
  ccpa,

  /// Japan Act on the Protection of Personal Information (個人情報保護法).
  appi,
}

/// A single consent record — purpose + status + jurisdiction + timestamp.
///
/// Immutable. Each consent change produces a new record.
/// The [updatedAt] field provides the audit trail for compliance.
class ConsentRecord extends Equatable {
  final ConsentPurpose purpose;
  final ConsentStatus status;
  final Jurisdiction jurisdiction;
  final DateTime updatedAt;

  const ConsentRecord({
    required this.purpose,
    required this.status,
    required this.jurisdiction,
    required this.updatedAt,
  });

  /// Creates an unknown (never-set) record for a purpose.
  ///
  /// Used when no consent has been recorded. Jidoka: this blocks
  /// data flow — UNKNOWN is never effectively granted.
  ConsentRecord.unknown({
    required this.purpose,
    this.jurisdiction = Jurisdiction.gdpr,
  }) : status = ConsentStatus.unknown,
       updatedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// True only when the driver has explicitly granted consent.
  ///
  /// Jidoka: UNKNOWN and DENIED both return false.
  /// The pipeline stops itself — no data leaves the device.
  bool get isEffectivelyGranted => status == ConsentStatus.granted;

  /// True when the driver has explicitly denied consent.
  bool get isExplicitlyDenied => status == ConsentStatus.denied;

  /// True when consent has never been requested or recorded.
  bool get isUnknown => status == ConsentStatus.unknown;

  @override
  List<Object?> get props => [purpose, status, jurisdiction, updatedAt];

  @override
  String toString() =>
      'ConsentRecord(${purpose.name}: ${status.name}, '
      '${jurisdiction.name}, $updatedAt)';
}
