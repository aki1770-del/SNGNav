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

## Forward — 0.2.0 (planned)

The 0.2.0 release will populate the three null-deferred entries
(圧雪 / シャーベット / 凍結) with authoritative-source citations
from a deeper review of JP-domestic safety publishers (Hokkaido
regional bureau / NEXCO / JARTIC / prefectural police). The enum
shape will not change; the change is additive on the data map only.
Existing 0.1.0 consumers using exhaustive `switch` over
`JapaneseSnowSurfaceClass.values` will not need code changes to
benefit from the deeper data.
