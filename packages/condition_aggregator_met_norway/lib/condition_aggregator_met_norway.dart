/// condition_aggregator_met_norway — MET Norway (Meteorologisk institutt)
/// adapter for the `condition_aggregator` interface.
///
/// Wraps the public MET Norway locationforecast/2.0/compact endpoint
/// (`https://api.met.no/weatherapi/locationforecast/2.0/compact`) and
/// maps the next-hour forecast slice for a requested point to a
/// source-neutral `Advisory` typed event at the adapter boundary.
///
/// Phase: explore — v0.0.1.
///
/// HER-trace (≤4-hop) end-to-end:
///   MET Norway locationforecast feed
///     → `MetNorwayAdvisoryProvider` (this package)
///     → `AdvisoryAggregator` typed merge
///     → integrator HMI surfaces advisory to the driver in unexpected
///       snow on Norwegian / Nordic-region roads.
/// 4 hops.
///
/// Source attribution: `AdvisorySource.metNorway`. The parent
/// `condition_aggregator` interface already carries the Norway member
/// + the verbatim CC-BY-4.0 attribution string via
/// `AdvisorySourceAttribution.attributionString`. MET Norway data is
/// licensed CC-BY-4.0 — attribution is REQUIRED by the license at the
/// consumer-facing surface, not optional. See README "License +
/// attribution" for binding implications.
///
/// Endpoint discovery (2026-05-24): the road-surface forecast
/// product `roadforecast/2.0` documented at
/// `https://api.met.no/weatherapi/roadforecast/2.0/documentation`
/// returns HTTP 404 at curl — the product is not publicly reachable.
/// v0.0.1 ships against `locationforecast/2.0/compact` (HTTP 200,
/// ~37 KB GeoJSON Point) as the canonical MET Norway weather endpoint.
/// Road-surface direct mapping is queued for v0.0.2+ if a public
/// road-product endpoint becomes available.
library;

export 'src/met_norway_advisory_provider.dart'
    show
        MetNorwayAdvisoryProvider,
        MetNorwayHttpException,
        MetNorwayParseException,
        MetNorwayConfigurationException,
        mapLocationForecastResponseToAdvisory,
        kDefaultMetNorwayLocationForecastUrl,
        kDefaultMetNorwayHeavyPrecipitationMmPerHour,
        kDefaultMetNorwayFreezingTemperatureCelsius,
        kDefaultMetNorwayClearSkyCloudPercentMax,
        kMetNorwaySaturatedHumidityPercent;
