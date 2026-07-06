## 0.1.0

- Initial release. `fuseDriveSituation` assembles a `compound_failure_advisor`
  `DriveSituation` from a `localization_fallback` `LocalizationEstimate` and a
  `condition_aggregator` `Advisory`.
- Exposes the two canonical seam mappings — `positionTrustOf` and
  `advisoryLevelOf` — for callers that assemble `DriveSituation` themselves.
- Total and deterministic; zero clock, zero IO. The safety-critical
  `deadReckoning -> degraded` mapping is canonical and tested.
