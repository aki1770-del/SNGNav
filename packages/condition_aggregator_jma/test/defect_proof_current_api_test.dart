/// Frozen-feed REGRESSION + HONEST BOUNDS, against the REAL frozen documents.
///
/// This file began as the "prove it fails first" evidence, written and run
/// BEFORE any implementation, using only the API shipped in 0.3.1/0.4.0. Its
/// recorded RED state was:
///   * DEFECT 1 FAILED — the 81-day-old Niigata silence reached the integrator
///     as an empty list, the identical value a clear sky produces;
///   * DEFECT 2 FAILED — `isExpiredAt` answered "not expired" forever;
///   * DEFECT 3 FAILED — `canAssertNoAdvisory` answered "measured calm".
///
/// DEFECT 1 is now FIXED and this file guards it. DEFECT 2 is deliberately
/// NOT fixed the way it was first written — the assertion was wrong and is
/// replaced by the ruling that produced it. DEFECT 3 is fixed at the adapter
/// and remains open upstream; that is recorded as an assertion, not hidden.
///
/// Every input is a REAL JMA document fetched live 2026-08-16 (provenance in
/// frozen_feed_test.dart).
library;

import 'dart:convert';
import 'dart:io';

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_jma/condition_aggregator_jma.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

final DateTime kNow = DateTime.parse('2026-08-16T00:00:00+09:00');

String _fx(String c) =>
    File('test/fixtures/jma_warning_$c.frozen_2026-05.json').readAsStringSync();

http.Response _r(String b) => http.Response.bytes(
  utf8.encode(b),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

JmaAdvisoryProvider _provider(String code) => JmaAdvisoryProvider(
  warningJsonBaseUrl: 'https://test.fixture/jma/warning/',
  client: MockClient((_) async => _r(_fx(code))),
);

void main() {
  test('DEFECT 1 — the 81-day-old Niigata silence reaches the integrator as an '
      'EMPTY LIST, identical to a measured calm', () async {
    final p = _provider('150000');
    await p.init();
    final out = await p.fetchActiveAdvisoriesAtPoint(
      latitude: 37.893333,
      longitude: 139.018333,
    );
    expect(
      out,
      isNotEmpty,
      reason:
          'FAILS TODAY. The document was last written '
          '2026-05-26T15:45+09:00 (81 days before 2026-08-16). The package '
          'returns [] — the exact value it returns when the sky is clear.',
    );
  });

  test(
    'DEFECT 2 / RULING — the Akita 雷注意報 keeps a NULL expires (we refuse to '
    'fabricate a publisher declaration) and carries the feed\'s age instead',
    () async {
      final p = _provider('050000');
      await p.init();
      final out = await p.fetchActiveAdvisoriesAtPoint(
        latitude: 39.716667,
        longitude: 140.098333,
      );

      final thunder = out.firstWhere((a) => a.eventClass == '雷注意報');

      // THE RULING. `expires` means "the publisher declared it expires at T".
      // JMA declared nothing, so we write nothing. Deriving a value here — from
      // the headline's 「２８日夜のはじめ頃まで」 (no month, JMA-defined time
      // band) or from a fixed TTL — would put OUR inference into a field the
      // consumer reads as JMA's word. That is the fabricated-clear class, and
      // it is a worse defect than the one being fixed.
      expect(thunder.expires, isNull);
      expect(
        thunder.isExpiredAt(kNow),
        isFalse,
        reason:
            'and this is CORRECT — an advisory from this source is never '
            'self-expiring. The honest signal is the feed\'s age, not a '
            'manufactured expiry.',
      );

      // What replaces it: the dead document is now named in band, so the
      // eternal 雷注意報 can no longer arrive alone and unqualified.
      expect(
        out.map((a) => a.eventClass),
        contains(kJmaStaleFeedEventClass),
        reason:
            'served as an ACTIVE hazard 230 times over HER mother\'s '
            'prefecture with nothing marking the document dead',
      );

      // And the age is reachable through the parent primitive that already
      // existed for exactly this and had zero callers.
      expect(thunder.stalenessAt(kNow)!.inDays, greaterThanOrEqualTo(79));
    },
  );

  test('DEFECT 3 — the empty-list all-clear is closed AT THE ADAPTER; the '
      'aggregator-level assertion remains UPSTREAM-OWED', () async {
    final p = _provider('150000');
    final agg = AdvisoryAggregator(providers: <AdvisoryProvider>[p]);
    await agg.init();
    final r = await agg.fetchActiveAdvisoriesAtPoint(
      latitude: 37.893333,
      longitude: 139.018333,
    );

    // FIXED adapter-side: the integrator's `if (advisories.isEmpty)`
    // all-clear branch no longer fires on an 81-day-old document.
    expect(r.advisories, isNotEmpty);
    expect(r.advisories.single.eventClass, kJmaStaleFeedEventClass);

    // HONEST BOUND, not a pass. `canAssertNoAdvisory` still returns true
    // here: the fetch SUCCEEDED, so providerErrors is empty, and the
    // aggregator has no vocabulary for "answered, but with a dead document".
    // An integrator that filters the minor-severity notice out and then asks
    // canAssertNoAdvisory still gets a measured-calm answer on an 81-day-old
    // document. Closing that needs a change in `condition_aggregator`, which
    // NDI does not own (NDI bylaws §1(c) — upstream proposal, routed).
    expect(
      r.canAssertNoAdvisory,
      isTrue,
      reason:
          'UPSTREAM-OWED, recorded rather than hidden. '
          'condition_aggregator/lib/src/advisory_aggregator.dart:110 says '
          '"never tell her it is clear" — and on a frozen feed it still does.',
    );
  });

  test('CONTEXT — the JMA headline our adapter copies verbatim CONTAINS the '
      'window, so "the windowless feed declares no explicit expiry" is only '
      'half true', () {
    final body = _fx('050000');
    final decoded = json.decode(body) as Map<String, dynamic>;
    final headline = decoded['headlineText'] as String;
    expect(headline, contains('２８日夜のはじめ頃まで'));
    final records = parseJmaWarningJson(body, prefectureCode: '050000');
    final a = mapJmaWarningToAdvisory(records.first);
    expect(a.headline, equals(headline));
    expect(a.expires, isNull);
  });
}
