/// Out-of-coverage honesty — the fourth member of the honest-absence family.
///
/// ## The defect these tests were written RED against
///
/// `fetchActiveAdvisoriesAtPoint` resolved a caller's lat/lon against
/// [kJmaPrefectureBoundingBoxes] and, when nothing contained the point,
/// returned `const <Advisory>[]`.
///
/// That is the SAME VALUE the provider returns for a prefecture it fully
/// covers, whose feed it fetched successfully, and which has no warnings in
/// force. Measured against the frozen JMA area master
/// (`test/fixtures/jma_area_offices.frozen_2026-08-24.json`, 58 offices) the
/// catalogue serves 13 — so for **45 of 58 offices**, including 長野県,
/// 富山県, 石川県, 福井県, 群馬県, 宮城県 and 福島県, the adapter answered
/// *"we do not cover this place"* with the bytes that mean *"no warnings are
/// in force"*. A driver in Nagano in a blizzard was told nothing was wrong.
///
/// The branch justified itself with a comment saying the aggregator's other
/// providers "(e.g. NWS)" cover points outside the catalog. That is false for
/// Japan: `condition_aggregator_nws` wraps NOAA/NWS (United States),
/// Digitraffic is Finland, MET Norway is Norway. No sibling provider covers
/// those 45 offices, so the empty list was the driver's whole answer.
///
/// ## Why a fourth notice rather than reusing an existing one
///
/// [kJmaIncompleteReadEventClass] means *"we could not look"* — it is injected
/// when a **containing** prefecture failed to fetch, and so presupposes the
/// point IS in coverage. [kJmaStaleFeedEventClass] means *"we looked, and what
/// answered is stale"*. Neither can say *"we never had a code for this place"*,
/// which is a different absence with a different fix: not a network retry, not
/// a path migration, but a bounding box this package does not ship.
library;

import 'dart:convert';
import 'dart:io';

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_jma/condition_aggregator_jma.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// 白馬村 (Hakuba, 長野県) — a real snow-country point in an office this
/// package does not serve. Chosen because it is exactly HER case: heavy
/// snow, mountain pass, and an office (200000 長野県) in the unserved 45.
const double kNaganoLat = 36.698;
const double kNaganoLon = 137.862;

/// 秋田市 (Akita) — inside catalogued office 050000.
const double kAkitaLat = 39.72;
const double kAkitaLon = 140.10;

final DateTime kNow = DateTime.parse('2026-08-26T12:00:00+09:00');

/// A FRESH, well-formed r8 document in which nothing is in force. This is the
/// genuine all-clear: the fetch succeeded, the document is current, and the
/// honest answer really is "no warnings".
String _freshAllClearDocument() => jsonEncode(<Map<String, dynamic>>[
  <String, dynamic>{
    'reportDatetime': kNow
        .subtract(const Duration(minutes: 12))
        .toIso8601String(),
    'infoType': '発表',
    'publishingOffice': '秋田地方気象台',
    'headlineText': '',
    'warning': <String, dynamic>{
      'class10Items': <Map<String, dynamic>>[
        <String, dynamic>{
          'areaCode': '050010',
          'kinds': <Map<String, dynamic>>[
            <String, dynamic>{'status': '発表警報・注意報はなし'},
          ],
        },
      ],
    },
  },
]);

http.Client _clientServing(String body) => MockClient(
  (req) async => http.Response.bytes(
    utf8.encode(body),
    200,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  ),
);

/// The provider must never be asked for the network on an uncovered point —
/// there is no area code to build a URL from. Any request here is a bug.
http.Client _clientThatMustNotBeCalled() => MockClient((req) async {
  fail('uncovered point must not issue an HTTP request: ${req.url}');
});

Future<List<Advisory>> _fetch({
  required http.Client client,
  required double lat,
  required double lon,
}) async {
  final provider = JmaAdvisoryProvider(client: client, now: () => kNow);
  await provider.init();
  return provider.fetchActiveAdvisoriesAtPoint(latitude: lat, longitude: lon);
}

