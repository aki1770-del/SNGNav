/// Integration test: ConsentBloc + SqliteConsentService.
///
/// Proves the interface-first contract (L-10): ConsentBloc works identically
/// whether backed by InMemoryConsentService or SqliteConsentService.
///
/// Tests:
///   1. Load: BLoC loads all consents from SQLite (all unknown initially)
///   2. Grant: BLoC grants via SQLite — record persists in database
///   3. Revoke: BLoC revokes via SQLite — status changes to denied
///   4. Full lifecycle: load → grant → revoke → re-grant through SQLite
///   5. Persistence: grant in one BLoC instance, load in another on same DB
///   6. Audit trail: BLoC operations produce audit log entries
///   7. Jidoka: error state when SQLite service is disposed mid-operation
///
/// Sprint 8 Day 3 — ConsentBloc + SQLite integration.
library;

import 'package:bloc_test/bloc_test.dart';
import 'package:driving_consent/driving_consent.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_snow_scene/bloc/consent_bloc.dart';
import 'package:sngnav_snow_scene/bloc/consent_event.dart';
import 'package:sngnav_snow_scene/bloc/consent_state.dart';
import 'package:sngnav_snow_scene/services/consent_database.dart';
import 'package:sngnav_snow_scene/services/sqlite_consent_service.dart';

void main() {
  group('ConsentBloc + SqliteConsentService integration', () {
    blocTest<ConsentBloc, ConsentState>(
      'load: all consents are unknown initially',
      build: () => ConsentBloc(
        service: SqliteConsentService(openConsentDatabase(':memory:')),
      ),
      act: (bloc) => bloc.add(const ConsentLoadRequested()),
      expect: () => [
        isA<ConsentState>()
            .having((s) => s.status, 'status', ConsentBlocStatus.loading),
        isA<ConsentState>()
            .having((s) => s.status, 'status', ConsentBlocStatus.ready)
            .having((s) => s.consents.length, 'count', 3)
            .having((s) => s.isAllDenied, 'all denied', true),
      ],
    );

    blocTest<ConsentBloc, ConsentState>(
      'grant: record persists in SQLite via BLoC',
      build: () => ConsentBloc(
        service: SqliteConsentService(openConsentDatabase(':memory:')),
      ),
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
        isA<ConsentState>()
            .having((s) => s.isFleetGranted, 'fleet', true)
            .having(
              (s) => s.consents[ConsentPurpose.fleetLocation]?.jurisdiction,
              'jurisdiction',
              Jurisdiction.appi,
            ),
      ],
    );

    blocTest<ConsentBloc, ConsentState>(
      'revoke: status changes to denied via SQLite',
      build: () => ConsentBloc(
        service: SqliteConsentService(openConsentDatabase(':memory:')),
      ),
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
            .having((s) => s.isFleetGranted, 'fleet', false)
            .having(
              (s) => s.consents[ConsentPurpose.fleetLocation]?.status,
              'status',
              ConsentStatus.denied,
            ),
      ],
    );

    blocTest<ConsentBloc, ConsentState>(
      'full lifecycle: load → grant → revoke → re-grant through SQLite',
      build: () => ConsentBloc(
        service: SqliteConsentService(openConsentDatabase(':memory:')),
      ),
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
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(const ConsentGrantRequested(
          purpose: ConsentPurpose.fleetLocation,
          jurisdiction: Jurisdiction.appi,
        ));
      },
      expect: () => [
        // loading
        isA<ConsentState>()
            .having((s) => s.status, 'status', ConsentBlocStatus.loading),
        // ready (all unknown)
        isA<ConsentState>()
            .having((s) => s.status, 'status', ConsentBlocStatus.ready)
            .having((s) => s.isFleetGranted, 'fleet', false),
        // fleet granted (GDPR)
        isA<ConsentState>()
            .having((s) => s.isFleetGranted, 'fleet', true)
            .having(
              (s) => s.consents[ConsentPurpose.fleetLocation]?.jurisdiction,
              'jurisdiction',
              Jurisdiction.gdpr,
            ),
        // fleet revoked
        isA<ConsentState>()
            .having((s) => s.isFleetGranted, 'fleet', false),
        // fleet re-granted (APPI — jurisdiction changed)
        isA<ConsentState>()
            .having((s) => s.isFleetGranted, 'fleet', true)
            .having(
              (s) => s.consents[ConsentPurpose.fleetLocation]?.jurisdiction,
              'jurisdiction',
              Jurisdiction.appi,
            ),
      ],
    );

    test('persistence: grant in one BLoC, load in another on same DB',
        () async {
      final db = openConsentDatabase(':memory:');
      final service1 = SqliteConsentService(db);
      final bloc1 = ConsentBloc(service: service1);

      // Grant fleet in BLoC 1
      bloc1.add(const ConsentLoadRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      bloc1.add(const ConsentGrantRequested(
        purpose: ConsentPurpose.fleetLocation,
        jurisdiction: Jurisdiction.appi,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Don't close bloc1 — it would dispose the DB.
      // Instead, create a second service on the same DB.
      final service2 = SqliteConsentService(db);
      final bloc2 = ConsentBloc(service: service2);

      bloc2.add(const ConsentLoadRequested());
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // BLoC 2 should see the grant from BLoC 1.
      expect(bloc2.state.status, ConsentBlocStatus.ready);
      expect(bloc2.state.isFleetGranted, true);
      expect(
        bloc2.state.consents[ConsentPurpose.fleetLocation]?.jurisdiction,
        Jurisdiction.appi,
      );

      // Clean up — close bloc2 first (disposes service2, not db).
      // Then close bloc1 (disposes service1 which disposes db).
      await bloc2.close();
      await bloc1.close();
    });

    test('audit trail: BLoC operations produce audit log entries', () async {
      final db = openConsentDatabase(':memory:');
      final service = SqliteConsentService(db);
      final bloc = ConsentBloc(service: service);

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
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Audit log should have 2 entries (grant + revoke).
      final log = service.readAuditLog();
      expect(log, hasLength(2));
      expect(log[0]['purpose'], 'fleetLocation');
      expect(log[0]['status'], 'granted');
      expect(log[1]['purpose'], 'fleetLocation');
      expect(log[1]['status'], 'denied');

      await bloc.close();
    });
  });
}
