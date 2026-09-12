// SPDX-FileCopyrightText: 2026 Akihiko Komada <aki1770@gmail.com>
// SPDX-License-Identifier: Apache-2.0

// The demo. Opens the real iceoryx2 subscriber, receives what the publisher
// puts in shared memory, and prints the classification of each sample.
//
//   Terminal 1:  ./native/road_friction_publisher
//   Terminal 2:  dart run example/road_friction_glance.dart
//
// Every line is one sample that actually crossed a process boundary. A sample
// whose wire quality was 0 prints `not measured` — never a number, and never a
// grip verdict. That is the whole reason this package exists in the shape it
// does: the failure it is built against is a confident wrong answer, not a
// missing one.

import 'dart:io';

import 'package:iceoryx2_ipc/iceoryx2_ipc.dart';

/// Where to find iceoryx2.
///
/// Defaults to the path `tool/build_iceoryx2.sh` recorded in
/// `native/.iceoryx2.env` — the same library the publisher was linked against.
/// A bare `libiceoryx2_ffi_c.so` is NOT the default, because the loader will
/// not find it (this build is not installed to a system library path) and the
/// demo would fail with a confusing "cannot open shared object file" on a
/// machine where everything is in fact built. Reading the env file also means
/// the publisher and the subscriber cannot end up on two different builds of
/// iceoryx2, which nothing else here would detect: iceoryx2 exports no version
/// symbol.
String _defaultLibraryPath() {
  final env = File('native/.iceoryx2.env');
  if (env.existsSync()) {
    for (final line in env.readAsLinesSync()) {
      if (line.startsWith('ICEORYX2_LIB=')) {
        final p = line.substring('ICEORYX2_LIB='.length).trim();
        if (p.isNotEmpty) return p;
      }
    }
  }
  return 'libiceoryx2_ffi_c.so';
}

Future<void> main(List<String> args) async {
  final libraryPath = args.isNotEmpty ? args.first : _defaultLibraryPath();

  final RoadFrictionSource source;
  try {
    source = Iox2RoadFrictionSource.open(libraryPath: libraryPath);
  } on Object catch (e) {
    stderr.writeln('Could not open the iceoryx2 subscriber: $e');
    stderr.writeln(
      'Build the native half first:  ./tool/build_iceoryx2.sh\n'
      'Then start the publisher:     ./native/road_friction_publisher',
    );
    exitCode = 2;
    return;
  }

  final bridge = RoadFrictionBridge(source);
  stdout.writeln('subscribed to sngnav/road_friction — waiting for samples');
  stdout.writeln('seq  friction      grip');

  var received = 0;
  final deadline = DateTime.now().add(const Duration(seconds: 30));

  try {
    while (DateTime.now().isBefore(deadline)) {
      final s = bridge.tryNext();
      if (s == null) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        continue;
      }
      received++;
      final friction = s.reading.percent == null
          ? 'not measured'
          : '${s.reading.percent!.toStringAsFixed(1)}%';
      stdout.writeln(
        '${s.sequence.toString().padRight(4)} '
        '${friction.padRight(13)} ${s.grip.name}',
      );
    }
  } finally {
    bridge.dispose();
  }

  stdout.writeln('$received sample(s) received');
  if (received == 0) {
    stderr.writeln(
      'NOTHING RECEIVED. The subscriber opened but no publisher was sending. '
      'This is not a passing run.',
    );
    exitCode = 1;
  }
}
