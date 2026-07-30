import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:test/test.dart';

/// The SECOND way to be silent — the one the sealed type cannot see.
///
/// `AdvisoryLookup` closes the FAILURE path: a provider that throws can no
/// longer reach an integrator as an empty list. It does not close this path: a
/// provider that returns an empty list **without failing**, because the point is
/// outside the catalog it ships, is counted as asked-and-answered though it
/// never sent a request.
///
/// Measured, not imagined: `condition_aggregator_jma` returns
/// `const <Advisory>[]` for an out-of-catalog point without throwing
/// (`jma_advisory_provider.dart:169-175`). The integrator app that hit it wrote
/// the finding down first — *"the provider lied by silence — it counted as
/// asked-and-answered while never asking."*
///
/// This file pins BOTH halves of the truth: the gap that is still open by
/// default (so the docs can never quietly overclaim), and the opt-in paths that
/// close it.

Advisory _snowWarning() => Advisory(
  source: AdvisorySource.jmaJapan,
  eventClass: '大雪警報',
  severity: AdvisorySeverity.severe,
  certainty: AdvisoryCertainty.likely,
  urgency: AdvisoryUrgency.expected,
  areaDescription: '秋田県',
  effective: DateTime.utc(2026, 1, 8, 0, 0),
  expires: DateTime.utc(2026, 1, 8, 12, 0),
  headline: '大雪警報',
  description: '大雪による交通障害に警戒してください。',
);

/// The SHIPPED `condition_aggregator_jma` behaviour, reproduced exactly: a
/// bounded catalog, and for a point outside it an empty list returned **without
/// throwing and without sending a request** (`jma_advisory_provider.dart`
/// :169-175). It declares no coverage, because the published adapter declares
/// none.
///
/// [requestsSent] counts only fetches that would have hit the network, so a test
/// can assert the difference between *asked-and-empty* and *never-asked* — the
/// distinction the aggregator cannot currently make for itself.
class _ShippedJmaShapedProvider implements AdvisoryProvider {
  _ShippedJmaShapedProvider();
  @override
  AdvisorySource get source => AdvisorySource.jmaJapan;

  int requestsSent = 0;

  /// The six-prefecture snow-zone catalog, as a single crude bound: Akita is
  /// inside it, Tokyo is not. Stands in for `prefectureCodesForPoint`.
  bool _inCatalog(double lat, double lon) => lat >= 36.5 && lat <= 45.6;

  @override
  Future<void> init() async {}

  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async {
    if (!_inCatalog(latitude, longitude)) {
      // Verbatim shape of the shipped adapter: no request, no throw, empty list.
      return const <Advisory>[];
    }
    requestsSent++;
    return const <Advisory>[];
  }
}

/// The same adapter, having adopted [AdvisoryCoverage] — one added member, no
/// change to [AdvisoryProvider] and no change to its fetch path.
class _JmaShapedWithCoverage extends _ShippedJmaShapedProvider
    implements AdvisoryCoverage {
  @override
  bool coversPoint({required double latitude, required double longitude}) =>
      _inCatalog(latitude, longitude);
}

/// Answers empty without failing, and declares nothing. The shape every adapter
/// published today has.
class _QuietUndeclaredProvider implements AdvisoryProvider {
  _QuietUndeclaredProvider(this.source);
  @override
  final AdvisorySource source;
  int fetches = 0;

  @override
  Future<void> init() async {}

  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async {
    fetches++;
    return const [];
  }
}

/// Answers with a real warning, and declares nothing.
class _LoudUndeclaredProvider implements AdvisoryProvider {
  _LoudUndeclaredProvider(this.source);
  @override
  final AdvisorySource source;

  @override
  Future<void> init() async {}

  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async => [_snowWarning()];
}

/// The honest adapter: it says where its own catalog reaches, and the
/// aggregator must never ask it outside that.
class _CatalogProvider implements AdvisoryProvider, AdvisoryCoverage {
  _CatalogProvider(this.source, {required this.covers, this.advisories});
  @override
  final AdvisorySource source;
  final bool covers;
  final List<Advisory>? advisories;
  int fetches = 0;

  @override
  bool coversPoint({required double latitude, required double longitude}) =>
      covers;

  @override
  Future<void> init() async {}

  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async {
    fetches++;
    return advisories ?? const [];
  }
}

/// Covers the point, and then fails anyway.
class _CatalogFailingProvider implements AdvisoryProvider, AdvisoryCoverage {
  _CatalogFailingProvider(this.source);
  @override
  final AdvisorySource source;

  @override
  bool coversPoint({required double latitude, required double longitude}) =>
      true;

  @override
  Future<void> init() async {}

  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async => throw Exception('feed down');
}

