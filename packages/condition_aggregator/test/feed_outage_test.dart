// A feed outage is not a clear sky.
//
// These tests exercise the 0.0.8 additions that let a caller tell an empty
// advisory list ("no advisory in force") apart from an empty advisory list
// ("every source was down"). They do not compile against 0.0.7 — the getters,
// `fold`, and `requireCompleteLookup` did not exist — which is exactly the
// point: 0.0.7 gave you no un-ignorable way to make the distinction.

import 'dart:async';

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:test/test.dart';

class _StubProvider implements AdvisoryProvider {
  @override
  final AdvisorySource source;
  final List<Advisory> _advisories;
  final Object? throwOnFetch;

  _StubProvider({
    required this.source,
    List<Advisory> advisories = const <Advisory>[],
    this.throwOnFetch,
  }) : _advisories = advisories;

  @override
  Future<void> init() async {}

  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async {
    final t = throwOnFetch;
    if (t != null) throw t;
    return _advisories;
  }
}

Advisory _adv(AdvisorySource source, String headline) => Advisory(
  source: source,
  eventClass: 'Winter Storm Warning',
  severity: AdvisorySeverity.severe,
  certainty: AdvisoryCertainty.likely,
  urgency: AdvisoryUrgency.expected,
  areaDescription: 'Area',
  effective: null,
  expires: null,
  headline: headline,
  description: 'd',
);

