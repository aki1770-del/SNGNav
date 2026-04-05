/// ConsentBloc — privacy consent gate state machine.
///
/// Manages the consent lifecycle for fleet data sharing:
///   idle → loading → ready (with per-purpose consent records)
///
/// Consumes a [ConsentService] — same dependency injection pattern as
/// LocationBloc (LocationProvider), RoutingBloc (RoutingEngine),
/// WeatherBloc (WeatherProvider).
///
/// Jidoka: if loading fails or service is unavailable, all purposes
/// are effectively denied. The pipeline stops itself.
///
/// Consent is explicit, revocable, and purpose-scoped.
library;

import 'package:driving_consent/driving_consent.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'consent_event.dart';
import 'consent_state.dart';

class ConsentBloc extends Bloc<ConsentEvent, ConsentState> {
  final ConsentService _service;

  ConsentBloc({required ConsentService service})
      : _service = service,
        super(const ConsentState.idle()) {
    on<ConsentLoadRequested>(_onLoad);
    on<ConsentGrantRequested>(_onGrant);
    on<ConsentRevokeRequested>(_onRevoke);
  }

  Future<void> _onLoad(
    ConsentLoadRequested event,
    Emitter<ConsentState> emit,
  ) async {
    emit(state.copyWith(status: ConsentBlocStatus.loading));

    try {
      final records = await _service.getAllConsents();
      final map = {for (final r in records) r.purpose: r};

      emit(ConsentState(
        status: ConsentBlocStatus.ready,
        consents: map,
      ));
    } catch (e) {
      // Jidoka: service error → all purposes effectively denied.
      emit(ConsentState(
        status: ConsentBlocStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> _onGrant(
    ConsentGrantRequested event,
    Emitter<ConsentState> emit,
  ) async {
    // Ignore grant requests while loading — the load result would overwrite them.
    if (state.status == ConsentBlocStatus.loading) return;
    try {
      final record = await _service.grant(
        event.purpose,
        event.jurisdiction,
      );

      final updated = Map<ConsentPurpose, ConsentRecord>.from(state.consents);
      updated[event.purpose] = record;

      emit(state.copyWith(
        status: ConsentBlocStatus.ready,
        consents: updated,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: ConsentBlocStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> _onRevoke(
    ConsentRevokeRequested event,
    Emitter<ConsentState> emit,
  ) async {
    // Ignore revoke requests while loading — the load result would overwrite them.
    if (state.status == ConsentBlocStatus.loading) return;
    try {
      final record = await _service.revoke(event.purpose);

      final updated = Map<ConsentPurpose, ConsentRecord>.from(state.consents);
      updated[event.purpose] = record;

      emit(state.copyWith(
        status: ConsentBlocStatus.ready,
        consents: updated,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: ConsentBlocStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  @override
  Future<void> close() async {
    await _service.dispose();
    return super.close();
  }
}
