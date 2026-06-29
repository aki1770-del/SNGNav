# Changelog

## 0.2.3

- Data-correctness fix: correct the `termRomaji` for `凍結`
  (`JapaneseSnowSurfaceClass.surfaceFrozen`) from the wrong `kettou` to
  the correct Hepburn `touketsu` (凍結 reads とうけつ). Fixed in
  `lib/src/jaf_authoritative_data.dart` and the README romaji table.
  No enum-shape, behavior, or verbatim-citation change.
- Add `test/romaji_test.dart` — a romaji-vs-kanji regression guard
  pinning every entry's `termRomaji` to its `termJa`, so a future
  mistyped romanization is caught at test time.

## 0.2.2

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.2.1 — 2026-05-10 — Pana score recovery (Theme α P3)

- Trim pubspec `description` to within the pana 60–180 character target.
- Add minimal `example/main.dart` for pana documentation scoring.
- Apply `dart format` to clear any formatter findings.
- No SDK source changes; metadata + format pass only.

## 0.2.0 — 2026-05-07 — Data-fill: 3 deferred entries populated (圧雪 / シャーベット / 凍結)

Verbatim authoritative-source citations added for the three entries
that carried only a taxonomic surface at 0.1.0:

- `JapaneseSnowSurfaceClass.compactedSnow` — 圧雪 (compacted snow);
  primary source JAF Training snow-drive column
  <https://jaf-training.jp/column/snow-drive/>; corroborated by JAF
  FAQ148 + MLIT Mie regional bureau (3-source coverage).
- `JapaneseSnowSurfaceClass.slush` — シャーベット (slush); single
  source JAF Training snow-drive column
  <https://jaf-training.jp/column/snow-drive/>. Single-publisher
  coverage; honest-class disclosure preserved in `KNOWN_LIMITATIONS.md`.
- `JapaneseSnowSurfaceClass.surfaceFrozen` — 凍結 (frozen surface);
  primary source JAF FAQ148
  <https://jaf.or.jp/common/kuruma-qa/category-natural/subcategory-snow/faq148>;
  corroborated by JAF Training winter-frozen-road + MLIT Mie regional
  bureau (3-source coverage).

All `safeDrivingResponseJa` strings are byte-identical to their JAF
source pages at extraction time (2026-05-07). The
`verbatim_citation_test.dart` test file regression-guards each new
literal at the same byte-identical granularity used at 0.1.0.

All six of six enum cases now carry full authoritative-source data.
The `data_completeness_test.dart` test file is updated to assert
6-of-6 populated; the 0.1.0 assertion of 3-of-6 populated +
3-of-6 deferred is replaced.

Forward-compatibility: this is an additive non-breaking release. The
enum shape is unchanged from 0.1.0; the three previously-null fields
on the deferred entries are now populated. Existing 0.1.0 consumers
relying on `JapaneseSnowVocabularyEntry.isFullyPopulated` to gate
authoritative-data access will transparently pick up the new data
without code change.

`KNOWN_LIMITATIONS.md` is updated: the 3-of-6 partial-disclosure
section is marked RESOLVED at 0.2.0, with the シャーベット
single-publisher caveat preserved as honest-class disclosure and
future-cadence improvement candidates noted (regional-vocabulary
additions, deeper Hokkaido bureau substrate, user-facing example app).

## 0.1.0 — 2026-05-07

Initial release. Six enum cases of JP-domestic snow / ice /
frozen-surface vocabulary with verbatim JAF authoritative-source
safe-driving-response citations populated for three of six entries:

- `JapaneseSnowSurfaceClass.iceBahn` — アイスバーン (icy hardpack);
  JAF citation populated.
- `JapaneseSnowSurfaceClass.blackIceBahn` — ブラックアイスバーン
  (black ice); JAF citation populated.
- `JapaneseSnowSurfaceClass.snowyRoad` — 雪道 (snow road); JAF
  citation populated.
- `JapaneseSnowSurfaceClass.compactedSnow` — 圧雪 (compacted snow);
  taxonomic surface only; authoritative fields `null` at 0.1.0.
- `JapaneseSnowSurfaceClass.slush` — シャーベット (slush); taxonomic
  surface only; authoritative fields `null` at 0.1.0.
- `JapaneseSnowSurfaceClass.surfaceFrozen` — 凍結 (frozen surface);
  taxonomic surface only; authoritative fields `null` at 0.1.0.

The three fully-populated entries' `safeDrivingResponseJa` strings
are byte-identical to the JAF source page at
<https://jaf.or.jp/common/attention/snow> as of 2026-05-07. The
`verbatim_citation_test.dart` test file regression-guards the literal
text; the package treats paraphrasing the authoritative advisory as
forbidden.

The enum exposes all six cases at 0.1.0 even though only three carry
authoritative data, so that downstream exhaustive `switch` is
forward-compatible across the 0.1.0 → 0.2.0 boundary.

No Flutter dependency. No transitive dependencies beyond `test` +
`lints` for development. License: BSD-3-Clause (mirrors
`navigation_safety_core`).

`KNOWN_LIMITATIONS.md` is authored at extraction time honest-disclosing
the 3-of-6 fully-populated scope, the bounded source coverage at
0.1.0, and the path to 0.2.0.

## Forward — 0.3.0 (planned)

A 0.3.0 release will deepen authoritative-source coverage for the
single-publisher entry (シャーベット) and consider regional-vocabulary
additions (e.g. Hokkaido-specific terms such as ガリ雪) from
prefectural-police + Hokkaido regional bureau substrates. The enum
shape will be extended additively; consumers using exhaustive
`switch` over `JapaneseSnowSurfaceClass.values` should plan for new
cases at the 0.3.0 boundary.
