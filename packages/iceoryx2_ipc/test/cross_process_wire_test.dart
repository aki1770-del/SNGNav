// SPDX-FileCopyrightText: 2026 Akihiko Komada <aki1770@gmail.com>
// SPDX-License-Identifier: Apache-2.0

// THE ONE TEST THAT PROVES THE WIRE.
//
// Everything in road_friction_bridge_test.dart runs against a fake and would
// stay green if iceoryx2 were uninstalled, the .so deleted and the publisher
// never written. This file exists so that "the tests pass" cannot mean that.
//
// It starts the real publisher in a real second process, opens the real
// subscriber, and asserts that bytes written by the C process arrive in this
// Dart process and classify correctly.
//
// IT FAILS, LOUDLY, WHEN IT CANNOT RUN. It does not skip. A skipped transport
// test and a passing transport test are indistinguishable in a CI summary, and
// this repository has already shipped native tests that were quietly not run.
// If the shared object or the publisher is absent, the result is UNVERIFIED —
// which is a failure, because the wire is then unproven.

import 'dart:io';

import 'package:iceoryx2_ipc/iceoryx2_ipc.dart';
import 'package:kuksa_dart_sdk/kuksa_dart_sdk.dart';
import 'package:test/test.dart';

Never _unverified(String what, String how) {
  fail(
    'UNVERIFIED — the cross-process wire was NOT exercised: $what\n'
    '$how\n'
    'This is NOT a pass. No byte has been shown to cross a process boundary.',
  );
}

/// The distinct phases of the publisher's 4-sample cycle present in [samples].
Set<int> phasesSeenOf(List<ClassifiedRoadFriction> samples) =>
    samples.map((s) => s.sequence % 4).toSet();

