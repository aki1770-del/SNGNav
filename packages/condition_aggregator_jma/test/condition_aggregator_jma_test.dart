import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_jma/condition_aggregator_jma.dart';
import 'package:condition_aggregator_jma/src/jma_advisory_mapper.dart';
import 'package:test/test.dart';

void main() {
  group('JmaAdvisoryProvider — interface compliance', () {
    test('source returns AdvisorySource.jmaJapan', () {
      final provider = JmaAdvisoryProvider();
      expect(provider.source, equals(AdvisorySource.jmaJapan));
    });

    test('init completes without throwing', () async {
      final provider = JmaAdvisoryProvider();
      await provider.init();
    });

    test('default endpointBaseUrl points at the public JMA XML feed', () {
      final provider = JmaAdvisoryProvider();
      expect(provider.endpointBaseUrl, contains('jma.go.jp'));
    });

    test('endpointBaseUrl is constructor-injectable', () {
      const testUrl = 'https://test.fixture/jma/';
      final provider = JmaAdvisoryProvider(endpointBaseUrl: testUrl);
      expect(provider.endpointBaseUrl, equals(testUrl));
    });
  });

  group('JmaAdvisoryProvider — explore-phase stub behavior', () {
    test(
      'fetchActiveAdvisoriesAtPoint returns empty list at any point '
      '(explore-phase stub)',
      () async {
        final provider = JmaAdvisoryProvider();
        await provider.init();
        final result = await provider.fetchActiveAdvisoriesAtPoint(
          latitude: 35.6762, // Tokyo
          longitude: 139.6503,
        );
        expect(result, isEmpty);
      },
    );

    test(
      'fetchActiveAdvisoriesAtPoint without init throws '
      'AdvisoryProviderInitException',
      () async {
        final provider = JmaAdvisoryProvider();
        expect(
          () => provider.fetchActiveAdvisoriesAtPoint(
            latitude: 39.7186, // Akita
            longitude: 140.1024,
          ),
          throwsA(isA<AdvisoryProviderInitException>()),
        );
      },
    );

    test(
      'fetchActiveAdvisoriesAtPoint stub returns the same empty result '
      'across distinct geographic points',
      () async {
        final provider = JmaAdvisoryProvider();
        await provider.init();
        final tokyo = await provider.fetchActiveAdvisoriesAtPoint(
          latitude: 35.6762,
          longitude: 139.6503,
        );
        final akita = await provider.fetchActiveAdvisoriesAtPoint(
          latitude: 39.7186,
          longitude: 140.1024,
        );
        expect(tokyo, isEmpty);
        expect(akita, isEmpty);
      },
    );
  });

  group('mapJmaForecastToAdvisory — placeholder shape lock', () {
    test('source is always jmaJapan', () {
      const record = JmaForecastRecord(
        reportFamilyCode: 'VPWW54',
        headline: '暴風雪警報',
        description: '北日本では暴風雪に警戒してください。',
        areaDescription: '秋田県',
        effective: null,
        expires: null,
      );
      final advisory = mapJmaForecastToAdvisory(record);
      expect(advisory.source, equals(AdvisorySource.jmaJapan));
    });

    test(
      'eventClass preserves JMA report family code verbatim '
      '(verbatim-relay discipline)',
      () {
        const record = JmaForecastRecord(
          reportFamilyCode: 'VPCJ51',
          headline: '大雪警報',
          description: '',
          areaDescription: '青森県',
          effective: null,
          expires: null,
        );
        final advisory = mapJmaForecastToAdvisory(record);
        expect(advisory.eventClass, equals('VPCJ51'));
      },
    );

    test(
      'severity / certainty / urgency map to unknown at explore-phase '
      '(deploy-graduation expands the per-report-family table)',
      () {
        const record = JmaForecastRecord(
          reportFamilyCode: 'VPAW51',
          headline: '',
          description: '',
          areaDescription: '',
          effective: null,
          expires: null,
        );
        final advisory = mapJmaForecastToAdvisory(record);
        expect(advisory.severity, equals(AdvisorySeverity.unknown));
        expect(advisory.certainty, equals(AdvisoryCertainty.unknown));
        expect(advisory.urgency, equals(AdvisoryUrgency.unknown));
      },
    );

    test(
      'areaDescription / headline / description / effective / expires '
      'are direct passthroughs',
      () {
        final effective = DateTime.utc(2026, 1, 15, 6, 0);
        final expires = DateTime.utc(2026, 1, 15, 18, 0);
        final record = JmaForecastRecord(
          reportFamilyCode: 'VPFD60',
          headline: '大雪と暴風雪に関する全般気象情報',
          description: '北日本では今夜から朝にかけて大雪となる見込み。',
          areaDescription: '北海道、東北地方',
          effective: effective,
          expires: expires,
        );
        final advisory = mapJmaForecastToAdvisory(record);
        expect(advisory.headline, equals('大雪と暴風雪に関する全般気象情報'));
        expect(
          advisory.description,
          equals('北日本では今夜から朝にかけて大雪となる見込み。'),
        );
        expect(advisory.areaDescription, equals('北海道、東北地方'));
        expect(advisory.effective, equals(effective));
        expect(advisory.expires, equals(expires));
      },
    );
  });
}