void main() {
  group('canAssertNoAdvisory — the one gate on claiming silence', () {
    test(
      'genuinely clear: all sources answered, empty list → CAN assert',
      () async {
        final agg = AdvisoryAggregator(
          providers: <AdvisoryProvider>[
            _StubProvider(source: AdvisorySource.nwsUnitedStates),
            _StubProvider(source: AdvisorySource.jmaJapan),
          ],
        );
        await agg.init();
        final r = await agg.fetchActiveAdvisoriesAtPoint(
          latitude: 0,
          longitude: 0,
        );

        expect(r.advisories, isEmpty);
        expect(
          r.canAssertNoAdvisory,
          isTrue,
          reason:
              'every source answered; an empty list here is a real all-clear',
        );
        expect(r.isUnavailable, isFalse);
      },
    );

    test('the defect this ships to fix: EVERY source down → empty list, but '
        'must NOT be readable as an all-clear', () async {
      final agg = AdvisoryAggregator(
        providers: <AdvisoryProvider>[
          _StubProvider(
            source: AdvisorySource.jmaJapan,
            throwOnFetch: TimeoutException('JMA did not answer'),
          ),
          _StubProvider(
            source: AdvisorySource.nwsUnitedStates,
            throwOnFetch: const FormatException('garbage GeoJSON'),
          ),
        ],
      );
      await agg.init();
      final r = await agg.fetchActiveAdvisoriesAtPoint(
        latitude: 0,
        longitude: 0,
      );

      // The empty list is IDENTICAL to the clear-sky case above...
      expect(r.advisories, isEmpty);
      // ...but the truth is now un-ignorable:
      expect(
        r.canAssertNoAdvisory,
        isFalse,
        reason:
            'no source was successfully read — this is an outage, not clear',
      );
      expect(r.isUnavailable, isTrue);
    });

    test(
      'partial outage: some seen → act on them, but cannot claim silence',
      () async {
        final agg = AdvisoryAggregator(
          providers: <AdvisoryProvider>[
            _StubProvider(
              source: AdvisorySource.nwsUnitedStates,
              advisories: <Advisory>[
                _adv(AdvisorySource.nwsUnitedStates, 'snow'),
              ],
            ),
            _StubProvider(
              source: AdvisorySource.jmaJapan,
              throwOnFetch: TimeoutException('JMA down'),
            ),
          ],
        );
        await agg.init();
        final r = await agg.fetchActiveAdvisoriesAtPoint(
          latitude: 0,
          longitude: 0,
        );

        expect(r.seen, hasLength(1), reason: 'a hazard seen is a hazard real');
        expect(
          r.canAssertNoAdvisory,
          isFalse,
          reason:
              'the warning we are missing may be in the source that is down',
        );
        expect(r.isUnavailable, isFalse);
      },
    );
  });

  group('typed failure reason — a sentence the driver can read', () {
    test(
      'timeout / parse / init classified; unknown stays unclassified',
      () async {
        final agg = AdvisoryAggregator(
          providers: <AdvisoryProvider>[
            _StubProvider(
              source: AdvisorySource.jmaJapan,
              throwOnFetch: TimeoutException('t'),
            ),
            _StubProvider(
              source: AdvisorySource.nwsUnitedStates,
              throwOnFetch: const FormatException('bad'),
            ),
            _StubProvider(
              source: AdvisorySource.metNorway,
              throwOnFetch: StateError('mystery'),
            ),
          ],
        );
        await agg.init();
        final r = await agg.fetchActiveAdvisoriesAtPoint(
          latitude: 0,
          longitude: 0,
        );

        final bySource = {for (final e in r.providerErrors) e.source: e.reason};
        expect(
          bySource[AdvisorySource.jmaJapan],
          AdvisoryUnavailableReason.timedOut,
        );
        expect(
          bySource[AdvisorySource.nwsUnitedStates],
          AdvisoryUnavailableReason.unparseable,
        );
        // We do not guess. An unrecognised error stays unclassified, with the
        // original preserved in `cause`.
        expect(
          bySource[AdvisorySource.metNorway],
          AdvisoryUnavailableReason.unclassified,
        );
        final met = r.providerErrors.firstWhere(
          (e) => e.source == AdvisorySource.metNorway,
        );
        expect(met.cause, isA<StateError>());
      },
    );
  });

  group('fold — handle every case or do not compile', () {
    test(
      'routes complete / partial / unavailable to the right branch',
      () async {
        String banner(AdvisoryAggregateResult r) => r.fold(
          complete: (a) => a.isEmpty ? 'NO_ADVISORY' : 'ADVISORY',
          partial: (seen, down) => 'PARTIAL',
          unavailable: (down) => 'FEED_DOWN',
        );

        final clear = AdvisoryAggregator(
          providers: <AdvisoryProvider>[
            _StubProvider(source: AdvisorySource.nwsUnitedStates),
          ],
        );
        await clear.init();
        expect(
          banner(
            await clear.fetchActiveAdvisoriesAtPoint(latitude: 0, longitude: 0),
          ),
          'NO_ADVISORY',
        );

        final down = AdvisoryAggregator(
          providers: <AdvisoryProvider>[
            _StubProvider(
              source: AdvisorySource.jmaJapan,
              throwOnFetch: TimeoutException('down'),
            ),
          ],
        );
        await down.init();
        expect(
          banner(
            await down.fetchActiveAdvisoriesAtPoint(latitude: 0, longitude: 0),
          ),
          'FEED_DOWN',
        );

        final partial = AdvisoryAggregator(
          providers: <AdvisoryProvider>[
            _StubProvider(
              source: AdvisorySource.nwsUnitedStates,
              advisories: <Advisory>[_adv(AdvisorySource.nwsUnitedStates, 'x')],
            ),
            _StubProvider(
              source: AdvisorySource.jmaJapan,
              throwOnFetch: TimeoutException('down'),
            ),
          ],
        );
        await partial.init();
        expect(
          banner(
            await partial.fetchActiveAdvisoriesAtPoint(
              latitude: 0,
              longitude: 0,
            ),
          ),
          'PARTIAL',
        );
      },
    );
  });

  group('requireCompleteLookup — opt-in loud stop with a way forward', () {
    test('does not throw when every source answered', () async {
      final agg = AdvisoryAggregator(
        providers: <AdvisoryProvider>[
          _StubProvider(source: AdvisorySource.nwsUnitedStates),
        ],
      );
      await agg.init();
      final r = await agg.fetchActiveAdvisoriesAtPoint(
        latitude: 0,
        longitude: 0,
      );
      expect(r.requireCompleteLookup, returnsNormally);
    });

    test(
      'throws a lamp — names the source, the reason, and the way forward',
      () async {
        final agg = AdvisoryAggregator(
          providers: <AdvisoryProvider>[
            _StubProvider(
              source: AdvisorySource.jmaJapan,
              throwOnFetch: TimeoutException('JMA down'),
            ),
          ],
        );
        await agg.init();
        final r = await agg.fetchActiveAdvisoriesAtPoint(
          latitude: 0,
          longitude: 0,
        );

        expect(
          r.requireCompleteLookup,
          throwsA(
            isA<AdvisoryLookupIncompleteException>()
                .having((e) => e.message, 'message', contains('jmaJapan'))
                .having(
                  (e) => e.message,
                  'says the reason',
                  contains('timedOut'),
                )
                .having((e) => e.message, 'points forward', contains('0.1.0'))
                .having((e) => e.unreachable, 'unreachable', hasLength(1)),
          ),
        );
      },
    );
  });

  group('hand-built result keeps 0.0.7 source-compatibility', () {
    test('constructing without sourcesQueried compiles and is honest (cannot '
        'claim completeness on unknown provenance)', () {
      // This is the 0.0.7 constructor call shape — it still compiles.
      const r = AdvisoryAggregateResult(
        advisories: <Advisory>[],
        providerErrors: <AdvisoryProviderError>[],
      );
      expect(
        r.canAssertNoAdvisory,
        isFalse,
        reason: 'unknown how many sources were asked → will not claim clear',
      );
    });
  });
}
