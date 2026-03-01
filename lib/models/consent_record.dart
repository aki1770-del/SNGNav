/// Consent record — the atomic unit of privacy consent in SNGNav.
///
/// Fleet telemetry requires explicit, revocable consent — Jidoka semantics:
/// UNKNOWN = DENIED. The pipeline stops itself.
///
/// Three enums:
///   [ConsentStatus]  — granted / denied / unknown (3-state gate)
///   [ConsentPurpose] — what the data is used for (per-purpose, not blanket)
///   [Jurisdiction]   — which legal regime applies (design for GDPR, deploy everywhere)
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
}

/// Legal jurisdiction governing this consent record.
///
/// "Design for GDPR, deploy everywhere":
/// An architecture that passes EDPB scrutiny automatically
/// satisfies APPI and CCPA. Zero jurisdiction-specific code paths.
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
  })  : status = ConsentStatus.unknown,
        updatedAt = DateTime.fromMillisecondsSinceEpoch(0);

  // ---------------------------------------------------------------------------
  // Jidoka getters
  // ---------------------------------------------------------------------------

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
