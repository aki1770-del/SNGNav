/// ConsentGate widget tests.
///
/// Tests:
///   1. Shows 'Fleet: ...' when loading
///   2. Shows 'Fleet: ERR' when error
///   3. Shows 'Fleet: OFF' when fleet denied/unknown
///   4. Shows 'Fleet: ON' when fleet granted
///   5. Tap OFF → dispatches ConsentGrantRequested
///   6. Tap ON → dispatches ConsentRevokeRequested
///   7. Tap ERR → dispatches ConsentLoadRequested (retry)
///   8. Shows correct icon for granted vs denied
///
/// Sprint 7 Day 9 — Snow Scene assembly.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:driving_consent/driving_consent.dart';
import 'package:mocktail/mocktail.dart';

import 'package:sngnav_snow_scene/bloc/consent_bloc.dart';
import 'package:sngnav_snow_scene/bloc/consent_event.dart';
import 'package:sngnav_snow_scene/bloc/consent_state.dart';
import 'package:sngnav_snow_scene/widgets/consent_gate.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockConsentBloc extends MockBloc<ConsentEvent, ConsentState>
    implements ConsentBloc {}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

final _fleetGranted = ConsentRecord(
  purpose: ConsentPurpose.fleetLocation,
  status: ConsentStatus.granted,
  jurisdiction: Jurisdiction.appi,
  updatedAt: DateTime(2026),
);

final _fleetDenied = ConsentRecord(
  purpose: ConsentPurpose.fleetLocation,
  status: ConsentStatus.denied,
  jurisdiction: Jurisdiction.appi,
  updatedAt: DateTime(2026),
);

ConsentState _readyState({required bool fleetGranted}) {
  final record = fleetGranted ? _fleetGranted : _fleetDenied;
  return ConsentState(
    status: ConsentBlocStatus.ready,
    consents: {ConsentPurpose.fleetLocation: record},
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildWidget(ConsentBloc bloc) {
  return MaterialApp(
    home: Scaffold(
      body: BlocProvider<ConsentBloc>.value(
        value: bloc,
        child: const ConsentGate(),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ConsentGate', () {
    late MockConsentBloc bloc;

    setUp(() {
      bloc = MockConsentBloc();
    });

    testWidgets('shows "Fleet: ..." when idle/loading', (tester) async {
      when(() => bloc.state)
          .thenReturn(const ConsentState(status: ConsentBlocStatus.loading));

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.text('Fleet: ...'), findsOneWidget);
    });

    testWidgets('shows "Fleet: ERR" when error', (tester) async {
      when(() => bloc.state).thenReturn(const ConsentState(
        status: ConsentBlocStatus.error,
        errorMessage: 'Service unavailable',
      ));

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.text('Fleet: ERR'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows "Fleet: OFF" when fleet denied', (tester) async {
      when(() => bloc.state).thenReturn(_readyState(fleetGranted: false));

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.text('Fleet: OFF'), findsOneWidget);
      expect(find.byIcon(Icons.location_disabled), findsOneWidget);
    });

    testWidgets('shows "Fleet: ON" when fleet granted', (tester) async {
      when(() => bloc.state).thenReturn(_readyState(fleetGranted: true));

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.text('Fleet: ON'), findsOneWidget);
      expect(find.byIcon(Icons.share_location), findsOneWidget);
    });

    testWidgets('tap OFF → dispatches ConsentGrantRequested', (tester) async {
      when(() => bloc.state).thenReturn(_readyState(fleetGranted: false));

      await tester.pumpWidget(_buildWidget(bloc));
      await tester.tap(find.text('Fleet: OFF'));

      verify(() => bloc.add(const ConsentGrantRequested(
            purpose: ConsentPurpose.fleetLocation,
            jurisdiction: Jurisdiction.appi,
          ))).called(1);
    });

    testWidgets('tap ON → dispatches ConsentRevokeRequested', (tester) async {
      when(() => bloc.state).thenReturn(_readyState(fleetGranted: true));

      await tester.pumpWidget(_buildWidget(bloc));
      await tester.tap(find.text('Fleet: ON'));

      verify(() => bloc.add(const ConsentRevokeRequested(
            purpose: ConsentPurpose.fleetLocation,
          ))).called(1);
    });

    testWidgets('tap ERR → dispatches ConsentLoadRequested (retry)',
        (tester) async {
      when(() => bloc.state).thenReturn(const ConsentState(
        status: ConsentBlocStatus.error,
        errorMessage: 'fail',
      ));

      await tester.pumpWidget(_buildWidget(bloc));
      await tester.tap(find.text('Fleet: ERR'));

      verify(() => bloc.add(const ConsentLoadRequested())).called(1);
    });

    testWidgets('shows "Fleet: OFF" when no consent records (Jidoka)',
        (tester) async {
      // Ready but empty map — Jidoka: unknown = denied
      when(() => bloc.state).thenReturn(const ConsentState(
        status: ConsentBlocStatus.ready,
      ));

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.text('Fleet: OFF'), findsOneWidget);
    });
  });
}
