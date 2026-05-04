# Changelog

## 0.0.1 — 2026-05-06 — Explore-phase scaffold

**Status: PUBLISH-PENDING.** Deploy graduation BLOCKS on a separate
engagement-shape election (alpha / beta / gamma) for the upstream
parser substrate (jmaxml). This entry records the scaffold landing
on disk; pub.dev publish does NOT happen at this version.
`publish_to: none` is set in `pubspec.yaml`.

### Added

- `JmaAdvisoryProvider` implementing `AdvisoryProvider` from
  `condition_aggregator`. Constructor accepts an `endpointBaseUrl`
  (default = the public JMA disaster-info XML feed root). `init()`
  is no-op; `fetchActiveAdvisoriesAtPoint` is a stub returning an
  empty list at every point until the upstream parser integration
  lands.
- `JmaForecastRecord` placeholder record shape used by the
  explore-phase scaffold. Replaced at graduation by the upstream
  parser's report-typed shape (e.g. `jmaxml`'s `Forecast` family).
- `mapJmaForecastToAdvisory(JmaForecastRecord)` mapper with locked
  shape: `source`, `eventClass`, `areaDescription`, `headline`,
  `description`, `effective`, `expires` are passthrough today;
  `severity` / `certainty` / `urgency` map to `unknown` at
  explore-phase and graduate to the per-report-family CAP
  normalization table at deploy-time.
- 9 tests covering: provider source identity, init contract,
  endpoint injectability, stub returns empty at any point,
  uninitialized fetch raises `AdvisoryProviderInitException`,
  mapper preserves JMA report family code verbatim, mapper
  passes through area / headline / description / effective /
  expires, mapper severity / certainty / urgency placeholder.
- `SAFETY_BOUNDARY.md` per-package boundary record at scaffold-time.
- BSD-3-Clause license (matches the rest of SNGNav).

### Deploy-graduation gate (does NOT fire at 0.0.1)

This package's deploy graduation BLOCKS on:

1. Komada-voice engagement-shape election for the upstream parser
   substrate (alpha / beta / gamma — election cadence is scheduled
   per the engagement governance track).
2. Upstream parser binding integration — either WASM bridge to the
   existing Rust crate OR Dart-native codegen port of the parser
   pipeline (both shapes were canvassed in the substrate prep, the
   election picks one).
3. Per-report-family CAP severity / certainty / urgency mapping
   table validation against multiple JMA sample feeds.
4. Region resolution from WGS84 lat/lon → JMA region code (the
   feed is region-segmented).
5. Aspiration → Deploy gate enumeration per the package's spec
   discipline (PHIL-001 8/8, CEO Vision Test 6/6, Article 17 (β)
   determination, JIS / JASO conformance audit, cybersecurity
   audit).

Until those gates fire, this package stays at `publish_to: none`.
