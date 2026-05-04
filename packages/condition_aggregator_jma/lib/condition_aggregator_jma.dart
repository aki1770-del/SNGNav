/// condition_aggregator_jma — JMA (Japan Meteorological Agency) adapter
/// for the condition_aggregator interface.
///
/// **Status: deployed via direct-Dart-XML-parse path.** The provider
/// fetches the JMA disaster-info atom feed
/// (`https://www.data.jma.go.jp/developer/xml/feed/extra_l.xml` by
/// default), filters to the prefecture-class
/// 気象警報・注意報 reports (e.g. `VPWW54`), parses each linked report
/// XML directly with the canonical Dart `xml` package, and surfaces
/// the winter-snow-class advisories (大雪警報 / 大雪注意報 /
/// 暴風雪警報 / 暴風雪注意報 / 着雪注意報) as source-neutral
/// `Advisory` records to the aggregator.
///
/// The jmaxml engagement-shape election (alpha/beta/gamma) for an
/// upstream typed-binding remains a separate open question (OQ-1).
/// 0.1.0 does NOT block on that election — the direct-parse path
/// is sufficient for deploy.
///
/// HER-trace (≤4-hop) end-to-end:
///   JMA disaster-info atom feed (気象庁防災情報XML)
///     → `JmaAdvisoryProvider` (this adapter; HTTP + XML parse + filter)
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
///   JMA disaster-info atom feed
///     → `JmaAdvisoryProvider` (this package; direct-parse)
///     → `AdvisoryAggregator` (merges across publishers including NWS)
///     → integrator HMI / driver
library;

export 'src/jma_advisory_provider.dart'
    show
        JmaAdvisoryProvider,
        JmaAdvisoryFetchException,
        kDefaultJmaAtomFeedUrl,
        kJmaPrefectureWarningReportTitles,
        kJmaFetchWallClockBudget,
        kJmaAtomFeedMaxBytes,
        kJmaReportXmlMaxBytes;
export 'src/jma_advisory_mapper.dart'
    show
        JmaForecastRecord,
        mapJmaForecastToAdvisory,
        kJmaSnowAdvisoryEventNames,
        kJmaPrefectureBoundingBoxes,
        prefectureCodeForPoint,
        parseJmaAtomFeed,
        parseJmaReportXml,
        JmaAtomEntry;
