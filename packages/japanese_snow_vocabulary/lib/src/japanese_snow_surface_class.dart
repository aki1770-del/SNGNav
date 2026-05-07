/// Six-case taxonomy of JP-domestic snow / ice / frozen road-surface
/// vocabulary, finer-grained than the English-language collapse used
/// by VSS `RoadSurfaceCondition`.
///
/// Each enum case names a culturally-load-bearing JP term that
/// drivers in snow-prone regions distinguish in everyday speech.
/// Distinct semantics → distinct safe-driving response. The
/// English-equivalent labels in this enum are best-effort
/// transliterations and do **not** force a VSS-class collapse.
///
/// Founding insight: the SNGNav 100-insights document (2026-04-27)
/// records that *"HER's first-language vocabulary for snow conditions
/// is finer-grained than English allows"* and that *"no app provides
/// in-app glossary"* (Appendix A.2 finding 5). This package exists to
/// surface those distinctions to integrators building JP-domestic
/// winter-driving apps.
///
/// Pair with [JapaneseSnowVocabularyEntry] (data class) and
/// [jafAuthoritativeData] (canonical map) from this same package to
/// retrieve the per-term verbatim safe-driving-response text.
///
/// Forward compatibility: the enum exposes all six cases at 0.1.0
/// even though only three of them have authoritative-source
/// safe-driving-response data populated. Downstream exhaustive
/// `switch` covers the full set today; 0.2.0 will populate the
/// remaining three entries without an enum-shape change.
enum JapaneseSnowSurfaceClass {
  /// アイスバーン — icy hardpack road surface; more slippery than
  /// general snow road; appears when daytime-melted snow refreezes
  /// overnight. JAF authoritative citation populated at 0.1.0.
  iceBahn,

  /// ブラックアイスバーン — black-ice subclass; visually
  /// indistinguishable from wet black asphalt yet the surface is
  /// frozen. Most dangerous on bridges, overpasses, and tunnel
  /// entrances. JAF authoritative citation populated at 0.1.0.
  blackIceBahn,

  /// 雪道 — general snow / snowy road class. JAF authoritative
  /// citation populated at 0.1.0.
  snowyRoad,

  /// 圧雪 — compacted snow surface (typical Hokkaido winter road).
  /// Authoritative-source safe-driving-response NOT yet captured at
  /// 0.1.0; populated at 0.2.0 per honest-disclosure pattern. The
  /// enum case is exposed today so that downstream exhaustive
  /// `switch` is forward-compatible.
  compactedSnow,

  /// シャーベット — slush / spring-thaw shaved-ice consistency.
  /// Authoritative-source safe-driving-response NOT yet captured at
  /// 0.1.0; populated at 0.2.0.
  slush,

  /// 凍結 — frozen road surface (general / 路面凍結). Authoritative
  /// safety advisory NOT yet captured at 0.1.0; populated at 0.2.0.
  surfaceFrozen,
}
