import 'japanese_snow_surface_class.dart';
import 'japanese_snow_vocabulary_entry.dart';

/// Canonical map from [JapaneseSnowSurfaceClass] case to its
/// vocabulary entry.
///
/// **All six entries fully populated at 0.2.0** with verbatim JAF
/// (Japan Automobile Federation) authoritative-source citations.
/// Three entries ([JapaneseSnowSurfaceClass.iceBahn],
/// [JapaneseSnowSurfaceClass.blackIceBahn],
/// [JapaneseSnowSurfaceClass.snowyRoad]) carry citations from the JAF
/// snow-attention page (extracted 2026-05-07). Three entries
/// ([JapaneseSnowSurfaceClass.compactedSnow],
/// [JapaneseSnowSurfaceClass.slush],
/// [JapaneseSnowSurfaceClass.surfaceFrozen]) carry citations from
/// JAF Training columns + JAF FAQ148 (data-filled at 0.2.0 from a
/// deeper authoritative-source review captured 2026-05-07).
///
/// **Verbatim-relay binding**: every `safeDrivingResponseJa` value
/// below is byte-identical to its JAF source page at extraction time
/// (2026-05-07). Mutating these literals is forbidden; the package's
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
    regionFrequency:
        'snow-prone regions; refreezes overnight after '
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
    regionFrequency:
        'general snow-fall conditions across all '
        'snow-prone regions',
  ),

  // --- 圧雪 (FULL data 0.2.0; primary source = JAF Training) ---
  JapaneseSnowSurfaceClass.compactedSnow: JapaneseSnowVocabularyEntry(
    termJa: '圧雪',
    termRomaji: 'assetsu',
    labelEn: 'compacted snow',
    authoritativeSource: 'JAF',
    sourceUrl: 'https://jaf-training.jp/column/snow-drive/',
    // Verbatim from JAF Training snow-drive column. Primary
    // safe-driving-response sentence preserved byte-identical.
    safeDrivingResponseJa:
        'この状態は、車の走行跡（わだち）があり、新雪と比べて走りやすい路面ですが、'
        '交差点などの車の往来が多い場所では圧雪が磨かれてアイスバーンになりやすいので、'
        '急のつく操作は避けましょう。',
    safeDrivingResponseEn:
        'This surface has vehicle tracks (wadachi) and is easier to '
        'drive on than fresh snow; however, in places with heavy '
        'traffic such as intersections, the compacted snow gets '
        'polished and tends to become icy hardpack, so abrupt '
        'operations should be avoided.',
    regionFrequency:
        'snow-prone regions; common state across all '
        'winter-driving scenarios; transitions to icy hardpack at '
        'intersections and high-traffic locations',
  ),

  // --- シャーベット (FULL data 0.2.0; single-publisher coverage) ---
  JapaneseSnowSurfaceClass.slush: JapaneseSnowVocabularyEntry(
    termJa: 'シャーベット',
    termRomaji: 'shabetto',
    labelEn: 'slush',
    authoritativeSource: 'JAF',
    sourceUrl: 'https://jaf-training.jp/column/snow-drive/',
    // Verbatim from JAF Training snow-drive column. Single-publisher
    // source-breadth (JAF Training only); see `KNOWN_LIMITATIONS.md`
    // for honest-class disclosure.
    safeDrivingResponseJa:
        '新雪や圧雪と違い、雪ならではのリスクは低くなりますが、'
        '場所によってはシャーベットの下が凍結している可能性があるので、油断は禁物です。',
    safeDrivingResponseEn:
        'Unlike fresh snow or compacted snow, the snow-specific risks '
        'are lower; however, in some places the slush may have frozen '
        'surface beneath it, so vigilance must not be relaxed.',
    regionFrequency:
        'spring-thaw conditions; rising-temperature '
        'phase; covered-frozen-substrate hazard noted by JAF '
        '(single-publisher coverage at 0.2.0; see KNOWN_LIMITATIONS.md)',
  ),

  // --- 凍結 (FULL data 0.2.0; primary source = JAF FAQ148) ---
  JapaneseSnowSurfaceClass.surfaceFrozen: JapaneseSnowVocabularyEntry(
    termJa: '凍結',
    termRomaji: 'kettou',
    labelEn: 'frozen surface',
    authoritativeSource: 'JAF',
    sourceUrl:
        'https://jaf.or.jp/common/kuruma-qa/category-natural/'
        'subcategory-snow/faq148',
    // Verbatim from JAF FAQ148. Two source sentences joined with
    // ideographic space; byte-identical to the JAF page at extraction
    // time.
    safeDrivingResponseJa:
        '雪が溶けて再び凍った路面。とても滑りやすく、慎重に運転を。'
        '日なたでは、解けた氷が水膜となって浮かぶと、さらに滑りやすくなっています。'
        '　'
        '事故の起こりやすい場所として、もっとも危険なのが、'
        '風通しのよい橋の上や陸橋、そしてトンネルの出入り口付近です。'
        '他よりも気温が低いため、路面が凍結しやすく、大変危険です。'
        'そのような場所では、手前で十分にスピードを落とし、慎重に走行する必要があります。',
    safeDrivingResponseEn:
        'A road surface where snow has melted and refrozen. Very '
        'slippery; drive carefully. In sunny spots, when melted ice '
        'floats as a water film, the surface becomes even more '
        'slippery. The most dangerous accident-prone locations are '
        'on bridges and overpasses with good airflow, and near tunnel '
        'entrances. Because temperatures there are lower than '
        'elsewhere, the road surface freezes easily and is very '
        'dangerous. In such places, you must reduce speed sufficiently '
        'in advance and drive carefully.',
    regionFrequency:
        'bridges, overpasses, tunnel entrances; cold '
        'dawn/dusk/night hours; post-rain-cold and post-thaw-refreeze '
        'conditions',
  ),
};
