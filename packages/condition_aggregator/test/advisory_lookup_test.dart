import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:test/test.dart';

Advisory _adv() => const Advisory(
  source: AdvisorySource.jmaJapan,
  eventClass: '大雪警報',
  severity: AdvisorySeverity.severe,
  certainty: AdvisoryCertainty.observed,
  urgency: AdvisoryUrgency.immediate,
  areaDescription: '秋田県',
  effective: null,
  expires: null,
  headline: '大雪警報',
  description: '',
);

AdvisoryProviderError _err() => const AdvisoryProviderError(
  source: AdvisorySource.jmaJapan,
  message: 'down',
  reason: AdvisoryUnavailableReason.networkUnreachable,
);

void main() {
  group('an empty list is not an all-clear unless the lookup was complete', () {
    test(
      'every source answered → Complete, and only then may we say "none"',
      () {
        final lookup = const AdvisoryAggregateResult(
          advisories: [],
          providerErrors: [],
          sourcesQueried: 2,
        ).toLookup();

        expect(lookup, isA<AdvisoryLookupComplete>());
        expect(lookup.canAssertNoAdvisory, isTrue);
        expect(lookup.seen, isEmpty);
        expect(lookup.failures, isEmpty);
      },
    );

    test(
      'EVERY source down → Unavailable, NOT Complete — the blizzard case',
      () {
        final lookup = AdvisoryAggregateResult(
          advisories: const [],
          providerErrors: [_err()],
          sourcesQueried: 1,
        ).toLookup();

        // THE ASSERTION THAT MATTERS. If this ever reads Complete, an outage
        // renders to the driver as a clear sky.
        expect(lookup, isA<AdvisoryLookupUnavailable>());
        expect(lookup.canAssertNoAdvisory, isFalse);
        expect(lookup.seen, isEmpty);
        expect(
          lookup.failures.single.reason,
          AdvisoryUnavailableReason.networkUnreachable,
        );
      },
    );

    test(
      'some down, some answered → Partial; seen is safe, silence is not',
      () {
        final lookup = AdvisoryAggregateResult(
          advisories: [_adv()],
          providerErrors: [_err()],
          sourcesQueried: 2,
        ).toLookup();

        expect(lookup, isA<AdvisoryLookupPartial>());
        expect(lookup.canAssertNoAdvisory, isFalse);
        expect(lookup.seen, hasLength(1)); // act on what was seen
        expect(lookup.failures, hasLength(1));
      },
    );

    test('unknown provenance never claims completeness', () {
      final lookup = const AdvisoryAggregateResult(
        advisories: [],
        providerErrors: [],
        // sourcesQueried omitted — we do not know if anyone was asked.
      ).toLookup();

      expect(lookup.canAssertNoAdvisory, isFalse);
      expect(lookup, isNot(isA<AdvisoryLookupComplete>()));
    });
  });

  test('the typed reason survives the conversion, so it can be translated', () {
    final lookup = AdvisoryAggregateResult(
      advisories: const [],
      providerErrors: [
        const AdvisoryProviderError(
          source: AdvisorySource.metNorway,
          message: 'x',
          reason: AdvisoryUnavailableReason.timedOut,
        ),
      ],
      sourcesQueried: 1,
    ).toLookup();

    final f = lookup.failures.single;
    expect(f.source, AdvisorySource.metNorway);
    expect(f.reason, AdvisoryUnavailableReason.timedOut);
  });

  test(
    '0.0.8 surfaces are UNCHANGED — this release adds, it does not move',
    () {
      const r = AdvisoryAggregateResult(
        advisories: [],
        providerErrors: [],
        sourcesQueried: 1,
      );
      // Everything a 0.0.8 consumer already calls must still be here.
      expect(r.canAssertNoAdvisory, isTrue);
      expect(r.isUnavailable, isFalse);
      expect(r.seen, isEmpty);
      expect(r.unreachable, isEmpty);
      expect(
        r.fold(
          complete: (_) => 'c',
          partial: (_, _) => 'p',
          unavailable: (_) => 'u',
        ),
        'c',
      );
    },
  );
}
