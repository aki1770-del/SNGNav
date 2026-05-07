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

    test('JAF source URL is byte-identical across all populated entries',
        () {
      const expected = 'https://jaf.or.jp/common/attention/snow';
      for (final c in const [
        JapaneseSnowSurfaceClass.iceBahn,
        JapaneseSnowSurfaceClass.blackIceBahn,
        JapaneseSnowSurfaceClass.snowyRoad,
      ]) {
        expect(jafAuthoritativeData[c]!.sourceUrl, expected);
      }
    });

    test('authoritativeSource label is the literal "JAF" for all populated',
        () {
      for (final c in const [
        JapaneseSnowSurfaceClass.iceBahn,
        JapaneseSnowSurfaceClass.blackIceBahn,
        JapaneseSnowSurfaceClass.snowyRoad,
      ]) {
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