void main() {
  group('NEGATIVE CONTROL — the two answers must not be the same bytes', () {
    // ⚑ THIS IS THE GUARD'S OWN NEGATIVE CONTROL.
    //
    // On the UNFIXED provider both sides of this comparison are
    // `const <Advisory>[]` and this test FAILS. That failure is the proof
    // that the guard bites on the real defect. A guard never shown to fail
    // on the defect it names has measured nothing.
    test(
      'an uncovered point (長野/白馬) is DISTINGUISHABLE from a covered point '
      'with no warnings in force (秋田, fresh feed, genuine all-clear)',
      () async {
        final uncovered = await _fetch(
          client: _clientThatMustNotBeCalled(),
          lat: kNaganoLat,
          lon: kNaganoLon,
        );
        final coveredAllClear = await _fetch(
          client: _clientServing(_freshAllClearDocument()),
          lat: kAkitaLat,
          lon: kAkitaLon,
        );

        expect(
          coveredAllClear,
          isEmpty,
          reason:
              'precondition: a covered prefecture with a fresh feed and '
              'nothing in force returns the empty list — the genuine '
              'all-clear. If this fails the comparison below proves nothing.',
        );

        expect(
          uncovered,
          isNot(equals(coveredAllClear)),
          reason:
              'THE DEFECT: "we do not cover this place" and "no warnings are '
              'in force" reached the driver as the same value.',
        );
        expect(
          uncovered,
          isNotEmpty,
          reason: 'an uncovered point must carry a notice, not silence.',
        );
      },
    );
  });

  group('the out-of-coverage notice', () {
    test('is a feed-health meta-advisory, keyed on the exported set', () async {
      final out = await _fetch(
        client: _clientThatMustNotBeCalled(),
        lat: kNaganoLat,
        lon: kNaganoLon,
      );
      expect(out, hasLength(1));
      final notice = out.single;
      expect(notice.eventClass, kJmaOutsideCoverageEventClass);
      expect(
        kJmaFeedHealthEventClasses,
        contains(kJmaOutsideCoverageEventClass),
        reason:
            'consumers key on the SET, not on one member — a fourth member '
            'that is not in the set is invisible to every existing consumer.',
      );
    });

    test('can never be graded as a hazard or deduped against a warning', () {
      expect(kJmaOutsideCoverageEventClass, isNot(endsWith('警報')));
      expect(kJmaOutsideCoverageEventClass, isNot(endsWith('注意報')));
      expect(
        kJmaSnowAdvisoryEventNames,
        isNot(contains(kJmaOutsideCoverageEventClass)),
      );
      final notice = buildOutsideCoverageNotice(
        latitude: kNaganoLat,
        longitude: kNaganoLon,
      );
      expect(notice.severity, AdvisorySeverity.minor);
      expect(notice.isHighImpact, isFalse);
      expect(notice.effective, isNull);
      expect(notice.expires, isNull);
    });

    test('says a DIFFERENT thing from the other three members', () {
      final texts = <String>{
        buildOutsideCoverageNotice(
          latitude: kNaganoLat,
          longitude: kNaganoLon,
        ).headline,
        buildIncompleteReadNotice(<String>['050000']).headline,
        buildStaleFeedNotice(
          prefectureCodes: <String>['050000'],
          age: const Duration(days: 9),
        ).headline,
        buildPathRetirementNotice(
          prefectureCode: '050000',
          age: const Duration(days: 88),
          sourceUrl: kJmaRetiredWarningJsonBaseUrl,
        ).headline,
      };
      expect(
        texts,
        hasLength(4),
        reason: 'four distinct absences must read as four distinct messages.',
      );
    });

    test(
      'tells the driver the silence is not safety, and names the point',
      () {
        final notice = buildOutsideCoverageNotice(
          latitude: kNaganoLat,
          longitude: kNaganoLon,
        );
        expect(notice.headline, contains('対象外'));
        expect(
          notice.headline,
          contains('安全'),
          reason:
              'the whole defect was silence reading as safety; the notice '
              'must say so in the language she reads.',
        );
        expect(notice.areaDescription, contains('36.698'));
        expect(notice.areaDescription, contains('137.862'));
      },
    );
  });

  group('COVERAGE PIN against the frozen JMA area master', () {
    late Map<String, dynamic> offices;

    setUpAll(() {
      final raw = jsonDecode(
            File(
              'test/fixtures/jma_area_offices.frozen_2026-08-24.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
      offices = raw['offices'] as Map<String, dynamic>;
    });

    test('the served set is exactly the 13 codes this package ships', () {
      expect(offices, hasLength(58));
      expect(kJmaPrefectureBoundingBoxes.keys.toSet(), <String>{
        '011000', '012000', '013000', '014030', '014100', '015000',
        '016000', '017000', '020000', '030000', '050000', '060000',
        '150000',
      });
    });

    test('every served code is a REAL office in the area master', () {
      for (final code in kJmaPrefectureBoundingBoxes.keys) {
        expect(
          offices.containsKey(code),
          isTrue,
          reason:
              '$code is not an office JMA publishes — the 0.6.0 Hokkaido '
              "defect ('010000') was exactly this shape.",
        );
      }
    });

    // The number that must never drift silently. If someone adds a bounding
    // box, this fails and they update the count deliberately — and if JMA
    // re-segments its offices, refreshing the fixture fails here too.
    test('45 of 58 offices are UNSERVED, and we say so out loud', () {
      final unserved =
          offices.keys
              .where((c) => !kJmaPrefectureBoundingBoxes.containsKey(c))
              .toSet();
      expect(
        unserved,
        hasLength(45),
        reason:
            'served ${kJmaPrefectureBoundingBoxes.length} of ${offices.length}. '
            'Change this number only together with the README coverage table.',
      );
      // The prefectures the finding named by hand — snow country we do not serve.
      for (final code in <String>[
        '040000', // 宮城県
        '070000', // 福島県
        '100000', // 群馬県
        '160000', // 富山県
        '170000', // 石川県
        '180000', // 福井県
        '200000', // 長野県
      ]) {
        expect(unserved, contains(code));
      }
    });
  });
}
