/// Fleet state — fleet telemetry and hazard aggregation.
///
/// State transitions:
///   idle → listening (on start)
///   listening → listening (new report received — updates active reports)
///   listening → idle (on stop)
///   listening → error (provider error)
///   error → listening (restart)
///
/// Active reports are kept in a map by vehicleId. Old reports
/// (> 15 minutes) are pruned on each new report.
///
/// Fleet data flow is gated by user consent.
library;

import 'package:equatable/equatable.dart';
import 'package:fleet_hazard/fleet_hazard.dart';

/// Fleet monitoring status.
enum FleetStatus {
  /// Not listening for fleet reports.
  idle,

  /// Actively receiving fleet reports.
  listening,

  /// Provider error.
  error,
}

class FleetState extends Equatable {
  final FleetStatus status;

  /// Most recent report per vehicle, keyed by vehicleId.
  final Map<String, FleetReport> activeReports;
  final String? errorMessage;

  const FleetState({
    required this.status,
    this.activeReports = const {},
    this.errorMessage,
  });

  const FleetState.idle()
      : status = FleetStatus.idle,
        activeReports = const {},
        errorMessage = null;

  // ---------------------------------------------------------------------------
  // Convenience getters
  // ---------------------------------------------------------------------------

  /// Whether we're actively listening for fleet reports.
  bool get isListening => status == FleetStatus.listening;

  /// All active reports as a list.
  List<FleetReport> get reports => activeReports.values.toList();

  /// Reports that indicate a road hazard (snowy or icy).
  List<FleetReport> get hazardReports =>
      reports.where((r) => r.isHazard).toList();

  /// Whether any active report indicates a hazard.
  bool get hasHazards => reports.any((r) => r.isHazard);

  /// Number of active vehicles reporting.
  int get vehicleCount => activeReports.length;

  FleetState copyWith({
    FleetStatus? status,
    Map<String, FleetReport>? activeReports,
    String? errorMessage,
  }) {
    return FleetState(
      status: status ?? this.status,
      activeReports: activeReports ?? this.activeReports,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, activeReports, errorMessage];

  @override
  String toString() =>
      'FleetState($status, ${activeReports.length} vehicles, '
      '${hazardReports.length} hazards)';
}
