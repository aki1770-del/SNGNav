# Changelog

## 0.1.0

- Initial release.
- `ConsentRecord` model with Jidoka semantics (UNKNOWN = DENIED).
- `ConsentStatus` three-state gate: granted, denied, unknown.
- `ConsentPurpose` per-purpose scoping: fleet location, weather telemetry, diagnostics.
- `Jurisdiction` multi-jurisdiction support: GDPR, CCPA, APPI.
- `ConsentService` abstract interface for pluggable storage.
- `InMemoryConsentService` for testing and offline use.
