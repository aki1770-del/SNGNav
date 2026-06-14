# Changelog

## 0.1.0 — 2026-06-14 — Initial extraction

- Initial release of the MET Norway hourly-forecast **source** for the
  [`pretrip_decision_advisor`](https://pub.dev/packages/pretrip_decision_advisor)
  contract, extracted verbatim from the SNGNav app's
  `MetNorwayHourlyForecastProvider` with no behaviour change.
- Fetches the MET Norway `locationforecast/2.0/compact` product (GLOBAL —
  serves a Nagoya commute as well as a Tromsø one) and maps the FULL hourly
  timeseries into the contract's `WeatherForecast` measurement.
- Emits a **measurement** (`WeatherForecast`). The sibling
  `condition_aggregator_met_norway` emits a **warning** (`Advisory`) from the
  same publisher — see README "Measurement vs warning".
- Honesty rules carried verbatim from the source and stated in the README:
  - visibility is NEVER estimated — the compact product carries none, so
    `visibilityMeters` is ALWAYS null;
  - road-surface (`estimatedRoadCondition`) is ALWAYS null — sky-state is not
    surface-state;
  - slices without a `next_1_hours` block (the 6-hourly tail) are skipped,
    never interpolated;
  - a slice missing `air_temperature` is skipped, never guessed;
  - a missing `meta.updated_at` returns null rather than inventing an issue
    time (the advisor's staleness chip depends on it being real);
  - all fetch/parse failures surface as `MetNorwayForecastException` or
    `null`; nothing is fabricated.
- MET Norway terms honoured: an identifying `User-Agent` is required (empty UA
  is rejected before any request) and coordinates are truncated to 4 decimals
  (publisher cache-friendliness AND a privacy posture — the driver's sub-11 m
  position is not transmitted).
- Public API: `MetNorwayHourlyForecastProvider` (+ `.withClient` for test
  injection), the top-level `mapLocationForecastToWeatherForecast` mapper for
  direct-call testing, `MetNorwayForecastException`, and the
  `kMetNorwayLocationForecastUrl` endpoint constant.
- Pure Dart. Runtime dependencies: `http` and `pretrip_decision_advisor`.
- Tests: 11, covering the mapper against a REAL captured Nagoya response
  (fetched live 2026-06-12), the honesty rules, the HTTP request shape via a
  mocked client, and an end-to-end map → `SnowAwarePretripAdvisor` verdict.
- Data license: MET Norway forecast data is © MET Norway, **CC BY 4.0**;
  attribution is REQUIRED at the consumer-facing surface (see README).
