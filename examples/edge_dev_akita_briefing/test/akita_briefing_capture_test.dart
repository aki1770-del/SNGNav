/// Pixel-capture harness for the edge developer's OWN Akita briefing widget.
///
/// An observable deliverable is verified by rendering it and looking at the
/// actual output — passing widget tests alone are not "seen". This harness
/// loads a real system TTF in place of the test-default Ahem block font so the
/// captured PNG shows actual legible text, renders [AkitaBriefingView] with the
/// briefing assembled from ONLY the two published packages, and writes a real
/// PNG to `_capture/akita_briefing.png` for a human to eyeball.
///
/// Fully deterministic and offline: it uses the constructed whiteout
/// observation, never the live AMeDAS fetch.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:edge_dev_akita_briefing/akita_briefing_view.dart';
import 'package:edge_dev_akita_briefing/akita_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';

const _ttf = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf';

Future<void> _loadRealFont() async {
  final bytes = File(_ttf).readAsBytesSync();
  final loader = FontLoader('Roboto')
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

void main() {
  testWidgets('capture: akita_briefing (whiteout, edge-dev UI)',
      (tester) async {
    await _loadRealFont();

    // The ENTIRE edge-developer data path — two published packages.
    final observation = akitaWhiteoutObservation();
    final briefing = assembleAkitaBriefing(observation);

    // Sanity: the measured 80 m really did light the whiteout/severe band the
    // temperature-only forecast alone could never reach.
    expect(briefing.peakHazard, HourHazard.severe);
    expect(
      briefing.chips.any((c) => c.toLowerCase().contains('whiteout')),
      isTrue,
      reason: 'severe must be named plainly: ${briefing.chips}',
    );

    final boundaryKey = GlobalKey();
    tester.view.physicalSize = const Size(620, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: 600,
                height: 700,
                child: AkitaBriefingView(
                  briefing: briefing,
                  observation: observation,
                  departure: akitaCommute().plannedDeparture,
                  isLive: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.runAsync(() async {
      final boundary = boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      final dir = Directory('_capture')..createSync();
      final file = File('${dir.path}/akita_briefing.png');
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      expect(file.lengthSync(), greaterThan(0));
      // ignore: avoid_print
      print('CAPTURE akita_briefing: ${file.absolute.path} '
          '${file.lengthSync()} bytes ${image.width}x${image.height}');
    });

    expect(tester.takeException(), isNull);
  });
}