void main() {
  test(
    'a sample written by the C publisher arrives and classifies in Dart',
    () async {
      final pkg = Directory.current.path;

      final publisher = File('$pkg/native/road_friction_publisher');
      if (!publisher.existsSync()) {
        _unverified(
          'the publisher binary is not built',
          'expected ${publisher.path} — run ./tool/build_iceoryx2.sh '
              'then make -C native',
        );
      }

      // The subscriber dlopen()s this. Absent, the transport cannot exist.
      //
      // The path is read from native/.iceoryx2.env — the file tool/build_iceoryx2.sh
      // writes and the Makefile links against — rather than searched for. That is
      // deliberate: locating the library independently is how a Dart subscriber
      // ends up dlopen'ing a DIFFERENT build of iceoryx2 than the publisher was
      // linked against. iceoryx2 exports no version symbol (measured: zero of 660
      // `iox2_*` symbols match version/abi/revision/semver), so a mismatched pair
      // cannot be detected at open. Reading one file makes them the same build by
      // construction instead of by coincidence.
      final env = File('$pkg/native/.iceoryx2.env');
      if (!env.existsSync()) {
        _unverified(
          'native/.iceoryx2.env is missing',
          'run ./tool/build_iceoryx2.sh (the Makefile writes this file)',
        );
      }
      final libLine = env
          .readAsLinesSync()
          .where((l) => l.startsWith('ICEORYX2_LIB='))
          .map((l) => l.substring('ICEORYX2_LIB='.length).trim())
          .where((p) => p.isNotEmpty)
          .firstOrNull;
      if (libLine == null) {
        _unverified(
          'ICEORYX2_LIB is not recorded in native/.iceoryx2.env',
          'contents:\n${env.readAsStringSync()}',
        );
      }
      final soPath = libLine;
      if (!File(soPath).existsSync()) {
        _unverified(
          'libiceoryx2_ffi_c.so is recorded but not on disk',
          '.iceoryx2.env points at $soPath',
        );
      }

      final proc = await Process.start(publisher.path, const []);
      final publisherLog = StringBuffer();
      proc.stdout.listen((d) => publisherLog.write(String.fromCharCodes(d)));
      proc.stderr.listen((d) => publisherLog.write(String.fromCharCodes(d)));

      RoadFrictionSource? source;
      final received = <ClassifiedRoadFriction>[];
      try {
        // The publisher must create the service before the subscriber opens it.
        await Future<void>.delayed(const Duration(milliseconds: 500));

        try {
          source = Iox2RoadFrictionSource.open(libraryPath: soPath);
        } on Object catch (e) {
          _unverified('the subscriber could not open', '$e\n$publisherLog');
        }

        final bridge = RoadFrictionBridge(source);
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        // Collect until every phase of the publisher's 4-sample cycle has been
        // seen at least once. A fixed count is not enough: the subscriber joins
        // at an arbitrary point in the cycle, so "the first four" is not "one of
        // each".
        final phasesSeen = <int>{};
        while (phasesSeen.length < 4 && DateTime.now().isBefore(deadline)) {
          final s = bridge.tryNext();
          if (s != null) {
            received.add(s);
            phasesSeen.add(s.sequence % 4);
          } else {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        }
      } finally {
        source?.dispose();
        proc.kill();
        await proc.exitCode;
      }

      printOnFailure('publisher output:\n$publisherLog');

      // Zero samples is the failure this test exists to catch: the subscriber
      // opened, nothing arrived, and without this assertion the run is silent.
      expect(
        received,
        isNotEmpty,
        reason:
            'UNVERIFIED — the subscriber opened but received NOTHING across the '
            'process boundary.\npublisher output:\n$publisherLog',
      );

      for (final s in received) {
        stdout.writeln(
          'seq=${s.sequence} '
          'friction=${s.reading.percent ?? "not measured"} '
          'grip=${s.grip.name}',
        );
      }

      // Every phase of the publisher's cycle was observed.
      expect(
        phasesSeenOf(received),
        {0, 1, 2, 3},
        reason:
            'did not observe all four phases of the scripted series within '
            'the deadline; got ${received.map((s) => s.sequence).toList()}',
      );

      // THE ASSERTION IS PER-SAMPLE, KEYED ON THE SAMPLE'S OWN SEQUENCE — not on
      // arrival position.
      //
      // An earlier version of this test asserted received[0..3] against the
      // series in order, and it failed against a sequence the publisher had
      // never printed. The cause was not a transport defect: the iceoryx2
      // service name is a fixed machine-global string
      // (`SNGNAV_ROAD_FRICTION_SERVICE`), so any other publisher running on the
      // same host — a second developer, a parallel CI job — publishes into the
      // SAME service and interleaves with this one. A subscriber also joins at
      // an arbitrary point in the cycle.
      //
      // Asserting arrival order therefore tested machine-wide exclusivity, which
      // this test does not have and cannot claim. The publisher's real contract
      // is `sequence % 4`, and it holds for every sample from every instance of
      // this publisher. That is both interleaving-proof and strictly stronger:
      // it checks EVERY sample received, not the first four.
      for (final s in received) {
        final phase = s.sequence % 4;
        switch (phase) {
          case 0:
            expect(s.grip, RoadGrip.grip, reason: 'seq ${s.sequence}: 80%');
            expect(s.reading.percent, 80);
          case 1:
            expect(s.grip, RoadGrip.reduced, reason: 'seq ${s.sequence}: 50%');
            expect(s.reading.percent, 50);
          case 2:
            expect(s.grip, RoadGrip.icy, reason: 'seq ${s.sequence}: 18%');
            expect(s.reading.percent, 18);
          case 3:
            // The one that matters most: quality 0 crossed the wire and did NOT
            // become a number. If the layout were wrong, this is where a garbage
            // double would arrive wearing a grip verdict.
            expect(s.grip, RoadGrip.unknown, reason: 'seq ${s.sequence}');
            expect(s.reading.percent, isNull);

            // AND the quality flag is what produced that, not luck.
            //
            // The publisher sends -999.0 as its not-measured sentinel. That is
            // outside VSS's 0..100, so a receiver that ignored `quality` and
            // passed the payload straight through would ALSO land on
            // RoadGrip.unknown — and the two assertions above would pass on a
            // broken mapping. Honouring `quality` gives classify(null), which is
            // not a contract violation; leaking the sentinel gives
            // classify(-999.0), which is. This is the only assertion that tells
            // the two apart.
            expect(
              s.reading.isContractViolation,
              isFalse,
              reason:
                  'seq ${s.sequence}: the -999.0 sentinel leaked through '
                  'instead of being suppressed by quality == 0 — absence is '
                  'riding the measurement scale',
            );
            expect(
              s.reading.rawValue,
              isNull,
              reason: 'the sentinel must not survive into the reading',
            );
        }
      }

      // Sequence numbers are publisher-assigned and must arrive intact and in
      // order. Asserted as a MONOTONIC property, not against literal [0,1,2,3]:
      // the subscriber joins mid-stream, so the first sequence it sees is
      // whatever the publisher had reached.
      //
      // A gap is NOT asserted away. iceoryx2 does not block a publisher for a
      // slow subscriber, so a gap is a real dropped sample and real information;
      // what would be a defect is going backwards, which means a stale sample
      // was delivered as current.
      final seqs = received.map((s) => s.sequence).toList();
      for (var i = 1; i < seqs.length; i++) {
        expect(
          seqs[i],
          greaterThan(seqs[i - 1]),
          reason:
              'sequence went backwards: $seqs — a stale sample was delivered '
              'as a current one',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
