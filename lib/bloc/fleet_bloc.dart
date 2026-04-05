/// FleetBloc — fleet telemetry reception and hazard aggregation.
///
/// Consumes a [FleetProvider] and emits [FleetState] with aggregated
/// fleet reports. The BLoC emits unconditionally — consent gating
/// happens at the widget layer via [ConsentGate] (widget-mediated
/// coupling).
///
/// Active reports are pruned when older than `_reportMaxAge` (15 minutes).
///
/// 7th BLoC in the Snow Scene. Same stream-subscription pattern as
/// WeatherBloc and LocationBloc.
///
/// Consent gating and inter-BLoC communication use widget-mediated coupling.
library;

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:fleet_hazard/fleet_hazard.dart';
import 'fleet_event.dart';
import 'fleet_state.dart';

class FleetBloc extends Bloc<FleetEvent, FleetState> {
  final FleetProvider _provider;
  static const _reportMaxAge = Duration(minutes: 15);

  StreamSubscription<dynamic>? _reportSub;

  FleetBloc({
    required FleetProvider provider,
  })  : _provider = provider,
        super(const FleetState.idle()) {
    on<FleetListenStarted>(_onStart);
    on<FleetListenStopped>(_onStop);
    on<FleetReportReceived>(_onReportReceived);
    on<FleetErrorOccurred>(_onError);
  }

  Future<void> _onStart(
    FleetListenStarted event,
    Emitter<FleetState> emit,
  ) async {
    if (state.isListening) return;

    // Cancel any previous subscription before starting a new one
    // (guards against retry after error state without an intervening stop).
    await _reportSub?.cancel();
    _reportSub = null;

    emit(state.copyWith(status: FleetStatus.listening));

    try {
      await _provider.startListening();
      _reportSub = _provider.reports.listen(
        (report) => add(FleetReportReceived(report)),
        onError: (Object e) => add(FleetErrorOccurred(e.toString())),
      );
    } catch (e) {
      emit(FleetState(
        status: FleetStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> _onStop(
    FleetListenStopped event,
    Emitter<FleetState> emit,
  ) async {
    await _reportSub?.cancel();
    _reportSub = null;

    try {
      await _provider.stopListening();
    } catch (_) {}

    emit(const FleetState.idle());
  }

  void _onReportReceived(
    FleetReportReceived event,
    Emitter<FleetState> emit,
  ) {
    // Upsert: latest report per vehicle, then prune stale.
    final updated = Map<String, FleetReport>.from(state.activeReports);
    updated[event.report.vehicleId] = event.report;

    // Prune reports older than _reportMaxAge.
    final now = DateTime.now();
    updated.removeWhere((_, report) =>
        now.difference(report.timestamp) > _reportMaxAge);

    emit(state.copyWith(
      status: FleetStatus.listening,
      activeReports: updated,
    ));
  }

  void _onError(
    FleetErrorOccurred event,
    Emitter<FleetState> emit,
  ) {
    // Preserve activeReports so hasHazards stays correct after error.
    emit(state.copyWith(
      status: FleetStatus.error,
      errorMessage: event.message,
    ));
  }

  @override
  Future<void> close() async {
    await _reportSub?.cancel();
    _provider.dispose();
    return super.close();
  }
}
