// SPDX-FileCopyrightText: 2026 Akihiko Komada <aki1770@gmail.com>
// SPDX-License-Identifier: Apache-2.0

// Bridge behaviour, on a fake source. These tests prove the CLASSIFICATION
// path only. They say nothing about whether a byte ever crossed a process
// boundary — that is cross_process_wire_test.dart's job, and it is deliberately
// a separate file so that a green run here can never be mistaken for a working
// transport.

import 'package:iceoryx2_ipc/iceoryx2_ipc.dart';
import 'package:kuksa_dart_sdk/kuksa_dart_sdk.dart';
import 'package:test/test.dart';

/// A source that replays a scripted list of samples, then reports empty.
final class FakeRoadFrictionSource implements RoadFrictionSource {
  FakeRoadFrictionSource(this._scripted);

  final List<RoadFrictionSample> _scripted;
  int _cursor = 0;
  bool disposed = false;

  @override
  RoadFrictionSample? tryReceive() =>
      _cursor < _scripted.length ? _scripted[_cursor++] : null;

  @override
  void dispose() => disposed = true;
}

RoadFrictionSample _sample(double? percent, {int sequence = 0}) =>
    RoadFrictionSample(
      frictionPercent: percent,
      measuredAtUnixNs: 1757000000000000000 + sequence,
      sequence: sequence,
    );

