# Known limitations

This document lists known limitations of the JP-domestic snow
vocabulary primitives shipped in `japanese_snow_vocabulary` 0.1.0,
with citations to the public sources used at extraction time, so
that consumers can integrate with eyes open and contribute
corrections from informed positions.

The list is honest by intent — surfacing what is not yet covered
rather than letting silent gaps reach drivers.

---

## Authoritative-source coverage at 0.1.0

### What is verified at 0.1.0

The three fully-populated entries — アイスバーン / ブラックアイスバーン
/ 雪道 — carry `safeDrivingResponseJa` text byte-identical to the JAF
(Japan Automobile Federation) source page
<https://jaf.or.jp/common/attention/snow> as captured on 2026-05-07.
The `verbatim_citation_test.dart` test file regression-guards the
literal strings; any future edit that drifts from the JAF source
will fail the test.

The taxonomic surface of all six entries (term + romaji + English
label) is verified against the founding cohort-research that
authored the JP vocabulary scope.

### What is UNVERIFIED at 0.1.0

- **Three entries have authoritative fields `null` at 0.1.0.** The
  `compactedSnow` (圧雪), `slush` (シャーベット), and `surfaceFrozen`
  (凍結 / 路面凍結) entries each carry only the taxonomic surface
  (term + romaji + English label). The five authoritative fields
  (`authoritativeSource`, `sourceUrl`, `safeDrivingResponseJa`,
  `safeDrivingResponseEn`, `regionFrequency`) are `null`.
- **The English-equivalent labels are best-effort.** `aisubaan` →
  `icy hardpack` and the other English fields in this package are
  engineering best-effort; they are not intended as a final UX
  surface and they should not be treated as locale-correct
  translations of the JAF advisory text. Consumers building
  user-facing surfaces should plumb their own translation pipeline.
- **Single-publisher coverage.** Where authoritative data is
  populated, it is currently single-source (JAF). Cross-publisher
  reconciliation across JARTIC / NEXCO / Hokkaido regional bureau /
  prefectural police is deferred to a later release.
- **Region / frequency anchors are qualitative.** The
  `regionFrequency` field carries short prose rather than a
  structured taxonomy of regions or weather-type frequencies. A
  future release may introduce a structured form once the dimension
  has stabilised.

### When NOT to use the 0.1.0 data unmodified

- **Safety-critical UI surfaces that need all six classes covered.**
  Three of six classes carry no authoritative advisory text at 0.1.0.
  Surfacing the JA-only taxonomic label without an advisory string
  may be acceptable for glossary-class consumers but is not
  sufficient for a surface that promises drivers an authoritative
  safe-driving response per class.
- **Dynamic surface-detection inference.** None of this package
  infers surface class from sensors. Consumers wanting live
  detection should compose this package with their own
  surface-classification model and surface the matching JA
  vocabulary entry only after their classifier has fired.
- **Direct VSS-class collapse.** This package intentionally does
  **not** define a mapping from `JapaneseSnowSurfaceClass` onto a
  VSS `RoadSurfaceCondition` value. Consumers that need a mapping
  should author it explicitly at their integration boundary so that
  the cohort-dignity discussion (when to collapse, when to preserve
  the JA distinction) is visible at the integration site rather than
  buried inside this package.

---

## Out-of-scope at 0.1.0

This package contains **no live-detection logic, no rendering, no
audio surface, and no telemetry pipeline**. It is a Pure Dart data
primitive. Consumers are responsible for sensors, classification,
UI, and everything else that turns the vocabulary into a driver-
visible advisory.

The package does not depend on `navigation_safety_core` and does not
import any of its types.

---

## Path to 0.2.0

The 0.2.0 release populates the three null-deferred entries
(`compactedSnow` / `slush` / `surfaceFrozen`) with authoritative
citations from a deeper review of Hokkaido regional bureau / NEXCO /
JARTIC / prefectural police sources. The enum shape will not change;
the change is additive on the data map only. Downstream exhaustive
`switch` written against 0.1.0 will continue to work without code
change.

The forward path is documented in `CHANGELOG.md` under the
`Forward — 0.2.0 (planned)` heading.

---

## How to contribute corrections

If you have:

- a JAF source-page revision that should refresh the literal verbatim
  text in an existing entry,
- a citation from another authoritative JP-domestic publisher
  (Hokkaido regional bureau / NEXCO / JARTIC / prefectural police)
  that fills the 圧雪 / シャーベット / 凍結 advisory gap, or
- a population-validated translation of the safe-driving-response
  text that improves the best-effort English field,

please open an issue at
<https://github.com/aki1770-del/SNGNav/issues>. Citations to a
published authoritative source are sufficient; verbatim-relay text
must include the URL and a clear extraction date so the package can
reproduce the byte-identical guard.
