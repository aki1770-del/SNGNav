import 'dart:io';

import 'package:condition_aggregator_jma/condition_aggregator_jma.dart';
import 'package:test/test.dart';

const _r8 = 'test/fixtures/jma_warning_r8_050000.frozen_2026-08-23.json';
const _legacy = 'test/fixtures/jma_warning_050000.frozen_2026-05.json';
String _read(String p) => File(p).readAsStringSync();

void main() {
  group('fixture pin', () {
    test('r8 Akita fixture is byte-exact as retrieved', () {
      expect(File(_r8).lengthSync(), equals(14117));
    });
  });

  group('the two schemas can never be silently confused', () {
    test('the LEGACY parser refuses an r8 document', () {
      expect(
        () => parseJmaFeed(_read(_r8), prefectureCode: '050000'),
        throwsA(isA<FormatException>()),
      );
    });

    test('the R8 parser refuses a legacy document', () {
      expect(
        () => parseJmaR8Feed(_read(_legacy), prefectureCode: '050000'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('freshness is the NEWEST document, never the oldest', () {
    test(
      'NEGATIVE CONTROL — the frozen Akita fixture holds a 2026-08-23T23:51 '
      'document and a 2026-07-16T06:30 one, 38 days apart, both normal. '
      'Taking the oldest reports a LIVE feed as ~38 days dead and fires a '
      'false feed-death notice over warnings that are genuinely in force.',
      () {
        final s = parseJmaR8Feed(_read(_r8), prefectureCode: '050000');
        expect(
          s.reportDateTime!.toUtc().toIso8601String(),
          equals('2026-08-23T14:51:00.000Z'),
          reason: 'must be the NEWEST document (2026-08-23T23:51+09:00)',
        );
      },
    );

    test('a live feed is not stale at a 6-hour threshold', () {
      final s = parseJmaR8Feed(_read(_r8), prefectureCode: '050000');
      final justAfter = DateTime.parse('2026-08-24T01:00:00+09:00');
      expect(s.isStaleAt(justAfter, const Duration(hours: 6)), isFalse);
    });

    test(
      'the legacy path IS stale at the same instant — the defect, proven',
      () {
        final s = parseJmaFeed(_read(_legacy), prefectureCode: '050000');
        final now = DateTime.parse('2026-08-24T01:00:00+09:00');
        expect(s.isStaleAt(now, const Duration(hours: 6)), isTrue);
        expect(s.ageAt(now)!.inDays, greaterThan(80));
      },
    );
  });

  group('the live warning is actually surfaced', () {
    test('Akita 濃霧注意報 (code 20) in force is mapped', () {
      final s = parseJmaR8Feed(_read(_r8), prefectureCode: '050000');
      expect(s.records.map((r) => r.warningCode), contains('20'));
      final fog = s.records.firstWhere((r) => r.warningCode == '20');
      expect(fog.eventName, equals('濃霧注意報'));
      expect(fog.status, equals('発表'));
      expect(fog.areaName, equals('秋田県'));
      expect(s.advisories.any((a) => a.eventClass == '濃霧注意報'), isTrue);
    });

    test('NEGATIVE CONTROL — cancelled (解除) and the explicit all-clear marker '
        'never become warnings. The fixture contains code 10/29/15/16 all at '
        '解除; if any leaks through, a cleared advisory is served as live.', () {
      final s = parseJmaR8Feed(_read(_r8), prefectureCode: '050000');
      final codes = s.records.map((r) => r.warningCode).toSet();
      expect(codes, equals({'20'}));
      for (final r in s.records) {
        expect(r.status, isNot(equals('解除')));
        expect(r.status, isNot(equals(kJmaR8StatusNoWarnings)));
      }
    });

    test('a null-code all-clear entry never becomes a record', () {
      final s = parseJmaR8Feed(_read(_r8), prefectureCode: '050000');
      expect(s.records.every((r) => r.warningCode.isNotEmpty), isTrue);
    });
  });

  group('publisher all-clear is distinguishable from an unread feed', () {
    test(
      'the Akita fixture does NOT declare a blanket all-clear (fog is on)',
      () {
        expect(jmaR8DeclaresNoWarnings(_read(_r8)), isFalse);
      },
    );
  });
}