void main() {
  group('the scripted series the publisher sends', () {
    // 80 -> 50 -> 18 -> quality 0, exactly as native/road_friction_publisher
    // emits it. If the publisher's script changes, this test is the place the
    // change has to be argued.
    test('classifies dry -> wet -> icy -> unknown', () {
      final source = FakeRoadFrictionSource([
        _sample(80, sequence: 0),
        _sample(50, sequence: 1),
        _sample(18, sequence: 2),
        _sample(null, sequence: 3),
      ]);
      final bridge = RoadFrictionBridge(source);

      final dry = bridge.tryNext()!;
      expect(dry.grip, RoadGrip.grip, reason: '80% is a dry road');
      expect(dry.reading.percent, 80);
      expect(dry.sequence, 0);

      final wet = bridge.tryNext()!;
      expect(wet.grip, RoadGrip.reduced, reason: '50% is reduced grip');
      expect(wet.reading.percent, 50);

      final icy = bridge.tryNext()!;
      expect(icy.grip, RoadGrip.icy, reason: '18% is ice');
      expect(icy.reading.percent, 18);
      expect(icy.reading.isIcy, isTrue);

      final unknown = bridge.tryNext()!;
      expect(unknown.grip, RoadGrip.unknown, reason: 'quality 0 is not measured');
      expect(unknown.reading.percent, isNull);
      expect(unknown.sequence, 3);
    });

    test('reports empty, not unknown, once the script is exhausted', () {
      final bridge = RoadFrictionBridge(FakeRoadFrictionSource([]));
      // "nothing arrived" and "a sample said the road was not measured" are
      // different facts. Collapsing them would let a dead transport read as a
      // live one that keeps reporting unknown.
      expect(bridge.tryNext(), isNull);
    });
  });

  group('absence never becomes a grip verdict', () {
    test('quality == 0 yields unknown and nothing else', () {
      // The wire says quality 0; the source maps that to a null percent. There
      // is no sequence number, timestamp or ordering that may turn it into a
      // claim about the road.
      for (var seq = 0; seq < 200; seq++) {
        final s = RoadFrictionBridge.classifySample(_sample(null, sequence: seq));
        expect(
          s.grip,
          RoadGrip.unknown,
          reason: 'seq $seq: a not-measured sample produced ${s.grip}',
        );
        expect(s.reading.percent, isNull);
        expect(s.reading.isKnown, isFalse);
        expect(s.isKnown, isFalse);
      }
    });

    test('an unknown reading answers neither icy nor not-icy', () {
      final s = RoadFrictionBridge.classifySample(_sample(null));
      // Both false is the point. Absence of a reading is not a claim in either
      // direction, and a UI that asks "is it icy" must get "I do not know".
      expect(s.reading.isIcy, isFalse);
      expect(s.reading.isNotIcy, isFalse);
    });

    test('requirePercent throws rather than fabricating a default', () {
      final s = RoadFrictionBridge.classifySample(_sample(null));
      expect(s.reading.requirePercent, throwsStateError);
    });

    test('honoured absence is distinguishable from a leaked sentinel', () {
      // The publisher's not-measured sentinel is -999.0, which is outside VSS's
      // 0..100. So a source that IGNORED the quality byte and passed the
      // payload straight through would still produce RoadGrip.unknown — and a
      // test asserting only the grip would pass on a broken mapping.
      //
      // isContractViolation separates them, and that is the only thing that
      // does. Asserted here so the cross-process test's use of it is anchored
      // in the fake as well: honoured absence is clean, a leaked sentinel is a
      // producer-contract violation.
      final honoured = RoadFrictionBridge.classifySample(_sample(null));
      expect(honoured.grip, RoadGrip.unknown);
      expect(honoured.reading.isContractViolation, isFalse);
      expect(honoured.reading.rawValue, isNull);

      final leaked = RoadFrictionBridge.classifySample(_sample(-999));
      expect(leaked.grip, RoadGrip.unknown, reason: 'same grip — that is the trap');
      expect(leaked.reading.isContractViolation, isTrue);
      expect(leaked.reading.rawValue, -999);
    });
  });

  group('a producer that violates the VSS contract is not trusted', () {
    test('out-of-range, NaN and infinite all become unknown', () {
      for (final bad in <double>[-0.1, 100.1, 1000, double.nan,
          double.infinity, double.negativeInfinity]) {
        final s = RoadFrictionBridge.classifySample(_sample(bad));
        expect(s.grip, RoadGrip.unknown, reason: '$bad must not classify');
        expect(s.reading.isContractViolation, isTrue, reason: '$bad');
        expect(s.reading.percent, isNull,
            reason: '$bad must not be clamped into range');
      }
    });

    test('a 0.0-1.0 fraction reader would misread these; we do not', () {
      // The scale trap, asserted rather than commented. On the percent scale
      // 0.5 is a near-frictionless surface, not a half-grip one.
      expect(RoadFrictionBridge.classifySample(_sample(0.5)).grip, RoadGrip.icy);
      expect(RoadFrictionBridge.classifySample(_sample(1)).grip, RoadGrip.icy);
    });
  });

  group('threshold boundaries', () {
    test('are closed at the bottom of each band', () {
      expect(RoadFrictionBridge.classifySample(_sample(0)).grip, RoadGrip.icy);
      expect(RoadFrictionBridge.classifySample(_sample(29.9)).grip, RoadGrip.icy);
      expect(
          RoadFrictionBridge.classifySample(_sample(30)).grip, RoadGrip.reduced);
      expect(RoadFrictionBridge.classifySample(_sample(59.9)).grip,
          RoadGrip.reduced);
      expect(RoadFrictionBridge.classifySample(_sample(60)).grip, RoadGrip.grip);
      expect(RoadFrictionBridge.classifySample(_sample(100)).grip, RoadGrip.grip);
    });

    test('match the published kuksa_dart_sdk, not a copy kept here', () {
      // If the SDK ever moves a threshold, this package must move with it
      // rather than silently disagree with the KUKSA path.
      expect(RoadFriction.icyBelowPercent, 30);
      expect(RoadFriction.reducedBelowPercent, 60);
      expect(RoadFriction.minPercent, 0);
      expect(RoadFriction.maxPercent, 100);
    });
  });

  group('wire metadata survives the bridge', () {
    test('sequence and timestamp are carried through unmodified', () {
      final s = RoadFrictionBridge.classifySample(
        RoadFrictionSample(
          frictionPercent: 42,
          measuredAtUnixNs: 1757012345678901234,
          sequence: 99,
        ),
      );
      expect(s.sequence, 99);
      expect(s.measuredAtUnixNs, 1757012345678901234);
    });

    test('a sequence gap stays visible to the consumer', () {
      // iceoryx2 does not block a publisher for a slow subscriber, so a gap is
      // real information about dropped samples. The bridge must not renumber.
      final bridge = RoadFrictionBridge(FakeRoadFrictionSource([
        _sample(80, sequence: 7),
        _sample(50, sequence: 11),
      ]));
      expect(bridge.tryNext()!.sequence, 7);
      expect(bridge.tryNext()!.sequence, 11);
    });
  });

  test('dispose reaches the underlying source', () {
    final source = FakeRoadFrictionSource([]);
    RoadFrictionBridge(source).dispose();
    expect(source.disposed, isTrue);
  });

  test('watch emits the scripted series in order', () async {
    final bridge = RoadFrictionBridge(FakeRoadFrictionSource([
      _sample(80, sequence: 0),
      _sample(50, sequence: 1),
      _sample(18, sequence: 2),
      _sample(null, sequence: 3),
    ]));
    final grips = await bridge
        .watch(pollInterval: const Duration(milliseconds: 1))
        .take(4)
        .map((s) => s.grip)
        .toList();
    expect(grips,
        [RoadGrip.grip, RoadGrip.reduced, RoadGrip.icy, RoadGrip.unknown]);
  });
}
