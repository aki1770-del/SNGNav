import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:test/test.dart';

/// The defect this file exists to keep dead.
///
/// A JMA outage during an Akita blizzard used to reach the integrator as an
/// EMPTY LIST — the same value it gets on a clear night. `condition_aggregator_jma`
/// threw honestly ("Incomplete border read for prefectures …"); the aggregator
/// caught it, flattened it to a string, filed it in a `providerErrors` list that
/// nothing in the tree ever read, and returned the empty list anyway.
///
/// Her screen said nothing. In a blizzard. Because the feed was down.
///
/// Every test here FAILS against 0.0.7.
class _DeadProvider implements AdvisoryProvider {
  @override
  final AdvisorySource source;
  _DeadProvider(this.source);

  @override
  Future<void> init() async {}

  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async => throw Exception('Incomplete border read for prefectures [05]');
}

/// A source that answers — with nothing in force. The one shape in which an
/// empty list is a real all-clear.
class _QuietProvider implements AdvisoryProvider {
  @override
  final AdvisorySource source;
  _QuietProvider(this.source);

  @override
  Future<void> init() async {}

  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async => const [];
}

void main() {
  group('a feed outage is not a clear night', () {
    test('every source down => UNAVAILABLE, never an empty list', () async {
      final agg = AdvisoryAggregator(
        providers: [_DeadProvider(AdvisorySource.jmaJapan)],
      );
      await agg.init();
      final r = await agg.fetchActiveAdvisoriesAtPoint(
        latitude: 39.72, // Akita
        longitude: 140.10,
      );

      // 0.0.7 returned an empty advisories list here — indistinguishable from
      // a calm night. The type now refuses to say that.
      expect(r, isA<AdvisoryLookupUnavailable>());

      // The load-bearing guarantee: you MAY NOT tell her nothing is in force.
      expect(r.canAssertNoAdvisory, isFalse);

      // And the lamp is at her hands, typed — not in a drawer as a string.
      expect(
        r.failures.single.reason,
        AdvisoryUnavailableReason.incompleteAreaCoverage,
      );
    });

    test(
      'an empty result is only "no advisory" when every source answered',
      () async {
        final agg = AdvisoryAggregator(
          providers: [_QuietProvider(AdvisorySource.jmaJapan)],
        );
        await agg.init();
        final r = await agg.fetchActiveAdvisoriesAtPoint(
          latitude: 39.72,
          longitude: 140.10,
        );

        // A source was asked and it answered; nothing failed. Silence here is
        // real silence.
        expect(r, isA<AdvisoryLookupComplete>());
        expect(r.canAssertNoAdvisory, isTrue);
        expect(r.seen, isEmpty);
      },
    );

    test('zero providers => UNAVAILABLE — a lookup that consulted nothing '
        'cannot claim completeness', () async {
      // 0.0.8's published contract: "zero sources asked is not an all-clear
      // either" (canAssertNoAdvisory required sourcesQueried > 0). The sealed
      // type keeps that promise: no provider registered means we did not look,
      // and "we did not look" is never rendered as "clear".
      final agg = AdvisoryAggregator(providers: const []);
      await agg.init();
      final r = await agg.fetchActiveAdvisoriesAtPoint(
        latitude: 39.72,
        longitude: 140.10,
      );

      expect(r, isA<AdvisoryLookupUnavailable>());
      expect(r.canAssertNoAdvisory, isFalse);
      expect(r.seen, isEmpty);
      expect(
        r.failures,
        isEmpty,
        reason:
            'nothing was asked, so nothing individually failed — the '
            'absence is the lookup itself',
      );
    });
  });
}
