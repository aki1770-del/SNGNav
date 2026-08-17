import 'package:driving_weather/driving_weather.dart';
import 'package:japanese_snow_vocabulary/japanese_snow_vocabulary.dart';
import 'package:snow_rendering/snow_rendering.dart';
import 'package:test/test.dart';

void main() {
  group('RoadSurfaceState.announcement', () {
    test('dry has nothing to announce', () {
      expect(RoadSurfaceState.dry.announcement, isNull);
    });

    test('every non-dry surface has an announcement with both locales', () {
      for (final surface in RoadSurfaceState.values) {
        if (surface == RoadSurfaceState.dry) continue;
        final a = surface.announcement;
        expect(a, isNotNull, reason: '$surface must announce');
        expect(a!.jaSpokenText, isNotEmpty, reason: '$surface ja');
        expect(a.enSpokenText, isNotEmpty, reason: '$surface en');
      }
    });

    test('blackIce leads with the precise term ブラックアイスバーン', () {
      final a = RoadSurfaceState.blackIce.announcement!;
      expect(a.termJa, 'ブラックアイスバーン');
      expect(a.jaSpokenText, startsWith('ブラックアイスバーン'));
      // Certainty is GRADED (JAF's own 可能性 phrasing), never asserted —
      // the classification is an inference, not a surface measurement.
      expect(a.jaSpokenText, contains('おそれ'));
      // Provenance-neutral: reachable during visible snowfall, so it must
      // NOT claim the road looks wet.
      expect(a.jaSpokenText, isNot(contains('濡れて見え')));
      expect(a.enSpokenText.toLowerCase(), contains('black ice'));
      expect(a.enSpokenText.toLowerCase(), contains('frozen'));
    });

    test(
        'invisibleBlackIceAnnouncement carries the looks-wet fact, graded, '
        'with the verbatim JAF entry', () {
      final a = invisibleBlackIceAnnouncement;
      expect(a.jaSpokenText, startsWith('ブラックアイスバーン'));
      // The load-bearing invisible-ice fact: the road LOOKS merely wet.
      expect(a.jaSpokenText, contains('濡れて見え'));
      // ...but still graded (おそれ), mirroring the JAF source's 可能性.
      expect(a.jaSpokenText, contains('おそれ'));
      expect(a.enSpokenText.toLowerCase(), contains('look'));
      expect(
        identical(
          a.vocabulary,
          jafAuthoritativeData[JapaneseSnowSurfaceClass.blackIceBahn],
        ),
        isTrue,
      );
    });

    test(
        'general blackIce variant carries NO vocabulary entry — the JAF '
        'verbatim advisory opens with the looks-wet description, which is '
        'false during visible snowfall', () {
      final a = RoadSurfaceState.blackIce.announcement!;
      expect(a.vocabulary, isNull);
      // The JAF source text this guards against surfacing on the wrong
      // path really does open with the looks-wet claim:
      final jaf = jafAuthoritativeData[JapaneseSnowSurfaceClass.blackIceBahn]!;
      expect(jaf.safeDrivingResponseJa, contains('濡れたアスファルト'));
    });

    test('invisible variant carries the JAF entry with VERBATIM advisory', () {
      final a = invisibleBlackIceAnnouncement;
      final jaf = jafAuthoritativeData[JapaneseSnowSurfaceClass.blackIceBahn]!;
      // Byte-identity to the vocabulary package's verbatim-relay-bound
      // field — the announcement must relay, never paraphrase, this text.
      expect(identical(a.vocabulary, jaf), isTrue);
      expect(a.vocabulary!.safeDrivingResponseJa, jaf.safeDrivingResponseJa);
      expect(a.vocabulary!.authoritativeSource, 'JAF');
      expect(a.vocabulary!.sourceUrl, isNotNull);
    });

    test('compactedSnow and slush map to their JAF vocabulary classes', () {
      final compacted = RoadSurfaceState.compactedSnow.announcement!;
      expect(compacted.termJa, '圧雪');
      expect(
        identical(
          compacted.vocabulary,
          jafAuthoritativeData[JapaneseSnowSurfaceClass.compactedSnow],
        ),
        isTrue,
      );

      final slush = RoadSurfaceState.slush.announcement!;
      expect(slush.termJa, 'シャーベット');
      expect(
        identical(
          slush.vocabulary,
          jafAuthoritativeData[JapaneseSnowSurfaceClass.slush],
        ),
        isTrue,
      );
    });

    test('non-snow-vocabulary surfaces carry no term / vocabulary', () {
      expect(RoadSurfaceState.wet.announcement!.termJa, isNull);
      expect(RoadSurfaceState.wet.announcement!.vocabulary, isNull);
      expect(RoadSurfaceState.standingWater.announcement!.termJa, isNull);
      expect(RoadSurfaceState.standingWater.announcement!.vocabulary, isNull);
    });

    test(
        'HER Akita radiative-frost morning: classification-to-announcement '
        'end-to-end names black ice precisely', () {
      // +2 °C, 70% RH, clear — the bond-#3 founding scenario. The classifier
      // now detects black ice; the announcement must NAME it.
      final condition = WeatherCondition(
        precipType: PrecipitationType.none,
        intensity: PrecipitationIntensity.none,
        temperatureCelsius: 2.0,
        visibilityMeters: 10000,
        windSpeedKmh: 5,
        humidityRH: 70,
        timestamp: DateTime.utc(2026, 1, 15, 6, 30),
      );
      final surface = RoadSurfaceState.fromCondition(condition);
      expect(surface, RoadSurfaceState.blackIce);
      expect(surface.announcement!.termJa, 'ブラックアイスバーン');
    });
  });
}
