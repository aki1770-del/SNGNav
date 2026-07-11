# Changelog

## 0.2.2

- Widen the `pretrip_decision_advisor` constraint to `'>=0.5.0 <0.7.0'` so this
  package resolves against `pretrip_decision_advisor` 0.6.0 (which adds
  `HourHazard.unknown` — a trip with NO forecast no longer reports its peak
  hazard as `clear`). This package's `lib/` reads neither changed symbol, so
  0.6.0 is source-compatible; for a 0.x package a caret does not admit the next
  minor, so without the widen `^0.5.0` and 0.6.0 have an EMPTY intersection.

- **Take pretrip_decision_advisor ^0.5.0.** The previous `^0.4.0` pin silently
  excluded the 0.5.x line — hosted consumers of this adapter never received
  the black-ice window and route-corridor bridge-icing pre-trip warnings
  (橋は路面より先に凍結します) shipped there. No behavior change in this
  package itself; the constraint widening is the release.


## 0.2.1 — 2026-06-26 — Example no longer crashes on first run

- **Fix:** `example/main.dart` no longer crashes with an unhandled
  `MetNorwayForecastException: HTTP 403` when the placeholder User-Agent is
  unchanged. A developer copying the example verbatim previously hit an
  unhandled exception on first run, because MET Norway's terms reject the
  generic `your_app/1.0 contact@example.com` identifier. The example now
  detects the still-placeholder User-Agent (and also catches a live 403),
  prints the one-line guidance "MET Norway requires an identifying User-Agent:
  set it to your app + contact email, then re-run", runs an offline mapper demo
  so the shape is still visible, and exits cleanly (exit 0).
- **Library behaviour unchanged.** `MetNorwayHourlyForecastProvider` still
  throws its loud typed `MetNorwayForecastException` on a non-200 response; only
  the example's handling changed. No public API change.

## 0.2.0 — 2026-06-24 — Re-pin advisor to ^0.4.0 (catalog resolvability)

- Shifts the `pretrip_decision_advisor` requirement from the 0.2.x range to the
  0.4.x range; advisor 0.2.x/0.3.x are no longer supported by this version. This
  package's own public API is unchanged. Minor bump because the resolution
  requirement is consumer-affecting. The published `pretrip_decision_advisor`
  0.4.0 is live on pub.dev; the previous `^0.2.0` constraint was incompatible
  with it and blocked edge developers from `pub add`-ing this source alongside
  the current advisor in one project.
- **License unchanged from 0.1.1.** Package CODE license stays **BSD 3-Clause**;
  the MET Norway DATA license remains **dual-licensed** under the **Norwegian
  Licence for Open Government Data (NLOD) 2.0** AND **Creative Commons
  Attribution 4.0 International (CC BY 4.0)** as documented in the README.
  Attribution ("Data from MET Norway", source The Norwegian Meteorological
  Institute) is REQUIRED at the consumer-facing surface.
- Completed the MET Norway data-attribution correction across all
  consumer-facing surfaces (library dartdoc, src dartdoc, and example), not the
  README alone — credit is "Data from MET Norway", data dual-licensed NLOD 2.0 /
  CC BY 4.0.

## 0.1.1 — 2026-06-22 — License documentation correction

- **Docs-only; no behaviour, API, or dependency change.** Corrects the stated
  MET Norway DATA license in the README. The freely-available forecast data is
  **dual-licensed** (unless otherwise specified) under the **Norwegian Licence
  for Open Government Data (NLOD) 2.0** AND **Creative Commons Attribution 4.0
  International (CC BY 4.0)** — the previous README under-stated it as CC BY 4.0
  only.
- Uses MET Norway's verbatim suggested credit **"Data from MET Norway"**,
  credits **The Norwegian Meteorological Institute (MET Norway)** as the source
  of data, and adds the appreciated source link <https://api.met.no/>.
- The package CODE license is unchanged: **BSD 3-Clause**. (The DATA license
  and the CODE license are separate.)

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
- Data license: MET Norway forecast data is dual-licensed under **NLOD 2.0**
  AND **CC BY 4.0**; credit "Data from MET Norway" (<https://api.met.no/>);
  attribution is REQUIRED at the consumer-facing surface (see README).
