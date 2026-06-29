# japanese_snow_vocabulary

[![pub package](https://img.shields.io/pub/v/japanese_snow_vocabulary.svg)](https://pub.dev/packages/japanese_snow_vocabulary)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/aki1770-del/SNGNav/blob/main/LICENSE)

**Pure Dart JP-domestic snow / ice / frozen-surface vocabulary
primitive.** Six enum cases for the culturally-load-bearing JP terms
that drivers in snow-prone regions distinguish in everyday speech,
paired with verbatim safe-driving-response text from the Japan
Automobile Federation (JAF) where authoritative-source data has been
captured.

| Term | Romaji | English-equivalent | Authoritative data at 0.2.0 |
|---|---|---|---|
| アイスバーン | aisubaan | icy hardpack | JAF — fully populated |
| ブラックアイスバーン | burakku-aisubaan | black ice | JAF — fully populated |
| 雪道 | yuki-michi | snow road | JAF — fully populated |
| 圧雪 | assetsu | compacted snow | JAF — fully populated |
| シャーベット | shabetto | slush | JAF — fully populated (single-publisher; see `KNOWN_LIMITATIONS.md`) |
| 凍結 | touketsu | frozen surface | JAF — fully populated |

The package serves a population gap: VSS `RoadSurfaceCondition`
(English-language) collapses these distinctions into broader buckets,
yet drivers' first-language vocabulary distinguishes them clearly and
each carries a distinct safe-driving response. This package surfaces
the JP taxonomy without forcing a VSS-class collapse, so downstream
integrators can decide for themselves how to map between the two
surfaces.

No Flutter dependency. No transitive dependencies (beyond `test` +
`lints` for development).

## Who is this for?

- **Open-source consumers** building Pure Dart libraries that need a
  canonical JP-domestic snow-vocabulary surface.
- **Config-defaults consumers** wanting a stable enum + map that can
  be inherited and extended by application-level configuration.
- **Parallel-product builders** shipping JP-domestic Flutter or Dart
  navigation / fleet / weather apps that surface culturally-correct
  advisory text to drivers.
- **JP-domestic cultural-voice dignity** — this package exists to
  prevent the silent erasure of finer-grained JA vocabulary by
  English-language collapse at the VSS / data-fusion boundary.

Typical consumers will pair this package with their own UI layer,
their own translation pipeline (the included English text is
best-effort and not intended as a final UX surface), and their own
sensor / forecast integration.

## Install

Add to `pubspec.yaml`:

```yaml
dependencies:
  japanese_snow_vocabulary: ^0.2.0
```

Then import the barrel:

```dart
import 'package:japanese_snow_vocabulary/japanese_snow_vocabulary.dart';
```

## Example

```dart
import 'package:japanese_snow_vocabulary/japanese_snow_vocabulary.dart';

void main() {
  // Iterate every case — all six entries carry verbatim JAF
  // authoritative-source data at 0.2.0; exhaustive switch is
  // forward-compatible.
  for (final surface in JapaneseSnowSurfaceClass.values) {
    final entry = jafAuthoritativeData[surface]!;
    print('${entry.termJa} (${entry.termRomaji}) — ${entry.labelEn}');
    print('  source: ${entry.authoritativeSource}');
    print('  ${entry.safeDrivingResponseJa}');
  }
}
```

## What is "verbatim" here?

Each entry's `safeDrivingResponseJa` field is byte-identical to its
JAF source page at extraction time (2026-05-07). Three entries
(アイスバーン / ブラックアイスバーン / 雪道) draw from the JAF
snow-attention page <https://jaf.or.jp/common/attention/snow>. Three
entries draw from JAF Training columns + JAF FAQ148 — see
`KNOWN_LIMITATIONS.md` for the full per-entry source matrix. The
package's `verbatim_citation_test.dart` regression-guards the literal
strings; paraphrasing the JAF advisory text inside this package is
not permitted. If JAF revises a source page, the change should be
relayed through a new package version with a CHANGELOG entry.

## Honest disclosure — single-publisher caveat for シャーベット

All six entries carry full authoritative-source data at 0.2.0. Five
of the six entries are corroborated by multiple independent
authoritative-source pages; the シャーベット (slush) entry is cited
from a single JAF Training column at this release. The single-source
verbatim citation is sufficient under the verbatim-relay binding
because the publisher is authoritative-class; deeper cross-publisher
cohort coverage is a 0.3.0 cadence candidate. See
[`KNOWN_LIMITATIONS.md`](KNOWN_LIMITATIONS.md) for the full
honest-disclosure scope.

## License

BSD-3-Clause. See `LICENSE`.
