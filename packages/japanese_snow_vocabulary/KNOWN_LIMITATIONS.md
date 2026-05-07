# Known limitations

This document lists known limitations of the JP-domestic snow
vocabulary primitives shipped in `japanese_snow_vocabulary` 0.2.0,
with citations to the public sources used at extraction time, so
that consumers can integrate with eyes open and contribute
corrections from informed positions.

The list is honest by intent — surfacing what is not yet covered
rather than letting silent gaps reach drivers.

---

## Authoritative-source coverage at 0.2.0

### What is verified at 0.2.0

All six entries carry `safeDrivingResponseJa` text byte-identical to
the JAF (Japan Automobile Federation) source pages captured on
2026-05-07. The three 0.1.0 entries (アイスバーン /
ブラックアイスバーン / 雪道) draw from
<https://jaf.or.jp/common/attention/snow>. The three 0.2.0 data-fill
entries draw from JAF Training columns + JAF FAQ148:

- 圧雪 (compactedSnow) — primary source JAF Training snow-drive
  <https://jaf-training.jp/column/snow-drive/>; corroborated by JAF
  FAQ148
  <https://jaf.or.jp/common/kuruma-qa/category-natural/subcategory-snow/faq148>
  + MLIT Mie regional bureau
  <https://www.cbr.mlit.go.jp/mie/snow/sp/point.html> (3-source
  coverage).
- シャーベット (slush) — single source JAF Training snow-drive
  <https://jaf-training.jp/column/snow-drive/> (1-source coverage;
  see honest-class caveat below).
- 凍結 (surfaceFrozen) — primary source JAF FAQ148; corroborated by
  JAF Training winter-frozen-road
  <https://jaf-training.jp/column/winter-frozen-road/> + MLIT Mie
  regional bureau
  <https://www.cbr.mlit.go.jp/mie/snow/sp/caution.html> (3-source
  coverage).

The `verbatim_citation_test.dart` test file regression-guards every
literal at byte-identical granularity; any future edit that drifts
from the JAF source will fail the test.

The taxonomic surface of all six entries (term + romaji + English
label) is verified against the founding cohort-research that
authored the JP vocabulary scope.

### Honest-class disclosure at 0.2.0

- **シャーベット single-publisher coverage.** The slush entry is
  cited from JAF Training snow-drive only. At extraction time the
  term was absent from JAF FAQ148, MLIT Mie regional bureau pages,
  and NEXCO Central drive-plaza. This is a common-vernacular-class
  naming-frequency observation rather than a safety-advisory-class
  lacuna — the term itself is in active use in JAF safety material
  but the cross-publisher cohort treats it less consistently than
  圧雪 / 凍結. The single-source verbatim citation is sufficient
  under the verbatim-relay binding because the publisher is
  authoritative-class; deeper cross-publisher cohort coverage is a
  0.3.0 cadence candidate.
- **English-equivalent labels remain best-effort.** `aisubaan` →
  `icy hardpack` and the other English fields in this package are
  engineering best-effort; they are not intended as a final UX
  surface and they should not be treated as locale-correct
  translations of the JAF advisory text. Consumers building
  user-facing surfaces should plumb their own translation pipeline.
- **Region / frequency anchors are qualitative.** The
  `regionFrequency` field carries short prose rather than a
  structured taxonomy of regions or weather-type frequencies. A
  future release may introduce a structured form once the dimension
  has stabilised.

### What was UNVERIFIED at 0.1.0 — RESOLVED at 0.2.0

- **0.1.0 deferred-entry gap (3-of-6 partial disclosure) — RESOLVED
  at 0.2.0.** The 0.1.0 release shipped 圧雪 / シャーベット / 凍結
  with all five authoritative fields (`authoritativeSource`,
  `sourceUrl`, `safeDrivingResponseJa`, `safeDrivingResponseEn`,
  `regionFrequency`) `null`. At 0.2.0 each of the three entries
  carries verbatim authoritative-source citations as documented in
  the section above.

### When NOT to use the 0.2.0 data unmodified

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

## Out-of-scope at 0.2.0

This package contains **no live-detection logic, no rendering, no
audio surface, and no telemetry pipeline**. It is a Pure Dart data
primitive. Consumers are responsible for sensors, classification,
UI, and everything else that turns the vocabulary into a driver-
visible advisory.

The package does not depend on `navigation_safety_core` and does not
import any of its types.

---

## Path to 0.3.0 (improvement candidates)

The 0.3.0 release is a candidate for the following improvements;
none are committed and none will land without integrator-developer
demand evidence:

- **Deeper シャーベット cross-publisher coverage** — survey
  prefectural-police winter-driving guides (Hokkaido / Aomori /
  Akita) + NEXCO PDF substrate (`s08.pdf` references
  「シャーベット状の積雪」 in chain-regulation context) to lift the
  entry from single-publisher to multi-publisher coverage.
- **Regional-vocabulary additions** — Hokkaido-specific terms such
  as ガリ雪 (gari-yuki, granular ice) that did not surface in the
  founding JAF + MLIT cohort but are in active driver-vernacular use
  in north-Japan regions.
- **Deeper Hokkaido regional bureau substrate** — the substrate-prep
  pass over-credited Hokkaido bureau yukinavi
  (`hrr.mlit.go.jp/hokugi/yukinavi/`) as canonical-glossary-class
  authority; deeper review surfaced that yukinavi is real-time
  information portal, not vocabulary glossary. A targeted 0.3.0
  bureau-substrate review may surface additional canonical-class
  pages.
- **User-facing example app** — a small example surfacing the
  vocabulary in a driver-facing context, useful as integrator
  reference but explicitly not a UX recommendation.

The enum shape may extend additively at 0.3.0 (new cases); existing
fully-populated entries will remain forward-compatible.

---

## How to contribute corrections

If you have:

- a JAF source-page revision that should refresh the literal verbatim
  text in an existing entry,
- a citation from another authoritative JP-domestic publisher
  (Hokkaido regional bureau / NEXCO / JARTIC / prefectural police)
  that thickens the cross-publisher cohort for any of the six
  entries (especially シャーベット), or
- a population-validated translation of the safe-driving-response
  text that improves the best-effort English field,

please open an issue at
<https://github.com/aki1770-del/SNGNav/issues>. Citations to a
published authoritative source are sufficient; verbatim-relay text
must include the URL and a clear extraction date so the package can
reproduce the byte-identical guard.