void main() {
  // Akita — inside the JMA snow-zone catalog. Tokyo — outside it.
  const akitaLat = 39.7186, akitaLon = 140.1024;

  // The three-way, on ONE fixture that reproduces the shipped adapter exactly.
  // Read together these three tests are the honest answer to "is the
  // silent-coverage gap closed?": NO by default, YES on either opt-in. Any
  // future edit that changes one of these three answers makes the CHANGELOG,
  // the dartdoc and SAFETY_BOUNDARY.md false in the same instant.
  group('the out-of-catalog point, three ways', () {
    // Tokyo — outside the six-prefecture snow-zone catalog.
    const tokyoLat = 35.68, tokyoLon = 139.76;

    test(
      'DEFAULT + the shipped adapter: STILL a fabricated all-clear — the '
      'gap is open, and this test exists so no document may say otherwise',
      () async {
        final jma = _ShippedJmaShapedProvider();
        final agg = AdvisoryAggregator(providers: [jma]);
        await agg.init();
        final r = await agg.fetchActiveAdvisoriesAtPoint(
          latitude: tokyoLat,
          longitude: tokyoLon,
        );
        expect(
          jma.requestsSent,
          0,
          reason: 'nobody was asked — no request left the adapter',
        );
        expect(
          r.canAssertNoAdvisory,
          isTrue,
          reason:
              'THIS IS THE DEFECT, not a passing grade. An untouched adapter '
              'under an untouched aggregator still yields a positive all-clear '
              'on a lookup that never looked. It is documented as the honest '
              'scope in CHANGELOG / dartdoc / SAFETY_BOUNDARY; if this ever '
              'flips, those documents must be corrected in the same commit.',
        );
      },
    );

    test(
      'OPT-IN A — the adapter adopts AdvisoryCoverage: no all-clear',
      () async {
        final agg = AdvisoryAggregator(providers: [_JmaShapedWithCoverage()]);
        await agg.init();
        final r = await agg.fetchActiveAdvisoriesAtPoint(
          latitude: tokyoLat,
          longitude: tokyoLon,
        );
        expect(r.canAssertNoAdvisory, isFalse);
        expect(r, isA<AdvisoryLookupUnavailable>());
        expect(
          r.unreachable.single.reason,
          AdvisoryUnavailableReason.outOfCoverage,
        );
      },
    );

    test('OPT-IN B — the ADAPTER IS UNTOUCHED and the integrator sets '
        'requireDeclaredCoverage: no all-clear', () async {
      final agg = AdvisoryAggregator(
        providers: [_ShippedJmaShapedProvider()],
        requireDeclaredCoverage: true,
      );
      await agg.init();
      final r = await agg.fetchActiveAdvisoriesAtPoint(
        latitude: tokyoLat,
        longitude: tokyoLon,
      );
      expect(
        r.canAssertNoAdvisory,
        isFalse,
        reason:
            'this is the only path that closes the gap TODAY, with the '
            'adapters actually on pub.dev and no adapter change at all',
      );
      expect(
        r.unreachable.single.reason,
        AdvisoryUnavailableReason.coverageUndeclared,
      );
    });
  });

  group('the gap that is still open by default — pinned, not papered over', () {
    test('an undeclared provider that answers empty still yields Complete: '
        'the docs must keep saying so', () async {
      final quiet = _QuietUndeclaredProvider(AdvisorySource.jmaJapan);
      final agg = AdvisoryAggregator(providers: [quiet]);
      await agg.init();
      final r = await agg.fetchActiveAdvisoriesAtPoint(
        latitude: akitaLat,
        longitude: akitaLon,
      );
      // This is NOT the behaviour we want; it is the behaviour we HAVE, and
      // the CHANGELOG / dartdoc / SAFETY_BOUNDARY all state it as the honest
      // scope. If this test ever flips, those documents became false.
      expect(r, isA<AdvisoryLookupComplete>());
      expect(r.canAssertNoAdvisory, isTrue);
    });
  });

  group('AdvisoryCoverage — an adapter that declares where it can answer', () {
    test('a declared out-of-coverage provider is NOT asked', () async {
      final jma = _CatalogProvider(AdvisorySource.jmaJapan, covers: false);
      final agg = AdvisoryAggregator(providers: [jma]);
      await agg.init();
      await agg.fetchActiveAdvisoriesAtPoint(
        latitude: 35.68,
        longitude: 139.76,
      );
      expect(jma.fetches, 0, reason: 'no request may be sent outside coverage');
    });

    test('when NO provider covers the point the lookup is Unavailable with '
        'outOfCoverage — never a fabricated clear', () async {
      final agg = AdvisoryAggregator(
        providers: [
          _CatalogProvider(AdvisorySource.jmaJapan, covers: false),
          _CatalogProvider(AdvisorySource.nwsUnitedStates, covers: false),
        ],
      );
      await agg.init();
      final r = await agg.fetchActiveAdvisoriesAtPoint(
        latitude: 35.68,
        longitude: 139.76,
      );
      expect(r, isA<AdvisoryLookupUnavailable>());
      expect(r.canAssertNoAdvisory, isFalse);
      expect(
        r.unreachable.map((f) => f.reason),
        everyElement(AdvisoryUnavailableReason.outOfCoverage),
      );
      expect(r.unreachable, hasLength(2));
    });

    test('an out-of-coverage sibling does not poison a covering source\'s '
        'genuine all-clear', () async {
      final agg = AdvisoryAggregator(
        providers: [
          _CatalogProvider(AdvisorySource.jmaJapan, covers: true),
          _CatalogProvider(AdvisorySource.nwsUnitedStates, covers: false),
        ],
      );
      await agg.init();
      final r = await agg.fetchActiveAdvisoriesAtPoint(
        latitude: akitaLat,
        longitude: akitaLon,
      );
      expect(r, isA<AdvisoryLookupComplete>());
      expect(r.canAssertNoAdvisory, isTrue);
    });

    test('a covering source\'s warning is carried, out-of-coverage sibling '
        'or not — a hazard seen is a hazard real', () async {
      final agg = AdvisoryAggregator(
        providers: [
          _CatalogProvider(
            AdvisorySource.jmaJapan,
            covers: true,
            advisories: [_snowWarning()],
          ),
          _CatalogProvider(AdvisorySource.nwsUnitedStates, covers: false),
        ],
      );
      await agg.init();
      final r = await agg.fetchActiveAdvisoriesAtPoint(
        latitude: akitaLat,
        longitude: akitaLon,
      );
      expect(r.seen, hasLength(1));
      expect(r.seen.single.eventClass, '大雪警報');
      expect(r, isA<AdvisoryLookupComplete>());
    });

    test('the completeness denominator excludes out-of-coverage: the only '
        'covering source failing means we know nothing', () async {
      final agg = AdvisoryAggregator(
        providers: [
          _CatalogFailingProvider(AdvisorySource.jmaJapan),
          _CatalogProvider(AdvisorySource.nwsUnitedStates, covers: false),
        ],
      );
      await agg.init();
      final r = await agg.fetchActiveAdvisoriesAtPoint(
        latitude: akitaLat,
        longitude: akitaLon,
      );
      expect(
        r,
        isA<AdvisoryLookupUnavailable>(),
        reason:
            'without the exclusion this reads Partial — "some source '
            'answered" — when the only source that could answer did not',
      );
    });
  });

  group('requireDeclaredCoverage — refuse completeness we cannot prove', () {
    test('off by default: today\'s behaviour is untouched', () async {
      final agg = AdvisoryAggregator(
        providers: [_QuietUndeclaredProvider(AdvisorySource.jmaJapan)],
      );
      expect(agg.requireDeclaredCoverage, isFalse);
      await agg.init();
      final r = await agg.fetchActiveAdvisoriesAtPoint(
        latitude: akitaLat,
        longitude: akitaLon,
      );
      expect(r, isA<AdvisoryLookupComplete>());
    });

    test('on: an undeclared quiet source cannot buy an all-clear', () async {
      final quiet = _QuietUndeclaredProvider(AdvisorySource.jmaJapan);
      final agg = AdvisoryAggregator(
        providers: [quiet],
        requireDeclaredCoverage: true,
      );
      await agg.init();
      final r = await agg.fetchActiveAdvisoriesAtPoint(
        latitude: akitaLat,
        longitude: akitaLon,
      );
      expect(r.canAssertNoAdvisory, isFalse);
      expect(r, isA<AdvisoryLookupUnavailable>());
      expect(
        r.unreachable.single.reason,
        AdvisoryUnavailableReason.coverageUndeclared,
      );
      expect(
        quiet.fetches,
        1,
        reason: 'we still ASK — we only refuse to claim',
      );
    });

    test('on: a hazard SEEN survives — caution-add-only, never demoted to '
        '"we know nothing"', () async {
      final agg = AdvisoryAggregator(
        providers: [_LoudUndeclaredProvider(AdvisorySource.jmaJapan)],
        requireDeclaredCoverage: true,
      );
      await agg.init();
      final r = await agg.fetchActiveAdvisoriesAtPoint(
        latitude: akitaLat,
        longitude: akitaLon,
      );
      expect(r, isA<AdvisoryLookupPartial>());
      expect(r.seen, hasLength(1));
      expect(r.seen.single.eventClass, '大雪警報');
      expect(r.canAssertNoAdvisory, isFalse);
    });

    test('on: a provider that DOES declare coverage is unaffected', () async {
      final agg = AdvisoryAggregator(
        providers: [_CatalogProvider(AdvisorySource.jmaJapan, covers: true)],
        requireDeclaredCoverage: true,
      );
      await agg.init();
      final r = await agg.fetchActiveAdvisoriesAtPoint(
        latitude: akitaLat,
        longitude: akitaLon,
      );
      expect(r, isA<AdvisoryLookupComplete>());
      expect(r.canAssertNoAdvisory, isTrue);
    });
  });
}
