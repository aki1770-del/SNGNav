import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:navigation_safety/navigation_safety.dart';

// ---------------------------------------------------------------------------
// Mock
// ---------------------------------------------------------------------------

class MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SafetyOverlay', () {
    late MockNavigationBloc bloc;

    setUp(() {
      bloc = MockNavigationBloc();
    });

    // Rule 3: passthrough when inactive.
    testWidgets('renders IgnorePointer when no alert active', (tester) async {
      when(() => bloc.state).thenReturn(const NavigationState.idle());

      await tester.pumpWidget(_buildWidget(bloc));

      // Our IgnorePointer is the one with ignoring=true and a SizedBox.shrink
      // child. Find it by ancestor: descendant of SafetyOverlay.
      final ignorePointers = tester.widgetList<IgnorePointer>(
        find.descendant(
          of: find.byType(SafetyOverlay),
          matching: find.byType(IgnorePointer),
        ),
      );
      expect(ignorePointers, isNotEmpty);
      // No GestureDetector (modal barrier) when inactive.
      expect(
        find.descendant(
          of: find.byType(SafetyOverlay),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    });

    // Rule 4: modal when active.
    testWidgets('renders modal barrier when alert active', (tester) async {
      when(() => bloc.state).thenReturn(_withAlert());

      await tester.pumpWidget(_buildWidget(bloc));

      // ColoredBox inside our GestureDetector serves as the modal barrier.
      expect(
        find.descendant(
          of: find.byType(SafetyOverlay),
          matching: find.byType(ColoredBox),
        ),
        findsOneWidget,
      );
      // No IgnorePointer from SafetyOverlay when alert is active.
      final ignorePointers = tester.widgetList<IgnorePointer>(
        find.descendant(
          of: find.byType(SafetyOverlay),
          matching: find.byType(IgnorePointer),
        ),
      );
      expect(ignorePointers, isEmpty);
    });

    testWidgets('shows alert message for info severity', (tester) async {
      when(() => bloc.state).thenReturn(_withAlert(
        severity: AlertSeverity.info,
        message: 'Road maintenance ahead',
      ));

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.text('Road maintenance ahead'), findsOneWidget);
    });

    testWidgets('shows alert message for warning severity', (tester) async {
      when(() => bloc.state).thenReturn(_withAlert(
        severity: AlertSeverity.warning,
        message: 'Ice detected ahead',
      ));

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.text('Ice detected ahead'), findsOneWidget);
    });

    testWidgets('shows alert message for critical severity', (tester) async {
      when(() => bloc.state).thenReturn(_withAlert(
        severity: AlertSeverity.critical,
        message: 'GPS signal lost',
        dismissible: false,
      ));

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.text('GPS signal lost'), findsOneWidget);
    });

    testWidgets('shows correct icon for info severity', (tester) async {
      when(() => bloc.state).thenReturn(_withAlert(
        severity: AlertSeverity.info,
      ));

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('shows correct icon for warning severity', (tester) async {
      when(() => bloc.state).thenReturn(_withAlert(
        severity: AlertSeverity.warning,
      ));

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.byIcon(Icons.warning_amber), findsOneWidget);
    });

    testWidgets('shows correct icon for critical severity', (tester) async {
      when(() => bloc.state).thenReturn(_withAlert(
        severity: AlertSeverity.critical,
        dismissible: false,
      ));

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.byIcon(Icons.error), findsOneWidget);
    });

    testWidgets('shows dismiss button when dismissible', (tester) async {
      when(() => bloc.state).thenReturn(_withAlert(dismissible: true));

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.text('Dismiss'), findsOneWidget);
    });

    testWidgets('hides dismiss button when not dismissible (critical)',
        (tester) async {
      when(() => bloc.state).thenReturn(_withAlert(
        severity: AlertSeverity.critical,
        dismissible: false,
      ));

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.text('Dismiss'), findsNothing);
    });

    testWidgets('dismiss button dispatches SafetyAlertDismissed',
        (tester) async {
      when(() => bloc.state).thenReturn(_withAlert(dismissible: true));

      await tester.pumpWidget(_buildWidget(bloc));
      await tester.tap(find.text('Dismiss'));

      verify(() => bloc.add(const SafetyAlertDismissed())).called(1);
    });

    // Rule 1: always present in widget tree.
    testWidgets('always present in tree even when no alert', (tester) async {
      when(() => bloc.state).thenReturn(const NavigationState.idle());

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.byType(SafetyOverlay), findsOneWidget);
    });
  });
}
