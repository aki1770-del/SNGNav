/// pretrip_source_met_norway — MET Norway locationforecast hourly-forecast
/// SOURCE for the `pretrip_decision_advisor` contract.
///
/// Fetches the MET Norway `locationforecast/2.0/compact` product (GLOBAL,
/// so it serves a Nagoya commute as well as a Tromsø one) and maps the FULL
/// hourly timeseries into the contract's [WeatherForecast] MEASUREMENT — the
/// raw observation an edge developer feeds to `pretrip_decision_advisor` to
/// build their own pre-trip "Before you drive" surface.
///
/// This package emits a MEASUREMENT ([WeatherForecast]). Its sibling
/// `condition_aggregator_met_norway` emits a WARNING (`Advisory`) from the
/// same publisher. See README "Measurement vs warning" for which to
/// `pub add` for which need.
///
/// Honesty rules are binding and live verbatim in the source + the README:
/// visibility is NEVER estimated (the compact product carries none →
/// `visibilityMeters` is ALWAYS null); a warning is never produced as a
/// number; an observation is valid for its departure hour only; a null
/// field is the driver's own judgement, never a fabricated hazard.
///
/// Coverage: the mapper SKIPS a timeseries slice it cannot honestly use (an
/// unparseable time, no `next_1_hours` — the 6-hourly tail —, or no
/// `air_temperature`). It never interpolates. Because [WeatherForecast]
/// carries no coverage member, a skipped slice used to be invisible: a hole
/// we made looked identical to an hour the publisher never issued. Use
/// [MetNorwayHourlyForecastProvider.fetchForecastWithCoverage] (or the
/// top-level [mapLocationForecastWithCoverage] if you already hold the JSON)
/// to see what was dropped and why ([MetNorwayMappingCoverage]);
/// `unexpectedDrops` counts only the drops that are NOT the publisher's
/// documented 6-hourly shape.
///
/// Service trace (driver in unexpected weather; ≤4 hops):
///   MET Norway locationforecast/2.0/compact feed
///     → `MetNorwayHourlyForecastProvider` (this package)
///     → `pretrip_decision_advisor` advisor (edge developer composes)
///     → integrator pre-trip surface warns the driver — and her family —
///       before she sets out.
///
/// Pure Dart. Only `http` and `pretrip_decision_advisor` runtime deps.
///
/// Credit: "Data from MET Norway" (<https://api.met.no/>). MET Norway
/// forecast data is dual-licensed under NLOD 2.0 AND CC BY 4.0; the
/// integrator surfaces the attribution wherever the data is shown (see
/// README).
library;

export 'src/met_norway_hourly_forecast.dart'
    show
        MetNorwayForecastException,
        MetNorwayForecastWithCoverage,
        MetNorwayHourlyForecastProvider,
        MetNorwayMappingCoverage,
        MetNorwaySliceDrop,
        kMetNorwayLocationForecastUrl,
        mapLocationForecastToWeatherForecast,
        mapLocationForecastWithCoverage;
