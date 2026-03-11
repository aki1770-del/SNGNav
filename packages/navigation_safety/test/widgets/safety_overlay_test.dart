/// SafetyOverlay widget tests.
library;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:navigation_safety/navigation_safety.dart';

class MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

NavigationState _withAlert({
  AlertSeverity severity = AlertSeverity.warning,
  String message = 'Ice detected ahead',
  bool dismissible = true,
}) {
  return NavigationState(
    status: NavigationStatus.navigating,
    alertMessage: message,
    alertSeverity: severity,
    alertDismissible: dismissible,
  );
}

Widget _buildWidget(NavigationBloc bloc) {
  return MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: Placeholder()),
          BlocProvider<NavigationBloc>.value(
            value: bloc,
            child: const SafetyOverlay(),
          ),
        ],
      ),
    ),
  );
}

void main() {
  group('SafetyOverlay', () {
    late MockNavigationBloc bloc;

    setUp(() {
      bloc = MockNavigationBloc();
    });

    testWidgets('always present in tree even without alert', (tester) async {
      when(() => bloc.state).thenReturn(const NavigationState.idle());

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.byType(SafetyOverlay), findsOneWidget);
    });

    testWidgets('renders IgnorePointer when no alert active', (tester) async {
      when(() => bloc.state).thenReturn(const NavigationState.idle());

      await tester.pumpWidget(_buildWidget(bloc));

      expect(
        find.descendant(
          of: find.byType(SafetyOverlay),
          matching: find.byType(IgnorePointer),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(SafetyOverlay),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    });

    testWidgets('renders modal barrier when alert active', (tester) async {
      when(() => bloc.state).thenReturn(_withAlert());

      await tester.pumpWidget(_buildWidget(bloc));

      expect(
        find.descendant(
          of: find.byType(SafetyOverlay),
          matching: find.byType(ColoredBox),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(SafetyOverlay),
          matching: find.byType(GestureDetector),
        ),
        findsWidgets,
      );
    });

    testWidgets('shows info severity UI', (tester) async {
      when(() => bloc.state).thenReturn(
        _withAlert(
          severity: AlertSeverity.info,
          message: 'Road maintenance ahead',
        ),
      );

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.text('Road maintenance ahead'), findsOneWidget);
    });

    testWidgets('shows warning severity UI', (tester) async {
      when(() => bloc.state).thenReturn(
        _withAlert(
          severity: AlertSeverity.warning,
          message: 'Ice detected ahead',
        ),
      );

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.byIcon(Icons.warning_amber), findsOneWidget);
      expect(find.text('Ice detected ahead'), findsOneWidget);
    });

    testWidgets('shows critical severity UI', (tester) async {
      when(() => bloc.state).thenReturn(
        _withAlert(
          severity: AlertSeverity.critical,
          message: 'Visibility zero',
          dismissible: false,
        ),
      );

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.byIcon(Icons.error), findsOneWidget);
      expect(find.text('Visibility zero'), findsOneWidget);
      expect(find.text('Dismiss'), findsNothing);
    });

    testWidgets('shows dismiss button when dismissible', (tester) async {
      when(() => bloc.state).thenReturn(_withAlert(dismissible: true));

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.text('Dismiss'), findsOneWidget);
    });

    testWidgets('dismiss button dispatches event', (tester) async {
      when(() => bloc.state).thenReturn(_withAlert(dismissible: true));

      await tester.pumpWidget(_buildWidget(bloc));
      await tester.tap(find.text('Dismiss'));

      verify(() => bloc.add(const SafetyAlertDismissed())).called(1);
    });

    testWidgets('does not show alert message when inactive', (tester) async {
      when(() => bloc.state).thenReturn(const NavigationState.idle());

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.text('Ice detected ahead'), findsNothing);
    });

    testWidgets('renders card for active alert', (tester) async {
      when(() => bloc.state).thenReturn(_withAlert());

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.byType(Card), findsOneWidget);
    });
  });
}