/// JMA forecast-record → source-neutral [Advisory] mapping.
///
/// **Explore-phase scaffold.** The function signature is locked so the
/// provider in [JmaAdvisoryProvider] can wire against the mapper today
/// (and tests can exercise the mapping shape) — but the mapping logic
/// is a placeholder until the upstream parser integration lands.
///
/// At graduation time, the input type changes from the placeholder
/// [JmaForecastRecord] below to the real upstream-parser report-typed
/// shape (e.g. `jmaxml`'s `Forecast` family) emitted by whichever
/// engagement-shape (WASM bridge OR Dart-native codegen port) the
/// election produces.
///
/// Severity / certainty / urgency mapping at deploy-time:
/// - JMA report family → CAP-class severity is non-trivial: JMA uses
///   報 (warning) / 注意報 (advisory) / 特別警報 (emergency warning)
///   distinct from the CAP minor / moderate / severe / extreme scale.
///   The mapping is publisher-class normalization, not authoritative
///   reclassification — the original JMA term is preserved verbatim
///   in `Advisory.eventClass`.
library;

import 'package:condition_aggregator/condition_aggregator.dart';

/// Placeholder JMA forecast-record shape used by the explore-phase
/// scaffold's tests. At graduation, this type is replaced by the real
/// upstream-parser report-typed shape; downstream callers re-bind via
/// the export surface in `condition_aggregator_jma.dart`.
class JmaForecastRecord {
  /// JMA report family code (e.g. `VPWW54`, `VPCJ51`, `VPAW51`,
  /// `VPFD60`, `VPBS50`). Verbatim-relayed in `Advisory.eventClass`.
  final String reportFamilyCode;

  /// Free-form headline as published by JMA (Japanese-language).
  final String headline;

  /// Multi-paragraph description as published by JMA.
  final String description;

  /// Free-form area description (typically 都道府県 list).
  final String areaDescription;

  /// When the advisory takes effect.
  final DateTime? effective;

  /// When the advisory expires.
  final DateTime? expires;

  const JmaForecastRecord({
    required this.reportFamilyCode,
    required this.headline,
    required this.description,
    required this.areaDescription,
    required this.effective,
    required this.expires,
  });
}

/// Maps a JMA forecast record to a source-neutral [Advisory].
///
/// **Explore-phase placeholder mapping**:
/// - `source` ← `AdvisorySource.jmaJapan` (constant)
/// - `eventClass` ← `JmaForecastRecord.reportFamilyCode` verbatim
/// - `severity` ← `AdvisorySeverity.unknown` (placeholder — graduates
///   to per-report-family CAP normalization at deploy-time)
/// - `certainty` ← `AdvisoryCertainty.unknown` (placeholder)
/// - `urgency` ← `AdvisoryUrgency.unknown` (placeholder)
/// - `areaDescription` / `headline` / `description` / `effective` /
///   `expires` are direct passthroughs.
///
/// At deploy-graduation the severity / certainty / urgency mapping
/// table per report family lands; the shape locks above, the table
/// expands.
Advisory mapJmaForecastToAdvisory(JmaForecastRecord record) {
  return Advisory(
    source: AdvisorySource.jmaJapan,
    eventClass: record.reportFamilyCode,
    severity: AdvisorySeverity.unknown,
    certainty: AdvisoryCertainty.unknown,
    urgency: AdvisoryUrgency.unknown,
    areaDescription: record.areaDescription,
    effective: record.effective,
    expires: record.expires,
    headline: record.headline,
    description: record.description,
  );
}
