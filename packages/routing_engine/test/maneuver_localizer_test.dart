import 'package:routing_engine/src/maneuver_localizer.dart';
import 'package:test/test.dart';

void main() {
  group('ManeuverLocalizer — Japanese (HER default locale)', () {
    String ja(String type, {String name = ''}) => ManeuverLocalizer.localize(
      language: 'ja-JP',
      type: type,
      streetName: name,
    );

    test('turns onto a named road read as "…方面へ〜"', () {
      expect(ja('left', name: '国道153号'), '国道153号方面へ左折');
      expect(ja('right', name: '国道153号'), '国道153号方面へ右折');
      expect(ja('sharp_left', name: '県道1号'), '県道1号方面へ鋭角に左折');
      expect(ja('sharp_right', name: '県道1号'), '県道1号方面へ鋭角に右折');
      expect(ja('slight_left', name: '本町通'), '本町通方面へ斜め左方向');
      expect(ja('slight_right', name: '本町通'), '本町通方面へ斜め右方向');
    });

    test('turns without a road name read as the bare direction', () {
      expect(ja('left'), '左折');
      expect(ja('right'), '右折');
      expect(ja('sharp_left'), '鋭角に左折');
      expect(ja('slight_right'), '斜め右方向');
    });

    test('sharp turns preserve the tightness cue and never use 大きく (wide)', () {
      // 大きく reads as a wide/GENTLE arc — the inverse severity of a sharp
      // turn; a driver would carry too much speed into a hairpin on snow.
      for (final t in ['sharp_left', 'sharp_right']) {
        expect(ja(t), isNot(ja(t.replaceFirst('sharp_', ''))),
            reason: 'sharpness must not be silently discarded');
        expect(ja(t), contains('鋭角'));
        expect(ja(t), isNot(contains('大きく')));
        expect(ja(t, name: '県道1号'), isNot(contains('大きく')));
      }
    });

    test('depart / straight travel "on" the road → "…を〜"', () {
      expect(ja('depart', name: '栄駅前'), '栄駅前を出発');
      expect(ja('depart'), '出発');
      expect(ja('straight', name: '国道153号'), '国道153号を直進');
      expect(ja('straight'), '直進');
    });

    test('merge / roundabout / ramp / u-turn / arrive', () {
      expect(ja('merge', name: '国道153号'), '国道153号に合流');
      expect(ja('merge'), '合流');
      expect(ja('roundabout_enter', name: '駅前通'), 'ロータリーに入り駅前通方面へ進む');
      expect(ja('roundabout_enter'), 'ロータリーに入る');
      expect(ja('ramp_right', name: '東名'), '東名方面へ右側の分岐を進む');
      expect(ja('ramp_left'), '左側の分岐を進む');
      expect(ja('u_turn_left'), 'Uターン');
      expect(ja('arrive'), '目的地に到着');
    });

    test('roundabout exit ordinal reaches the instruction (multi-exit safety)', () {
      String jaExit(String type, int exit, {String name = ''}) =>
          ManeuverLocalizer.localize(
            language: 'ja-JP',
            type: type,
            streetName: name,
            roundaboutExit: exit,
          );
      expect(jaExit('roundabout_enter', 3), 'ロータリーに入り3番目の出口を出る');
      expect(
        jaExit('roundabout_enter', 2, name: '国道153号'),
        'ロータリーに入り2番目の出口で国道153号方面へ進む',
      );
      // Exit 0 / absent falls back to the ordinal-less form.
      expect(jaExit('roundabout_enter', 0), 'ロータリーに入る');
    });

    test('roundabout exit type', () {
      expect(ja('roundabout_exit'), 'ロータリーを出る');
      expect(ja('roundabout_exit', name: '本町通'), '本町通方面へロータリーを出る');
    });

    test('side-less ramp never fabricates a direction', () {
      expect(ja('ramp'), '分岐に進む');
      expect(ja('ramp', name: '東名'), '東名方面へ進む');
      expect(ja('ramp'), isNot(contains('右')));
      expect(ja('ramp'), isNot(contains('左')));
    });

    test('proceed (unknown geometry) defers to the road, never fabricates 直進', () {
      expect(ja('proceed'), '道なりに進む');
      expect(ja('proceed'), isNot(contains('直進')));
    });

    test('OSRM continue/new-name aliases fold into 直進', () {
      expect(ja('continue', name: '国道1号'), '国道1号を直進');
      expect(ja('new name'), '直進');
    });
  });

  group('ManeuverLocalizer — graceful degradation (never a wrong turn)', () {
    test('unknown type in Japanese degrades to the English fallback', () {
      final out = ManeuverLocalizer.localize(
        language: 'ja-JP',
        type: 'some_exotic_type',
        streetName: 'X Road',
        englishFallback: () => 'ENGLISH-FALLBACK',
      );
      expect(out, 'ENGLISH-FALLBACK');
    });

    test('unknown type with no fallback uses the built-in English baseline', () {
      expect(
        ManeuverLocalizer.localize(language: 'ja-JP', type: 'fork', streetName: 'Main St'),
        'Fork onto Main St',
      );
    });

    test('non-Japanese language uses the fallback verbatim (no regression)', () {
      final out = ManeuverLocalizer.localize(
        language: 'en-US',
        type: 'left',
        streetName: 'Main St',
        englishFallback: () => 'Left onto Main St',
      );
      expect(out, 'Left onto Main St');
    });

    test('language-tag variants all resolve to Japanese', () {
      for (final tag in ['ja', 'ja-JP', 'ja_JP', 'JA', 'ja-Hira-JP']) {
        expect(
          ManeuverLocalizer.localize(language: tag, type: 'left', streetName: '国道1号'),
          '国道1号方面へ左折',
          reason: 'tag "$tag" should localize to Japanese',
        );
      }
      expect(ManeuverLocalizer.supports('ja-JP'), isTrue);
      expect(ManeuverLocalizer.supports('en'), isFalse);
    });

    test('a blank/whitespace street name is treated as unnamed', () {
      expect(
        ManeuverLocalizer.localize(language: 'ja-JP', type: 'left', streetName: '   '),
        '左折',
      );
    });
  });
}
