// Minimal example for japanese_snow_vocabulary.
//
// Demonstrates lookup of authoritative JAF (日本自動車連盟) data for
// each Japanese snow surface class. The taxonomy distinguishes
// アイスバーン / ブラックアイスバーン / 雪道 / 圧雪 / シャーベット /
// 凍結 — six culturally-load-bearing JP terms for winter road
// conditions. JAF citations are surfaced where captured.

import 'package:japanese_snow_vocabulary/japanese_snow_vocabulary.dart';

void main() {
  for (final surface in JapaneseSnowSurfaceClass.values) {
    final entry = jafAuthoritativeData[surface];
    if (entry == null) continue;
    print('${entry.termJa} (${entry.termRomaji}) — ${entry.labelEn}');
    if (entry.authoritativeSource != null) {
      print('  Source: ${entry.authoritativeSource}');
    }
    if (entry.safeDrivingResponseJa != null) {
      print('  推奨: ${entry.safeDrivingResponseJa}');
    }
  }
}
