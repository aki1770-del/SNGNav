// Render-and-SEE capture of the 0.9.5 condition-cleared fix (2026-07-22).
//
// WHY this exists: 0.9.5 was published from a working tree that never reached
// git, so this repository sat at 0.9.3 and the consuming app — which takes this
// package by path override — was compiling a version in which NO code path
// could clear a non-dismissible alert. Plain SafetyAlertDismissed refuses them
// by design, RerouteCompleted preserves them by design, and nothing else
// touches the alert fields. So once a non-dismissible alert fired, the overlay
// stayed modal for the process lifetime EVEN AFTER THE HAZARD HAD PASSED.
//
// A hazard warning that cannot leave the screen becomes its own hazard: it sits
// over the map the driver is trying to read, and its modal barrier swallows her
// taps.
//
// Recovering the source is not enough to claim the fix works. A "verified"
// claim on something with a visible result is not satisfied by a passing
// assertion — the output has to be rendered and looked at. This test drives the
// real widget with a real NavigationBloc (not a mock, so the recovered
// dismissal branch actually executes) and writes two PNGs:
//
//   _capture/condition_cleared_1_alert_modal.png   — non-dismissible alert up
//   _capture/condition_cleared_2_after_clear.png   — after the hazard owner
//                                                    reports the condition passed
//
// Run: flutter test test/widgets/condition_cleared_capture_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety/navigation_safety.dart';

Future<void> _capturePng(
  WidgetTester tester,
  Finder finder,
  String outPath,
) async {
  await tester.runAsync(() async {
    final element = finder.evaluate().first;
    RenderObject? ro = element.renderObject;
    while (ro != null && ro is! RenderRepaintBoundary) {
      ro = ro.parent;
    }
    final boundary = ro! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(outPath)..parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('CAPTURE $outPath ${file.lengthSync()} bytes');
  });
}

Widget _harness(NavigationBloc bloc) {
  return MaterialApp(
    home: Scaffold(
      body: RepaintBoundary(
        child: Stack(
          children: [
            // Stands in for the map she is trying to read underneath.
            Positioned.fill(
              child: Container(
                color: const Color(0xFF20303C),
                alignment: Alignment.center,
                child: const Text(
                  'MAP UNDERNEATH',
                  style: TextStyle(color: Colors.white38, fontSize: 22),
                ),
              ),
            ),
            BlocProvider<NavigationBloc>.value(
              value: bloc,
              child: const SafetyOverlay(),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a non-dismissible alert RENDERS, and the hazard owner clearing '
      'the condition actually removes it from the screen', (tester) async {
    final bloc = NavigationBloc();
    addTearDown(bloc.close);

    await tester.pumpWidget(_harness(bloc));

    // Raise the alert a driver may NOT wave away.
    bloc.add(
      const SafetyAlertReceived(
        message: '視界ゼロ — 安全な場所に停車してください',
        severity: AlertSeverity.critical,
        dismissible: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(bloc.state.hasSafetyAlert, isTrue,
        reason: 'the alert must be up before we can prove it clears');
    expect(bloc.state.alertDismissible, isFalse);
    await _capturePng(
      tester,
      find.byType(RepaintBoundary).first,
      'test/widgets/_capture/condition_cleared_1_alert_modal.png',
    );

    // The DRIVER cannot wave it away — unchanged by 0.9.5, and the reason the
    // deadlock existed. Proven here so the capture below is not mistaken for
    // ordinary dismissal.
    bloc.add(const SafetyAlertDismissed());
    await tester.pumpAndSettle();
    expect(bloc.state.hasSafetyAlert, isTrue,
        reason: 'driver dismissal must still be refused for non-dismissible');

    // The HAZARD OWNER reports the condition has passed. Before 0.9.5 this
    // parameter did not exist and the overlay could never come down.
    bloc.add(const SafetyAlertDismissed(conditionCleared: true));
    await tester.pumpAndSettle();

    expect(bloc.state.hasSafetyAlert, isFalse,
        reason: 'the recovered 0.9.5 path must clear a non-dismissible alert');
    await _capturePng(
      tester,
      find.byType(RepaintBoundary).first,
      'test/widgets/_capture/condition_cleared_2_after_clear.png',
    );
  });
}
