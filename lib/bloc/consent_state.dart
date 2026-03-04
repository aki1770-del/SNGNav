/// Consent state — privacy consent gate for fleet data.
///
/// State transitions:
///   idle → loading (load requested)
///   loading → ready (consents loaded from service)
///   loading → error (service error)
///   ready → ready (grant/revoke updates the map)
///   error → loading (retry)
///
/// Jidoka convenience getters: `isFleetGranted`, `isWeatherGranted`,
/// `isDiagnosticsGranted` all return false when status is not ready
/// or when the specific purpose has not been explicitly granted.
///
/// Consent is explicit, revocable, and purpose-scoped.
library;

import 'package:equatable/equatable.dart';

import '../models/consent_record.dart';

enum ConsentBlocStatus {
  /// Not yet loaded.
  idle,

  /// Loading consents from service.
  loading,

  /// Consents loaded and available.
  ready,

  /// Service error.
  error,
}

class ConsentState extends Equatable {
  final ConsentBlocStatus status;
  final Map<ConsentPurpose, ConsentRecord> consents;
  final String? errorMessage;

  const ConsentState({
    required this.status,
    this.consents = const {},
    this.errorMessage,
  });

  const ConsentState.idle()
      : status = ConsentBlocStatus.idle,
        consents = const {},
        errorMessage = null;

  // ---------------------------------------------------------------------------
  // Jidoka getters — false unless explicitly granted AND state is ready
  // ---------------------------------------------------------------------------

  /// True only when fleet location consent is explicitly granted.
  bool get isFleetGranted => _isGranted(ConsentPurpose.fleetLocation);

  /// True only when weather telemetry consent is explicitly granted.
  bool get isWeatherGranted => _isGranted(ConsentPurpose.weatherTelemetry);

  /// True only when diagnostics consent is explicitly granted.
  bool get isDiagnosticsGranted => _isGranted(ConsentPurpose.diagnostics);

  /// True when all purposes are effectively denied (none granted).
  bool get isAllDenied =>
      !isFleetGranted && !isWeatherGranted && !isDiagnosticsGranted;

  /// Get the consent record for a specific purpose.
  /// Returns null if not loaded.
  ConsentRecord? consentFor(ConsentPurpose purpose) => consents[purpose];

  bool _isGranted(ConsentPurpose purpose) {
    if (status != ConsentBlocStatus.ready) return false;
    final record = consents[purpose];
    if (record == null) return false;
    return record.isEffectivelyGranted;
  }

  ConsentState copyWith({
    ConsentBlocStatus? status,
    Map<ConsentPurpose, ConsentRecord>? consents,
    String? errorMessage,
  }) {
    return ConsentState(
      status: status ?? this.status,
      consents: consents ?? this.consents,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, consents, errorMessage];

  @override
  String toString() {
    final granted = consents.values
        .where((r) => r.isEffectivelyGranted)
        .map((r) => r.purpose.name)
        .join(', ');
    return 'ConsentState($status, granted=[$granted])';
  }
}
