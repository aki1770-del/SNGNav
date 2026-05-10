import 'package:japanese_snow_vocabulary/japanese_snow_vocabulary.dart';
import 'package:test/test.dart';

/// Regression-guard for the verbatim-relay binding on JAF-cited
/// safe-driving-response strings.
///
/// Each test below compares the value carried in [jafAuthoritativeData]
/// against a byte-identical literal copy of the JAF source-page text.
/// If a future edit paraphrases or re-orders the authoritative
/// citation, these tests will fail. Do not loosen the literal
/// comparison: the binding is preserved at byte-identical granularity.
///
/// At 0.2.0 the regression-guard covers all six entries; the three
/// 0.2.0 data-fill entries (圧雪 / シャーベット / 凍結) draw from JAF
/// Training columns + JAF FAQ148 (additional URLs beyond the 0.1.0
/// JAF snow-attention page).
void main() {
  group('verbatim_citation_test — JAF byte-identical regression-guard', () {
    test('アイスバーン safeDrivingResponseJa is byte-identical', () {
      const expected =
          'アイスバーンは雪道以上に滑るので要注意。'
          '　'
          '道路脇の道路との境の矢印や反射板のポールを見当に走行する。';
      final entry = jafAuthoritativeData[JapaneseSnowSurfaceClass.iceBahn]!;
      expect(entry.safeDrivingResponseJa, expected);
    });

    test('ブラックアイスバーン safeDrivingResponseJa is byte-identical', () {
      const expected =
          '一見すると濡れたアスファルト路面のように黒く見えるのに、'
          '実は表面が凍りついている路面「ブラックアイスバーン」になる可能性'
          '　'
          '風通しのよい橋の上や陸橋、トンネル出入口付近がもっとも危険'
          '　'
          '滑ることを前提にした慎重な運転（予測運転）が必要。'
          '発進、停止、カーブで「急」のつく動作は厳禁。';
      final entry =
          jafAuthoritativeData[JapaneseSnowSurfaceClass.blackIceBahn]!;
      expect(entry.safeDrivingResponseJa, expected);
    });

    test('雪道 safeDrivingResponseJa is byte-identical', () {
      const expected =
          '雪道をノーマルタイヤで走行することは極めて危険なので、'
          'スタッドレスタイヤやチェーンを必ず装着する。'
          '　'
          '急な車線変更、急ブレーキは厳禁。'
          '先行車との車間距離を多めにとる。'
          '　'
          '発進時はアクセルをじわりと踏み込み、ゆっくり発進する。';
      final entry = jafAuthoritativeData[JapaneseSnowSurfaceClass.snowyRoad]!;
      expect(entry.safeDrivingResponseJa, expected);
    });

    test('圧雪 safeDrivingResponseJa is byte-identical', () {
      const expected =
          'この状態は、車の走行跡（わだち）があり、新雪と比べて走りやすい路面ですが、'
          '交差点などの車の往来が多い場所では圧雪が磨かれてアイスバーンになりやすいので、'
          '急のつく操作は避けましょう。';
      final entry =
          jafAuthoritativeData[JapaneseSnowSurfaceClass.compactedSnow]!;
      expect(entry.safeDrivingResponseJa, expected);
    });

    test('シャーベット safeDrivingResponseJa is byte-identical', () {
      const expected =
          '新雪や圧雪と違い、雪ならではのリスクは低くなりますが、'
          '場所によってはシャーベットの下が凍結している可能性があるので、油断は禁物です。';
      final entry = jafAuthoritativeData[JapaneseSnowSurfaceClass.slush]!;
      expect(entry.safeDrivingResponseJa, expected);
    });

    test('凍結 safeDrivingResponseJa is byte-identical', () {
      const expected =
          '雪が溶けて再び凍った路面。とても滑りやすく、慎重に運転を。'
          '日なたでは、解けた氷が水膜となって浮かぶと、さらに滑りやすくなっています。'
          '　'
          '事故の起こりやすい場所として、もっとも危険なのが、'
          '風通しのよい橋の上や陸橋、そしてトンネルの出入り口付近です。'
          '他よりも気温が低いため、路面が凍結しやすく、大変危険です。'
          'そのような場所では、手前で十分にスピードを落とし、慎重に走行する必要があります。';
      final entry =
          jafAuthoritativeData[JapaneseSnowSurfaceClass.surfaceFrozen]!;
      expect(entry.safeDrivingResponseJa, expected);
    });

    test('JAF source URL for 0.1.0 entries is byte-identical', () {
      const expected = 'https://jaf.or.jp/common/attention/snow';
      for (final c in const [
        JapaneseSnowSurfaceClass.iceBahn,
        JapaneseSnowSurfaceClass.blackIceBahn,
        JapaneseSnowSurfaceClass.snowyRoad,
      ]) {
        expect(jafAuthoritativeData[c]!.sourceUrl, expected);
      }
    });

    test('JAF Training snow-drive URL is byte-identical for 圧雪 + シャーベット', () {
      const expected = 'https://jaf-training.jp/column/snow-drive/';
      for (final c in const [
        JapaneseSnowSurfaceClass.compactedSnow,
        JapaneseSnowSurfaceClass.slush,
      ]) {
        expect(jafAuthoritativeData[c]!.sourceUrl, expected);
      }
    });

    test('JAF FAQ148 URL is byte-identical for 凍結', () {
      const expected =
          'https://jaf.or.jp/common/kuruma-qa/category-natural/'
          'subcategory-snow/faq148';
      expect(
        jafAuthoritativeData[JapaneseSnowSurfaceClass.surfaceFrozen]!.sourceUrl,
        expected,
      );
    });

    test('authoritativeSource label is the literal "JAF" for all entries', () {
      for (final c in JapaneseSnowSurfaceClass.values) {
        expect(jafAuthoritativeData[c]!.authoritativeSource, 'JAF');
      }
    });

    test('JA term characters are byte-identical for all six entries', () {
      expect(
        jafAuthoritativeData[JapaneseSnowSurfaceClass.iceBahn]!.termJa,
        'アイスバーン',
      );
      expect(
        jafAuthoritativeData[JapaneseSnowSurfaceClass.blackIceBahn]!.termJa,
        'ブラックアイスバーン',
      );
      expect(
        jafAuthoritativeData[JapaneseSnowSurfaceClass.snowyRoad]!.termJa,
        '雪道',
      );
      expect(
        jafAuthoritativeData[JapaneseSnowSurfaceClass.compactedSnow]!.termJa,
        '圧雪',
      );
      expect(
        jafAuthoritativeData[JapaneseSnowSurfaceClass.slush]!.termJa,
        'シャーベット',
      );
      expect(
        jafAuthoritativeData[JapaneseSnowSurfaceClass.surfaceFrozen]!.termJa,
        '凍結',
      );
    });
  });
}
