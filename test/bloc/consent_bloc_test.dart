/// Tests for ConsentRecord, ConsentService, ConsentEvent, ConsentState,
/// and ConsentBloc — the privacy consent gate (C-AD-11).
///
/// Coverage:
///   - ConsentRecord model: enums, Jidoka getters, equality
///   - InMemoryConsentService: grant, revoke, getAllConsents, unknown default
///   - ConsentState: convenience getters, Jidoka semantics
///   - ConsentEvent: equality
///   - ConsentBloc: load, grant, revoke, error handling, Jidoka defaults
///
/// Architecture reference: A63 v3.0 §4.8, C-AD-11.
library;

import 'package:bloc_test/bloc_test.dart';
import 'package:driving_consent/driving_consent.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_snow_scene/bloc/consent_bloc.dart';
import 'package:sngnav_snow_scene/bloc/consent_event.dart';
import 'package:sngnav_snow_scene/bloc/consent_state.dart';

// ---------------------------------------------------------------------------
// Mock that can be configured to throw
// ---------------------------------------------------------------------------

class _FailingConsentService implements ConsentService {
  bool shouldFail = false;

  final _delegate = InMemoryConsentService();

  @override
  Future<ConsentRecord> getConsent(ConsentPurpose purpose) async {
    if (shouldFail) throw Exception('Service unavailable');
    return _delegate.getConsent(purpose);
  }

  @override
  Future<List<ConsentRecord>> getAllConsents() async {
    if (shouldFail) throw Exception('Service unavailable');
    return _delegate.getAllConsents();
  }

  @override
  Future<ConsentRecord> grant(
    ConsentPurpose purpose,
    Jurisdiction jurisdiction,
  ) async {
    if (shouldFail) throw Exception('Service unavailable');
    return _delegate.grant(purpose, jurisdiction);
  }

  @override
  Future<ConsentRecord> revoke(ConsentPurpose purpose) async {
    if (shouldFail) throw Exception('Service unavailable');
    return _delegate.revoke(purpose);
  }

  @override
  Future<void> dispose() async {
    await _delegate.dispose();
  }
}

