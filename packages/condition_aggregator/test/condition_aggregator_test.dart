import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:test/test.dart';

void main() {
  group('Advisory value-object', () {
    final base = Advisory(
      source: AdvisorySource.nwsUnitedStates,
      eventClass: 'Winter Storm Warning',
      severity: AdvisorySeverity.severe,
      certainty: AdvisoryCertainty.likely,
      urgency: AdvisoryUrgency.expected,
      areaDescription: 'Towner; Cavalier; Benson',
      effective: DateTime.utc(2026, 5, 3, 0, 0),
      expires: DateTime.utc(2026, 5, 3, 12, 0),
      headline: 'Winter Storm Warning issued by NWS Grand Forks ND',
      description: 'Heavy snow expected.',
    );

    test('equatable equality on identical fields', () {
      final twin = Advisory(
        source: AdvisorySource.nwsUnitedStates,
        eventClass: 'Winter Storm Warning',
        severity: AdvisorySeverity.severe,
        certainty: AdvisoryCertainty.likely,
        urgency: AdvisoryUrgency.expected,
        areaDescription: 'Towner; Cavalier; Benson',
        effective: DateTime.utc(2026, 5, 3, 0, 0),
        expires: DateTime.utc(2026, 5, 3, 12, 0),
        headline: 'Winter Storm Warning issued by NWS Grand Forks ND',
        description: 'Heavy snow expected.',
      );
      expect(twin, equals(base));
    });

    test('isHighImpact true for severe and extreme', () {
      expect(base.isHighImpact, isTrue);
      final extreme = Advisory(
        source: base.source,
        eventClass: base.eventClass,
        severity: AdvisorySeverity.extreme,
        certainty: base.certainty,
        urgency: base.urgency,
        areaDescription: base.areaDescription,
        effective: base.effective,
        expires: base.expires,
        headline: base.headline,
        description: base.description,
      );
      expect(extreme.isHighImpact, isTrue);
    });

    test('isHighImpact false for moderate and below', () {
      final moderate = Advisory(
        source: base.source,
        eventClass: base.eventClass,
        severity: AdvisorySeverity.moderate,
        certainty: base.certainty,
        urgency: base.urgency,
        areaDescription: base.areaDescription,
        effective: base.effective,
        expires: base.expires,
        headline: base.headline,
        description: base.description,
      );
      expect(moderate.isHighImpact, isFalse);
    });

    test('isExpiredAt returns false when expires is null', () {
      final neverExpires = Advisory(
        source: base.source,
        eventClass: base.eventClass,
        severity: base.severity,
        certainty: base.certainty,
        urgency: base.urgency,
        areaDescription: base.areaDescription,
        effective: base.effective,
        expires: null,
        headline: base.headline,
        description: base.description,
      );
      expect(neverExpires.isExpiredAt(DateTime.utc(2099, 1, 1)), isFalse);
    });

    test('isExpiredAt true when now after expires', () {
      expect(base.isExpiredAt(DateTime.utc(2026, 5, 4)), isTrue);
      expect(base.isExpiredAt(DateTime.utc(2026, 5, 3, 6)), isFalse);
    });

    test('stalenessAt returns null when effective is null', () {
      final unknownEffective = Advisory(
        source: base.source,
        eventClass: base.eventClass,
        severity: base.severity,
        certainty: base.certainty,
        urgency: base.urgency,
        areaDescription: base.areaDescription,
        effective: null,
        expires: base.expires,
        headline: base.headline,
        description: base.description,
      );
      expect(
        unknownEffective.stalenessAt(DateTime.utc(2026, 5, 3, 12, 0)),
        isNull,
      );
    });

    test('stalenessAt returns now − effective for past-effective advisory', () {
      // base.effective = 2026-05-03T00:00Z
      final s = base.stalenessAt(DateTime.utc(2026, 5, 3, 6, 0));
      expect(s, equals(const Duration(hours: 6)));
    });

    test('stalenessAt clamps to zero when effective is in the future', () {
      // base.effective = 2026-05-03T00:00Z; now is BEFORE.
      final s = base.stalenessAt(DateTime.utc(2026, 5, 2, 23, 0));
      expect(s, equals(Duration.zero));
    });

    test('isStaleAt false when effective is null (unknown freshness)', () {
      final unknownEffective = Advisory(
        source: base.source,
        eventClass: base.eventClass,
        severity: base.severity,
        certainty: base.certainty,
        urgency: base.urgency,
        areaDescription: base.areaDescription,
        effective: null,
        expires: base.expires,
        headline: base.headline,
        description: base.description,
      );
      expect(
        unknownEffective.isStaleAt(
          DateTime.utc(2026, 5, 3, 12, 0),
          const Duration(hours: 1),
        ),
        isFalse,
      );
    });

    test('isStaleAt true when delta meets-or-exceeds threshold', () {
      // base.effective = 2026-05-03T00:00Z; now = +90 minutes.
      expect(
        base.isStaleAt(
          DateTime.utc(2026, 5, 3, 1, 30),
          const Duration(hours: 1),
        ),
        isTrue,
      );
    });

    test('isStaleAt false when delta strictly below threshold', () {
      // base.effective = 2026-05-03T00:00Z; now = +30 minutes.
      expect(
        base.isStaleAt(
          DateTime.utc(2026, 5, 3, 0, 30),
          const Duration(hours: 1),
        ),
        isFalse,
      );
    });
  });

  group('AdvisoryProviderInitException', () {
    test('toString includes source name and message', () {
      const e = AdvisoryProviderInitException(
        source: AdvisorySource.jmaJapan,
        message: 'schema-version mismatch',
      );
      final s = e.toString();
      expect(s, contains('jmaJapan'));
      expect(s, contains('schema-version mismatch'));
    });
  });

  group('AdvisoryAggregator fan-out', () {
    test('throws StateError when fetched before init', () async {
      final agg = AdvisoryAggregator(
        providers: <AdvisoryProvider>[
          _StubProvider(source: AdvisorySource.nwsUnitedStates),
        ],
      );
      expect(
        () => agg.fetchActiveAdvisoriesAtPoint(latitude: 0, longitude: 0),
        throwsStateError,
      );
    });

    test(
      'init then fetch returns merged advisories from all providers',
      () async {
        final a1 = Advisory(
          source: AdvisorySource.nwsUnitedStates,
          eventClass: 'Winter Storm Warning',
          severity: AdvisorySeverity.severe,
          certainty: AdvisoryCertainty.likely,
          urgency: AdvisoryUrgency.expected,
          areaDescription: 'Area-A',
          effective: null,
          expires: null,
          headline: 'h1',
          description: 'd1',
        );
        final a2 = Advisory(
          source: AdvisorySource.jmaJapan,
          eventClass: 'VPWW54',
          severity: AdvisorySeverity.severe,
          certainty: AdvisoryCertainty.observed,
          urgency: AdvisoryUrgency.immediate,
          areaDescription: 'Area-B',
          effective: null,
          expires: null,
          headline: 'h2',
          description: 'd2',
        );
        final agg = AdvisoryAggregator(
          providers: <AdvisoryProvider>[
            _StubProvider(
              source: AdvisorySource.nwsUnitedStates,
              advisories: <Advisory>[a1],
            ),
            _StubProvider(
              source: AdvisorySource.jmaJapan,
              advisories: <Advisory>[a2],
            ),
          ],
        );
        await agg.init();
        final result = await agg.fetchActiveAdvisoriesAtPoint(
          latitude: 47.9,
          longitude: -97.0,
        );
        expect(result.seen, containsAll(<Advisory>[a1, a2]));
        expect(result.failures, isEmpty);
      },
    );

    test(
      'warn-and-continue: per-provider error captured, others continue',
      () async {
        final goodAdvisory = Advisory(
          source: AdvisorySource.nwsUnitedStates,
          eventClass: 'Winter Storm Warning',
          severity: AdvisorySeverity.severe,
          certainty: AdvisoryCertainty.likely,
          urgency: AdvisoryUrgency.expected,
          areaDescription: 'Area-A',
          effective: null,
          expires: null,
          headline: 'h',
          description: 'd',
        );
        final agg = AdvisoryAggregator(
          providers: <AdvisoryProvider>[
            _StubProvider(
              source: AdvisorySource.nwsUnitedStates,
              advisories: <Advisory>[goodAdvisory],
            ),
            _StubProvider(
              source: AdvisorySource.jmaJapan,
              throwOnFetch: 'transport timeout',
            ),
          ],
        );
        await agg.init();
        final result = await agg.fetchActiveAdvisoriesAtPoint(
          latitude: 0,
          longitude: 0,
        );
        expect(result.seen, equals(<Advisory>[goodAdvisory]));
        expect(result.failures, hasLength(1));
        expect(result.failures.single.source, AdvisorySource.jmaJapan);
        // The reason is now TYPED, not a string. A driver cannot be shown
        // 'transport timeout'; she can be shown "the source did not answer in
        // time", in her own language — and only a typed reason survives that
        // translation.
        expect(
          result.failures.single.reason,
          AdvisoryUnavailableReason.timedOut,
        );
        // And the guarantee that matters: one source failed, so we may NOT tell
        // her nothing is in force.
        expect(result.canAssertNoAdvisory, isFalse);
        expect(result, isA<AdvisoryLookupPartial>());
      },
    );

    test('init failure propagates (does not fan-and-swallow)', () async {
      final agg = AdvisoryAggregator(
        providers: <AdvisoryProvider>[
          _StubProvider(
            source: AdvisorySource.jmaJapan,
            throwOnInit: 'schema-version mismatch',
          ),
        ],
      );
      expect(() => agg.init(), throwsA(isA<AdvisoryProviderInitException>()));
    });

    test('init is idempotent: second call after success is no-op', () async {
      final stub = _StubProvider(source: AdvisorySource.nwsUnitedStates);
      final agg = AdvisoryAggregator(providers: <AdvisoryProvider>[stub]);
      await agg.init();
      await agg.init();
      expect(stub.initCallCount, equals(1));
      expect(agg.isInitialized, isTrue);
    });
  });

  group('Advisory JSON serialization (0.0.3)', () {
    final canonical = Advisory(
      source: AdvisorySource.metNorway,
      eventClass: 'Winter Storm Warning',
      severity: AdvisorySeverity.severe,
      certainty: AdvisoryCertainty.likely,
      urgency: AdvisoryUrgency.expected,
      areaDescription: 'Nordland',
      effective: DateTime.utc(2026, 1, 15, 6, 0),
      expires: DateTime.utc(2026, 1, 15, 18, 0),
      headline: 'Heavy snow expected',
      description: 'Heavy snow expected across the region.',
    );

    test('round-trip preserves equality', () {
      final json = canonical.toJson();
      final reconstructed = Advisory.fromJson(json);
      expect(reconstructed, equals(canonical));
    });

    test('toJson encodes null effective / expires as null '
        '(not omitted; not empty string)', () {
      final noTimes = Advisory(
        source: AdvisorySource.nwsUnitedStates,
        eventClass: 'Freeze Warning',
        severity: AdvisorySeverity.minor,
        certainty: AdvisoryCertainty.unknown,
        urgency: AdvisoryUrgency.unknown,
        areaDescription: 'Area-X',
        effective: null,
        expires: null,
        headline: 'h',
        description: 'd',
      );
      final json = noTimes.toJson();
      expect(json['effective'], isNull);
      expect(json['expires'], isNull);
      final reconstructed = Advisory.fromJson(json);
      expect(reconstructed.effective, isNull);
      expect(reconstructed.expires, isNull);
    });

    test('attributionString format per source', () {
      expect(
        AdvisorySource.nwsUnitedStates.attributionString,
        contains('U.S. National Weather Service'),
      );
      expect(
        AdvisorySource.jmaJapan.attributionString,
        contains('Japan Meteorological Agency'),
      );
      expect(AdvisorySource.metNorway.attributionString, contains('CC BY 4.0'));
      expect(AdvisorySource.other.attributionString, contains('Other'));
    });

    test('fromJson throws on missing eventClass', () {
      final bad = <String, dynamic>{
        'source': 'nwsUnitedStates',
        'severity': 'severe',
        'certainty': 'likely',
        'urgency': 'expected',
        'areaDescription': 'Area-X',
        'effective': null,
        'expires': null,
        'headline': 'h',
        'description': 'd',
      };
      expect(
        () => Advisory.fromJson(bad),
        throwsA(isA<AdvisoryDeserializationException>()),
      );
    });

    test('fromJson maps unknown enum names to fallback variants '
        '(forward-compat)', () {
      final json = <String, dynamic>{
        'source': 'futureUnknownPublisher',
        'eventClass': 'Some Event',
        'severity': 'apocalyptic',
        'certainty': 'mostlyMaybe',
        'urgency': 'someday',
        'areaDescription': 'Area-X',
        'effective': null,
        'expires': null,
        'headline': 'h',
        'description': 'd',
      };
      final reconstructed = Advisory.fromJson(json);
      expect(reconstructed.source, equals(AdvisorySource.other));
      expect(reconstructed.severity, equals(AdvisorySeverity.unknown));
      expect(reconstructed.certainty, equals(AdvisoryCertainty.unknown));
      expect(reconstructed.urgency, equals(AdvisoryUrgency.unknown));
    });
  });
}

class _StubProvider implements AdvisoryProvider {
  @override
  final AdvisorySource source;
  final List<Advisory> _advisories;
  final String? throwOnInit;
  final String? throwOnFetch;
  int initCallCount = 0;

  _StubProvider({
    required this.source,
    List<Advisory> advisories = const <Advisory>[],
    this.throwOnInit,
    this.throwOnFetch,
  }) : _advisories = advisories;

  @override
  Future<void> init() async {
    initCallCount++;
    final t = throwOnInit;
    if (t != null) {
      throw AdvisoryProviderInitException(source: source, message: t);
    }
  }

  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async {
    final t = throwOnFetch;
    if (t != null) throw Exception(t);
    return _advisories;
  }
}
