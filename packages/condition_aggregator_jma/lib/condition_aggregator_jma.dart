/// condition_aggregator_jma — JMA (Japan Meteorological Agency) adapter
/// for the `condition_aggregator` interface.
///
/// Fetches live Japanese winter-snow advisories (大雪 / 暴風雪 / 着雪)
/// for a lat/lon point and returns them as source-neutral [Advisory]
/// records.
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
/// path (0.2.0).** The provider resolves the caller's lat/lon to a
/// snow-zone prefecture (office) code, fetches the single small
/// `https://www.jma.go.jp/bosai/warning/data/warning/{areacode}.json`,
/// parses the current in-force warnings, and surfaces the
/// winter-snow-class advisories (大雪警報 / 大雪注意報 / 暴風雪警報 /
/// 着雪注意報) as source-neutral `Advisory` records to the aggregator.
///
/// 0.2.0 replaces the 0.1.x atom-feed + per-report-XML path, which had
/// a window / scroll-off false-negative (a still-in-force warning that
/// was last re-issued before the feed window opens scrolled off and
/// was silently missed). The windowless JSON always reflects the
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
/// Driver-facing loom: when JMA has issued a 大雪 / 暴風雪 / 着雪
/// advisory for the driver's current point in Japan, the integrator
/// HMI surfaces a typed `Advisory` event with severity / certainty /
/// urgency / area / effective / expires normalized at the boundary,
/// with JMA's exact wording preserved verbatim per Article 17 (β)
/// verbatim-relay discipline. The driver always drives.
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
        kJmaWarningJsonMaxBytes;
export 'src/jma_advisory_mapper.dart'
    show
        JmaWarningRecord,
        mapJmaWarningToAdvisory,
        parseJmaWarningJson,
        kJmaSnowWarningCodes,
        kJmaSnowAdvisoryEventNames,
        kJmaPrefectureBoundingBoxes,
        kJmaPrefectureNames,
        jmaPrefectureName,
        prefectureCodeForPoint;