void main() {
  // -------------------------------------------------------------------------
  // ConsentRecord model
  // -------------------------------------------------------------------------

  group('ConsentRecord', () {
    test('granted record is effectively granted', () {
      final record = ConsentRecord(
        purpose: ConsentPurpose.fleetLocation,
        status: ConsentStatus.granted,
        jurisdiction: Jurisdiction.gdpr,
        updatedAt: DateTime(2026, 2, 27),
      );
      expect(record.isEffectivelyGranted, isTrue);
      expect(record.isExplicitlyDenied, isFalse);
      expect(record.isUnknown, isFalse);
    });

    test('denied record is not effectively granted', () {
      final record = ConsentRecord(
        purpose: ConsentPurpose.fleetLocation,
        status: ConsentStatus.denied,
        jurisdiction: Jurisdiction.ccpa,
        updatedAt: DateTime(2026, 2, 27),
      );
      expect(record.isEffectivelyGranted, isFalse);
      expect(record.isExplicitlyDenied, isTrue);
      expect(record.isUnknown, isFalse);
    });

    test('unknown record is not effectively granted — Jidoka', () {
      final record = ConsentRecord.unknown(
        purpose: ConsentPurpose.fleetLocation,
      );
      expect(record.isEffectivelyGranted, isFalse);
      expect(record.isExplicitlyDenied, isFalse);
      expect(record.isUnknown, isTrue);
      expect(record.status, ConsentStatus.unknown);
    });

    test('unknown defaults to GDPR jurisdiction', () {
      final record = ConsentRecord.unknown(
        purpose: ConsentPurpose.diagnostics,
      );
      expect(record.jurisdiction, Jurisdiction.gdpr);
    });

    test('unknown timestamp is epoch zero', () {
      final record = ConsentRecord.unknown(
        purpose: ConsentPurpose.weatherTelemetry,
      );
      expect(record.updatedAt, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('equality by value', () {
      final a = ConsentRecord(
        purpose: ConsentPurpose.fleetLocation,
        status: ConsentStatus.granted,
        jurisdiction: Jurisdiction.appi,
        updatedAt: DateTime(2026, 2, 27, 10, 30),
      );
      final b = ConsentRecord(
        purpose: ConsentPurpose.fleetLocation,
        status: ConsentStatus.granted,
        jurisdiction: Jurisdiction.appi,
        updatedAt: DateTime(2026, 2, 27, 10, 30),
      );
      expect(a, equals(b));
    });

    test('different status ≠ equal', () {
      final granted = ConsentRecord(
        purpose: ConsentPurpose.fleetLocation,
        status: ConsentStatus.granted,
        jurisdiction: Jurisdiction.gdpr,
        updatedAt: DateTime(2026, 2, 27),
      );
      final denied = ConsentRecord(
        purpose: ConsentPurpose.fleetLocation,
        status: ConsentStatus.denied,
        jurisdiction: Jurisdiction.gdpr,
        updatedAt: DateTime(2026, 2, 27),
      );
      expect(granted, isNot(equals(denied)));
    });

    test('toString includes purpose and status', () {
      final record = ConsentRecord(
        purpose: ConsentPurpose.fleetLocation,
        status: ConsentStatus.granted,
        jurisdiction: Jurisdiction.gdpr,
        updatedAt: DateTime(2026, 2, 27),
      );
      expect(record.toString(), contains('fleetLocation'));
      expect(record.toString(), contains('granted'));
    });

    test('all ConsentPurpose values exist', () {
      expect(ConsentPurpose.values, hasLength(3));
      expect(ConsentPurpose.values, contains(ConsentPurpose.fleetLocation));
      expect(ConsentPurpose.values, contains(ConsentPurpose.weatherTelemetry));
      expect(ConsentPurpose.values, contains(ConsentPurpose.diagnostics));
    });

    test('all Jurisdiction values exist', () {
      expect(Jurisdiction.values, hasLength(3));
      expect(Jurisdiction.values, contains(Jurisdiction.gdpr));
      expect(Jurisdiction.values, contains(Jurisdiction.ccpa));
      expect(Jurisdiction.values, contains(Jurisdiction.appi));
    });

    test('all ConsentStatus values exist', () {
      expect(ConsentStatus.values, hasLength(3));
    });
  });

  // -------------------------------------------------------------------------
  // InMemoryConsentService
  // -------------------------------------------------------------------------

  group('InMemoryConsentService', () {
    late InMemoryConsentService service;

    setUp(() {
      service = InMemoryConsentService();
    });

    tearDown(() async {
      await service.dispose();
    });

    test('getConsent returns unknown for unset purpose', () async {
      final record = await service.getConsent(ConsentPurpose.fleetLocation);
      expect(record.status, ConsentStatus.unknown);
      expect(record.purpose, ConsentPurpose.fleetLocation);
      expect(record.isEffectivelyGranted, isFalse);
    });

    test('getAllConsents returns all purposes with unknown defaults', () async {
      final records = await service.getAllConsents();
      expect(records, hasLength(ConsentPurpose.values.length));
      for (final record in records) {
        expect(record.status, ConsentStatus.unknown);
      }
    });

    test('grant sets status to granted', () async {
      final record = await service.grant(
        ConsentPurpose.fleetLocation,
        Jurisdiction.gdpr,
      );
      expect(record.status, ConsentStatus.granted);
      expect(record.purpose, ConsentPurpose.fleetLocation);
      expect(record.jurisdiction, Jurisdiction.gdpr);
      expect(record.isEffectivelyGranted, isTrue);
    });

    test('grant persists in getConsent', () async {
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.appi);
      final record = await service.getConsent(ConsentPurpose.fleetLocation);
      expect(record.status, ConsentStatus.granted);
      expect(record.jurisdiction, Jurisdiction.appi);
    });

    test('revoke sets status to denied', () async {
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.gdpr);
      final record = await service.revoke(ConsentPurpose.fleetLocation);
      expect(record.status, ConsentStatus.denied);
      expect(record.isEffectivelyGranted, isFalse);
    });

    test('revoke preserves jurisdiction from previous grant', () async {
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.appi);
      final record = await service.revoke(ConsentPurpose.fleetLocation);
      expect(record.jurisdiction, Jurisdiction.appi);
    });

    test('revoke without prior grant defaults to GDPR jurisdiction', () async {
      final record = await service.revoke(ConsentPurpose.diagnostics);
      expect(record.jurisdiction, Jurisdiction.gdpr);
    });

    test('per-purpose: granting fleet does not affect weather', () async {
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.gdpr);
      final weather =
          await service.getConsent(ConsentPurpose.weatherTelemetry);
      expect(weather.status, ConsentStatus.unknown);
    });

    test('getAllConsents reflects mixed states', () async {
      await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.gdpr);
      await service.revoke(ConsentPurpose.diagnostics);
      // weatherTelemetry left as unknown

      final records = await service.getAllConsents();
      final fleet =
          records.firstWhere((r) => r.purpose == ConsentPurpose.fleetLocation);
      final diag =
          records.firstWhere((r) => r.purpose == ConsentPurpose.diagnostics);
      final weather = records
          .firstWhere((r) => r.purpose == ConsentPurpose.weatherTelemetry);

      expect(fleet.status, ConsentStatus.granted);
      expect(diag.status, ConsentStatus.denied);
      expect(weather.status, ConsentStatus.unknown);
    });
  });

  // -------------------------------------------------------------------------
  // ConsentState
  // -------------------------------------------------------------------------

  group('ConsentState', () {
    test('idle state has empty consents', () {
      const state = ConsentState.idle();
      expect(state.status, ConsentBlocStatus.idle);
      expect(state.consents, isEmpty);
      expect(state.isFleetGranted, isFalse);
      expect(state.isAllDenied, isTrue);
    });

    test('Jidoka: getters return false when not ready', () {
      final state = ConsentState(
        status: ConsentBlocStatus.loading,
        consents: {
          ConsentPurpose.fleetLocation: ConsentRecord(
            purpose: ConsentPurpose.fleetLocation,
            status: ConsentStatus.granted,
            jurisdiction: Jurisdiction.gdpr,
            updatedAt: DateTime(2026),
          ),
        },
      );
      // Even though fleet is granted in the map, status is loading → false
      expect(state.isFleetGranted, isFalse);
    });

    test('ready state with granted fleet returns true', () {
      final state = ConsentState(
        status: ConsentBlocStatus.ready,
        consents: {
          ConsentPurpose.fleetLocation: ConsentRecord(
            purpose: ConsentPurpose.fleetLocation,
            status: ConsentStatus.granted,
            jurisdiction: Jurisdiction.gdpr,
            updatedAt: DateTime(2026),
          ),
        },
      );
      expect(state.isFleetGranted, isTrue);
      expect(state.isWeatherGranted, isFalse);
      expect(state.isAllDenied, isFalse);
    });

    test('consentFor returns record or null', () {
      final record = ConsentRecord(
        purpose: ConsentPurpose.fleetLocation,
        status: ConsentStatus.granted,
        jurisdiction: Jurisdiction.gdpr,
        updatedAt: DateTime(2026),
      );
      final state = ConsentState(
        status: ConsentBlocStatus.ready,
        consents: {ConsentPurpose.fleetLocation: record},
      );
      expect(state.consentFor(ConsentPurpose.fleetLocation), equals(record));
      expect(state.consentFor(ConsentPurpose.diagnostics), isNull);
    });

    test('toString includes granted purposes', () {
      final state = ConsentState(
        status: ConsentBlocStatus.ready,
        consents: {
          ConsentPurpose.fleetLocation: ConsentRecord(
            purpose: ConsentPurpose.fleetLocation,
            status: ConsentStatus.granted,
            jurisdiction: Jurisdiction.gdpr,
            updatedAt: DateTime(2026),
          ),
        },
      );
      expect(state.toString(), contains('fleetLocation'));
    });
  });

  // -------------------------------------------------------------------------
  // ConsentEvent
  // -------------------------------------------------------------------------

  group('ConsentEvent', () {
    test('ConsentLoadRequested equality', () {
      expect(
        const ConsentLoadRequested(),
        equals(const ConsentLoadRequested()),
      );
    });

    test('ConsentGrantRequested equality', () {
      expect(
        const ConsentGrantRequested(
          purpose: ConsentPurpose.fleetLocation,
          jurisdiction: Jurisdiction.gdpr,
        ),
        equals(const ConsentGrantRequested(
          purpose: ConsentPurpose.fleetLocation,
          jurisdiction: Jurisdiction.gdpr,
        )),
      );
    });

    test('ConsentRevokeRequested equality', () {
      expect(
        const ConsentRevokeRequested(purpose: ConsentPurpose.fleetLocation),
        equals(
            const ConsentRevokeRequested(purpose: ConsentPurpose.fleetLocation)),
      );
    });
  });

  // -------------------------------------------------------------------------
  // ConsentBloc
  // -------------------------------------------------------------------------

  group('ConsentBloc', () {
    late InMemoryConsentService service;
    late ConsentBloc bloc;

    setUp(() {
      service = InMemoryConsentService();
      bloc = ConsentBloc(service: service);
    });

    tearDown(() async {
      await bloc.close();
    });

    test('initial state is idle', () {
      expect(bloc.state.status, ConsentBlocStatus.idle);
      expect(bloc.state.consents, isEmpty);
    });

    blocTest<ConsentBloc, ConsentState>(
      'load emits loading then ready with all unknown',
      build: () => ConsentBloc(service: InMemoryConsentService()),
      act: (bloc) => bloc.add(const ConsentLoadRequested()),
      expect: () => [
        isA<ConsentState>()
            .having((s) => s.status, 'status', ConsentBlocStatus.loading),
        isA<ConsentState>()
            .having((s) => s.status, 'status', ConsentBlocStatus.ready)
            .having((s) => s.consents.length, 'consents count', 3)
            .having((s) => s.isAllDenied, 'all denied', true),
      ],
    );

    blocTest<ConsentBloc, ConsentState>(
      'grant fleet emits ready with fleet granted',
      build: () => ConsentBloc(service: InMemoryConsentService()),
      seed: () => ConsentState(
        status: ConsentBlocStatus.ready,
        consents: {
          for (final p in ConsentPurpose.values)
            p: ConsentRecord.unknown(purpose: p),
        },
      ),
      act: (bloc) => bloc.add(const ConsentGrantRequested(
        purpose: ConsentPurpose.fleetLocation,
        jurisdiction: Jurisdiction.gdpr,
      )),
      expect: () => [
        isA<ConsentState>()
            .having((s) => s.isFleetGranted, 'fleet granted', true)
            .having((s) => s.isWeatherGranted, 'weather granted', false),
      ],
    );

    blocTest<ConsentBloc, ConsentState>(
      'revoke fleet after grant emits ready with fleet denied',
      build: () {
        final svc = InMemoryConsentService();
        return ConsentBloc(service: svc);
      },
      seed: () => ConsentState(
        status: ConsentBlocStatus.ready,
        consents: {
          ConsentPurpose.fleetLocation: ConsentRecord(
            purpose: ConsentPurpose.fleetLocation,
            status: ConsentStatus.granted,
            jurisdiction: Jurisdiction.gdpr,
            updatedAt: DateTime(2026),
          ),
        },
      ),
      act: (bloc) => bloc.add(
        const ConsentRevokeRequested(purpose: ConsentPurpose.fleetLocation),
      ),
      expect: () => [
        isA<ConsentState>()
            .having((s) => s.isFleetGranted, 'fleet granted', false)
            .having(
              (s) => s.consents[ConsentPurpose.fleetLocation]?.status,
              'fleet status',
              ConsentStatus.denied,
            ),
      ],
    );

    blocTest<ConsentBloc, ConsentState>(
      'per-purpose: grant fleet and weather independently',
      build: () => ConsentBloc(service: InMemoryConsentService()),
      seed: () => ConsentState(
        status: ConsentBlocStatus.ready,
        consents: {
          for (final p in ConsentPurpose.values)
            p: ConsentRecord.unknown(purpose: p),
        },
      ),
      act: (bloc) {
        bloc.add(const ConsentGrantRequested(
          purpose: ConsentPurpose.fleetLocation,
          jurisdiction: Jurisdiction.gdpr,
        ));
        bloc.add(const ConsentGrantRequested(
          purpose: ConsentPurpose.weatherTelemetry,
          jurisdiction: Jurisdiction.appi,
        ));
      },
      expect: () => [
        // After fleet grant
        isA<ConsentState>()
            .having((s) => s.isFleetGranted, 'fleet', true)
            .having((s) => s.isWeatherGranted, 'weather', false),
        // After weather grant
        isA<ConsentState>()
            .having((s) => s.isFleetGranted, 'fleet', true)
            .having((s) => s.isWeatherGranted, 'weather', true)
            .having((s) => s.isDiagnosticsGranted, 'diag', false),
      ],
    );

    blocTest<ConsentBloc, ConsentState>(
      'Jidoka: service error on load emits error state',
      build: () {
        final failing = _FailingConsentService()..shouldFail = true;
        return ConsentBloc(service: failing);
      },
      act: (bloc) => bloc.add(const ConsentLoadRequested()),
      expect: () => [
        isA<ConsentState>()
            .having((s) => s.status, 'status', ConsentBlocStatus.loading),
        isA<ConsentState>()
            .having((s) => s.status, 'status', ConsentBlocStatus.error)
            .having((s) => s.isFleetGranted, 'fleet', false)
            .having((s) => s.errorMessage, 'error', isNotNull),
      ],
    );

    blocTest<ConsentBloc, ConsentState>(
      'Jidoka: service error on grant emits error state',
      build: () {
        final failing = _FailingConsentService()..shouldFail = true;
        return ConsentBloc(service: failing);
      },
      seed: () => ConsentState(
        status: ConsentBlocStatus.ready,
        consents: {
          for (final p in ConsentPurpose.values)
            p: ConsentRecord.unknown(purpose: p),
        },
      ),
      act: (bloc) => bloc.add(const ConsentGrantRequested(
        purpose: ConsentPurpose.fleetLocation,
        jurisdiction: Jurisdiction.gdpr,
      )),
      expect: () => [
        isA<ConsentState>()
            .having((s) => s.status, 'status', ConsentBlocStatus.error),
      ],
    );

    blocTest<ConsentBloc, ConsentState>(
      'Jidoka: service error on revoke emits error state',
      build: () {
        final failing = _FailingConsentService()..shouldFail = true;
        return ConsentBloc(service: failing);
      },
      seed: () => ConsentState(
        status: ConsentBlocStatus.ready,
        consents: {
          ConsentPurpose.fleetLocation: ConsentRecord(
            purpose: ConsentPurpose.fleetLocation,
            status: ConsentStatus.granted,
            jurisdiction: Jurisdiction.gdpr,
            updatedAt: DateTime(2026),
          ),
        },
      ),
      act: (bloc) => bloc.add(
        const ConsentRevokeRequested(purpose: ConsentPurpose.fleetLocation),
      ),
      expect: () => [
        isA<ConsentState>()
            .having((s) => s.status, 'status', ConsentBlocStatus.error),
      ],
    );

    blocTest<ConsentBloc, ConsentState>(
      '3-jurisdiction: APPI consent stored correctly',
      build: () => ConsentBloc(service: InMemoryConsentService()),
      seed: () => ConsentState(
        status: ConsentBlocStatus.ready,
        consents: {
          for (final p in ConsentPurpose.values)
            p: ConsentRecord.unknown(purpose: p),
        },
      ),
      act: (bloc) => bloc.add(const ConsentGrantRequested(
        purpose: ConsentPurpose.fleetLocation,
        jurisdiction: Jurisdiction.appi,
      )),
      expect: () => [
        isA<ConsentState>().having(
          (s) => s.consents[ConsentPurpose.fleetLocation]?.jurisdiction,
          'jurisdiction',
          Jurisdiction.appi,
        ),
      ],
    );

    blocTest<ConsentBloc, ConsentState>(
      'full lifecycle: load → grant → revoke',
      build: () => ConsentBloc(service: InMemoryConsentService()),
      act: (bloc) async {
        bloc.add(const ConsentLoadRequested());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(const ConsentGrantRequested(
          purpose: ConsentPurpose.fleetLocation,
          jurisdiction: Jurisdiction.gdpr,
        ));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(
          const ConsentRevokeRequested(purpose: ConsentPurpose.fleetLocation),
        );
      },
      expect: () => [
        // loading
        isA<ConsentState>()
            .having((s) => s.status, 'status', ConsentBlocStatus.loading),
        // ready (all unknown)
        isA<ConsentState>()
            .having((s) => s.status, 'status', ConsentBlocStatus.ready)
            .having((s) => s.isFleetGranted, 'fleet', false),
        // fleet granted
        isA<ConsentState>()
            .having((s) => s.isFleetGranted, 'fleet', true),
        // fleet revoked
        isA<ConsentState>()
            .having((s) => s.isFleetGranted, 'fleet', false)
            .having(
              (s) => s.consents[ConsentPurpose.fleetLocation]?.status,
              'status',
              ConsentStatus.denied,
            ),
      ],
    );
  });
}
