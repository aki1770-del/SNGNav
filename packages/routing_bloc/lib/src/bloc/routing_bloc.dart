/// RoutingBloc — 4-state machine for route lifecycle.
library;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:routing_engine/routing_engine.dart';

import 'routing_event.dart';
import 'routing_state.dart';

class RoutingBloc extends Bloc<RoutingEvent, RoutingState> {
  final RoutingEngine _engine;

  /// Incremented on every new RouteRequested so that a stale response
  /// from an earlier request is discarded when a newer one is in-flight.
  int _requestId = 0;

  RoutingBloc({required RoutingEngine engine})
      : _engine = engine,
        super(const RoutingState.idle()) {
    on<RouteRequested>(_onRouteRequested);
    on<RouteClearRequested>(_onRouteClearRequested);
    on<RoutingEngineCheckRequested>(_onEngineCheck);
  }

  Future<void> _onRouteRequested(
    RouteRequested event,
    Emitter<RoutingState> emit,
  ) async {
    final requestId = ++_requestId;

    emit(RoutingState(
      status: RoutingStatus.loading,
      destinationLabel: event.destinationLabel,
      engineAvailable: state.engineAvailable,
    ));

    try {
      final result = await _engine.calculateRoute(RouteRequest(
        origin: event.origin,
        destination: event.destination,
        costing: event.costing,
      ));

      // Discard result if a newer request superseded this one.
      if (requestId != _requestId) return;

      emit(RoutingState(
        status: RoutingStatus.routeActive,
        route: result,
        destinationLabel: event.destinationLabel,
        engineAvailable: true,
      ));
    } catch (error) {
      if (requestId != _requestId) return;
      emit(RoutingState(
        status: RoutingStatus.error,
        errorMessage: error.toString(),
        engineAvailable: state.engineAvailable,
      ));
    }
  }

  void _onRouteClearRequested(
    RouteClearRequested event,
    Emitter<RoutingState> emit,
  ) {
    emit(RoutingState.idle(engineAvailable: state.engineAvailable));
  }

  Future<void> _onEngineCheck(
    RoutingEngineCheckRequested event,
    Emitter<RoutingState> emit,
  ) async {
    final available = await _engine.isAvailable();
    emit(state.copyWith(engineAvailable: available));
  }

  @override
  Future<void> close() async {
    await _engine.dispose();
    return super.close();
  }
}