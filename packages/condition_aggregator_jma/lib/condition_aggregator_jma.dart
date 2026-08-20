/// condition_aggregator_jma — JMA (Japan Meteorological Agency) adapter
/// for the `condition_aggregator` interface.
///
/// Fetches live Japanese weather warnings — the winter-snow classes
/// (大雪 / 暴風雪 / 着雪) plus, from 0.4.0, the downpour / typhoon-wind /
/// thunder / fog turmoil classes (大雨 / 暴風・強風 / 雷 / 濃霧) — for a
/// lat/lon point and returns them as source-neutral [Advisory] records.
///
/// Usage: construct [JmaAdvisoryProvider], `await init()` once, then call
/// `fetchActiveAdvisoriesAtPoint(latitude:, longitude:)`. It does real
/// HTTPS I/O against the public JMA feed, so wrap calls in a try/catch on
/// [JmaAdvisoryFetchException]. See the README and `example/main.dart`.
///
/// ```dart
/// final jma = JmaAdvisoryProvider(userAgent: '(myapp, https://example.com)');
/// await jma.init();
/// final advisories = await jma.fetchActiveAdvisoriesAtPoint(
///   latitude: 39.7186, longitude: 140.1024, // Akita
/// );
/// ```
///
/// ---
///
/// **Status: deployed via the windowless per-prefecture warning JSON
/// path.** The provider resolves the caller's lat/lon to **every**
/// catalogued snow-zone prefecture (office) code whose bounding box
/// contains the point — one for an interior point, or the full
/// containing set at a border (the boxes overlap along every shared
/// border) — fetches each prefecture's
/// `https://www.jma.go.jp/bosai/warning/data/warning/{areacode}.json`
/// **concurrently**, parses the current in-force warnings, and surfaces
/// the **deduplicated union** of the surfaced warning classes
/// (`kJmaWarningCodes`: the winter-snow classes 大雪警報 / 大雪注意報 /
/// 暴風雪警報 / 着雪注意報 / 大雪特別警報 / 暴風雪特別警報 plus the
/// 0.4.0 turmoil classes 大雨特別警報 / 大雨危険警報 / 大雨警報 /
/// 大雨注意報 / 暴風特別警報 / 暴風警報 / 強風注意報 / 雷注意報 /
/// 濃霧注意報) as source-neutral `Advisory` records to the aggregator.
/// This is the conservative,
/// over-warn handling of border ambiguity (0.3.0): a border driver
/// never misses a neighbouring prefecture's warning because the resolver
/// guessed a single side. When the union is non-empty but a containing
/// prefecture could not be fetched, the partial read is signalled in-band
/// by a synthetic, low-severity incomplete-read notice naming the
/// unreachable prefecture(s) — a partial read is never presented as a
/// complete all-clear. See CHANGELOG 0.3.0.
///
/// The windowless JSON replaced the 0.1.x atom-feed + per-report-XML
/// path, which had a window / scroll-off false-negative (a still-in-force
/// warning that was last re-issued before the feed window opens scrolled
/// off and was silently missed); the windowless JSON always reflects the
/// current in-force state. See CHANGELOG 0.2.0.
///
/// HER-trace (≤4-hop) end-to-end:
///   JMA windowless per-prefecture warning JSON (気象庁防災情報)
///     → `JmaAdvisoryProvider` (this adapter; HTTP + JSON parse + filter)
///     → `AdvisoryAggregator` typed merge with sibling adapters
///     → integrator HMI surfaces the advisory to the driver in
///       unexpected snow on a Japanese road.
/// 4 hops.
///
/// Driver-facing loom: when JMA has issued a surfaced-class warning —
/// 大雪 / 暴風雪 / 着雪 in winter, or 大雨 / 暴風・強風 / 雷 / 濃霧 in
/// sudden summer / typhoon turmoil — for the driver's current point in
/// Japan, the integrator HMI surfaces a typed `Advisory` event with
/// severity / certainty / urgency / area / effective / expires
/// normalized at the boundary, with JMA's exact wording preserved
/// verbatim per Article 17 (β) verbatim-relay discipline. The driver
/// always drives.
///
/// Composition:
///   JMA windowless per-prefecture warning JSON
///     → `JmaAdvisoryProvider` (this package; JSON parse)
///     → `AdvisoryAggregator` (merges across publishers including NWS)
///     → integrator HMI / driver
library;

export 'src/jma_advisory_provider.dart'
    show
        JmaAdvisoryProvider,
        JmaAdvisoryFetchException,
        kJmaWarningJsonBaseUrl,
        kJmaFetchWallClockBudget,
        kJmaWarningJsonMaxBytes,
        kJmaDefaultStaleFeedThreshold;
export 'src/jma_advisory_mapper.dart'
    show
        JmaWarningRecord,
        mapJmaWarningToAdvisory,
        buildIncompleteReadNotice,
        kJmaIncompleteReadEventClass,
        buildStaleFeedNotice,
        kJmaStaleFeedEventClass,
        JmaFeedSnapshot,
        parseJmaFeed,
        parseJmaWarningJson,
        kJmaWarningCodes,
        kJmaSnowWarningCodes,
        kJmaSnowAdvisoryEventNames,
        kJmaPrefectureBoundingBoxes,
        kJmaPrefectureNames,
        kJmaPrefectureNamesJa,
        jmaPrefectureName,
        jmaPrefectureNameJa,
        prefectureCodeForPoint,
        prefectureCodesForPoint;
