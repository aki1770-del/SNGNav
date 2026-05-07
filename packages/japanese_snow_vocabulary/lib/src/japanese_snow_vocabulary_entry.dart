/// Immutable record of one JP-domestic snow-vocabulary term.
///
/// Each entry encodes:
///
/// - [termJa] — the JA term (kanji / kana) preserved verbatim.
/// - [termRomaji] — Hepburn-style romanization.
/// - [labelEn] — best-effort English-equivalent label (does **not**
///   force a VSS-class collapse; consumers may surface either form).
/// - [authoritativeSource] — short label of the publisher of
///   [safeDrivingResponseJa] / [safeDrivingResponseEn] (e.g. `JAF`).
///   `null` when the entry is null-deferred at 0.1.0 per the
///   honest-disclosure pattern.
/// - [sourceUrl] — canonical URL of the authoritative source. `null`
///   when null-deferred.
/// - [safeDrivingResponseJa] — verbatim JA safety-advisory text from
///   the authoritative source. Subject to the AAA Article 17 (β)
///   verbatim-relay binding when non-null. `null` when null-deferred.
/// - [safeDrivingResponseEn] — best-effort English translation of the
///   advisory text. `null` when null-deferred or when no
///   high-confidence translation has been authored.
/// - [regionFrequency] — short qualitative anchor of where the term
///   most commonly applies (e.g. `Hokkaido common` or
///   `spring-thaw class`). `null` when null-deferred.
///
/// Equality is by-value (all eight fields) so that
/// [verbatim_citation_test.dart] can guard byte-identical regression
/// of the published JAF advisory text.
class JapaneseSnowVocabularyEntry {
  /// Construct an entry. Three taxonomic fields ([termJa],
  /// [termRomaji], [labelEn]) are always required; the five
  /// authoritative fields are optional so that null-deferred 0.1.0
  /// entries can coexist with fully-populated entries inside the
  /// same map literal.
  const JapaneseSnowVocabularyEntry({
    required this.termJa,
    required this.termRomaji,
    required this.labelEn,
    this.authoritativeSource,
    this.sourceUrl,
    this.safeDrivingResponseJa,
    this.safeDrivingResponseEn,
    this.regionFrequency,
  });

  /// JA term, verbatim characters (kanji / kana preserved).
  final String termJa;

  /// Hepburn-style romanization of [termJa].
  final String termRomaji;

  /// Best-effort English-equivalent label.
  final String labelEn;

  /// Short label of the authoritative publisher (e.g. `JAF`). `null`
  /// when this entry is null-deferred at 0.1.0.
  final String? authoritativeSource;

  /// Canonical URL of the authoritative source. `null` when
  /// null-deferred.
  final String? sourceUrl;

  /// Verbatim JA safety-advisory text from the authoritative source.
  /// AAA Article 17 (β) verbatim-relay binding applies when non-null.
  final String? safeDrivingResponseJa;

  /// Best-effort English translation of the advisory text. `null`
  /// when no high-confidence translation has been authored.
  final String? safeDrivingResponseEn;

  /// Short qualitative anchor of where the term most commonly
  /// applies. `null` when null-deferred.
  final String? regionFrequency;

  /// `true` when this entry has all five authoritative fields
  /// populated (i.e. is a 0.1.0 fully-populated entry rather than a
  /// 0.1.0 null-deferred entry).
  bool get isFullyPopulated =>
      authoritativeSource != null &&
      sourceUrl != null &&
      safeDrivingResponseJa != null &&
      safeDrivingResponseEn != null &&
      regionFrequency != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JapaneseSnowVocabularyEntry &&
          runtimeType == other.runtimeType &&
          termJa == other.termJa &&
          termRomaji == other.termRomaji &&
          labelEn == other.labelEn &&
          authoritativeSource == other.authoritativeSource &&
          sourceUrl == other.sourceUrl &&
          safeDrivingResponseJa == other.safeDrivingResponseJa &&
          safeDrivingResponseEn == other.safeDrivingResponseEn &&
          regionFrequency == other.regionFrequency;

  @override
  int get hashCode => Object.hash(
        termJa,
        termRomaji,
        labelEn,
        authoritativeSource,
        sourceUrl,
        safeDrivingResponseJa,
        safeDrivingResponseEn,
        regionFrequency,
      );

  @override
  String toString() =>
      'JapaneseSnowVocabularyEntry(termJa: $termJa, '
      'romaji: $termRomaji, labelEn: $labelEn, '
      'fullyPopulated: $isFullyPopulated)';
}
