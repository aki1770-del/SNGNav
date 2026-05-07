import 'japanese_snow_surface_class.dart';
import 'japanese_snow_vocabulary_entry.dart';

/// Canonical map from [JapaneseSnowSurfaceClass] case to its
/// vocabulary entry.
///
/// **Three of six entries** are fully populated at 0.1.0 with verbatim
/// JAF (Japan Automobile Federation) authoritative-source citations:
/// [JapaneseSnowSurfaceClass.iceBahn],
/// [JapaneseSnowSurfaceClass.blackIceBahn],
/// [JapaneseSnowSurfaceClass.snowyRoad].
///
/// The remaining three entries
/// ([JapaneseSnowSurfaceClass.compactedSnow],
/// [JapaneseSnowSurfaceClass.slush],
/// [JapaneseSnowSurfaceClass.surfaceFrozen]) carry only the
/// taxonomic surface (term + romaji + English label) at 0.1.0;
/// the five authoritative fields are `null`. They will be populated
/// at 0.2.0 once a deeper review of authoritative sources (Hokkaido
/// regional bureau / NEXCO / JARTIC / prefectural police) lands.
///
/// **Verbatim-relay binding**: every non-null `safeDrivingResponseJa`
/// value below is byte-identical to the JAF source page extracted at
/// <https://jaf.or.jp/common/attention/snow> on 2026-05-07. Mutating
/// these literals is forbidden; the package's
/// `verbatim_citation_test.dart` regression-guards each string.
const Map<JapaneseSnowSurfaceClass, JapaneseSnowVocabularyEntry>
    jafAuthoritativeData = {
  // --- アイスバーン (FULL data 0.1.0) ---
  JapaneseSnowSurfaceClass.iceBahn: JapaneseSnowVocabularyEntry(
    termJa: 'アイスバーン',
    termRomaji: 'aisubaan',
    labelEn: 'icy hardpack',
    authoritativeSource: 'JAF',
    sourceUrl: 'https://jaf.or.jp/common/attention/snow',
    // Verbatim from JAF. Joined with U+3000 ideographic space between
    // the two source sentences so the byte-identical citation is
    // preserved as a single field while remaining round-trippable to
    // the source page.
    safeDrivingResponseJa:
        'アイスバーンは雪道以上に滑るので要注意。'
        '　'
        '道路脇の道路との境の矢印や反射板のポールを見当に走行する。',
    safeDrivingResponseEn:
        'Icy hardpack is more slippery than a general snow road; '
        'caution is required. Use roadside boundary arrows and '
        'reflector poles as visual reference while driving.',
    regionFrequency: 'snow-prone regions; refreezes overnight after '
        'daytime melt or post-rain cold',
  ),

  // --- ブラックアイスバーン (FULL data 0.1.0) ---
  JapaneseSnowSurfaceClass.blackIceBahn: JapaneseSnowVocabularyEntry(
    termJa: 'ブラックアイスバーン',
    termRomaji: 'burakku-aisubaan',
    labelEn: 'black ice',
    authoritativeSource: 'JAF',
    sourceUrl: 'https://jaf.or.jp/common/attention/snow',
    // Verbatim from JAF. Three source sentences joined with
    // ideographic spaces; byte-identical to the JAF page at
    // extraction time.
    safeDrivingResponseJa:
        '一見すると濡れたアスファルト路面のように黒く見えるのに、'
        '実は表面が凍りついている路面「ブラックアイスバーン」になる可能性'
        '　'
        '風通しのよい橋の上や陸橋、トンネル出入口付近がもっとも危険'
        '　'
        '滑ることを前提にした慎重な運転（予測運転）が必要。'
        '発進、停止、カーブで「急」のつく動作は厳禁。',
    safeDrivingResponseEn:
        'Surfaces that look like wet black asphalt may actually be '
        'frozen black ice. Bridges, overpasses, and tunnel '
        'entrances with good airflow are most dangerous. Anticipatory '
        'cautious driving assuming slippage is required; abrupt '
        'starts, stops, and turns are strictly forbidden.',
    regionFrequency:
        'bridges, overpasses, tunnel entrances; cold + post-thaw '
        'refreeze conditions',
  ),

  // --- 雪道 (FULL data 0.1.0) ---
  JapaneseSnowSurfaceClass.snowyRoad: JapaneseSnowVocabularyEntry(
    termJa: '雪道',
    termRomaji: 'yuki-michi',
    labelEn: 'snow road',
    authoritativeSource: 'JAF',
    sourceUrl: 'https://jaf.or.jp/common/attention/snow',
    // Verbatim from JAF. Three source sentences joined with
    // ideographic spaces; byte-identical.
    safeDrivingResponseJa:
        '雪道をノーマルタイヤで走行することは極めて危険なので、'
        'スタッドレスタイヤやチェーンを必ず装着する。'
        '　'
        '急な車線変更、急ブレーキは厳禁。'
        '先行車との車間距離を多めにとる。'
        '　'
        '発進時はアクセルをじわりと踏み込み、ゆっくり発進する。',
    safeDrivingResponseEn:
        'Driving a snow road on normal tires is extremely dangerous; '
        'studless tires or chains must always be installed. Abrupt '
        'lane changes and hard braking are strictly forbidden; '
        'increase distance to the vehicle ahead. On start, press the '
        'accelerator gently and pull away slowly.',
    regionFrequency: 'general snow-fall conditions across all '
        'snow-prone regions',
  ),

  // --- 圧雪 (DEFERRED 0.2.0) ---
  JapaneseSnowSurfaceClass.compactedSnow: JapaneseSnowVocabularyEntry(
    termJa: '圧雪',
    termRomaji: 'assetsu',
    labelEn: 'compacted snow',
    // authoritativeSource / sourceUrl / safeDrivingResponse* /
    // regionFrequency intentionally left null at 0.1.0 per
    // honest-disclosure pattern. Populated at 0.2.0.
  ),

  // --- シャーベット (DEFERRED 0.2.0) ---
  JapaneseSnowSurfaceClass.slush: JapaneseSnowVocabularyEntry(
    termJa: 'シャーベット',
    termRomaji: 'shabetto',
    labelEn: 'slush',
  ),

  // --- 凍結 (DEFERRED 0.2.0) ---
  JapaneseSnowSurfaceClass.surfaceFrozen: JapaneseSnowVocabularyEntry(
    termJa: '凍結',
    termRomaji: 'kettou',
    labelEn: 'frozen surface',
  ),
};
