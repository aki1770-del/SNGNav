/// Pure Dart JP-domestic snow / ice / frozen-surface vocabulary
/// primitive.
///
/// This package surfaces a six-case taxonomy of culturally-load-bearing
/// JP terms for winter road conditions, paired with verbatim
/// safe-driving-response text from the Japan Automobile Federation
/// (JAF) where authoritative-source data has been captured.
///
/// Three of six entries are fully populated at 0.1.0 (アイスバーン
/// / ブラックアイスバーン / 雪道); the remaining three (圧雪 /
/// シャーベット / 凍結) carry only the taxonomic surface and will be
/// populated at 0.2.0 once a deeper review of authoritative sources
/// lands. The enum exposes all six cases today so that downstream
/// exhaustive `switch` is forward-compatible across the 0.1.0 → 0.2.0
/// boundary.
///
/// No Flutter dependency. No transitive dependencies. Consumable from
/// CLI tools, server-side test fixtures, and any other Pure Dart
/// package doing JP-domestic winter-driving vocabulary work.
///
/// See `KNOWN_LIMITATIONS.md` for the honest-disclosure scope and
/// `README.md` for the cohort framing and example usage.
library;

export 'src/jaf_authoritative_data.dart';
export 'src/japanese_snow_surface_class.dart';
export 'src/japanese_snow_vocabulary_entry.dart';
