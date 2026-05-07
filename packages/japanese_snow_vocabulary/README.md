# japanese_snow_vocabulary

[![pub package](https://img.shields.io/pub/v/japanese_snow_vocabulary.svg)](https://pub.dev/packages/japanese_snow_vocabulary)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/aki1770-del/SNGNav/blob/main/LICENSE)

**Pure Dart JP-domestic snow / ice / frozen-surface vocabulary
primitive.** Six enum cases for the culturally-load-bearing JP terms
that drivers in snow-prone regions distinguish in everyday speech,
paired with verbatim safe-driving-response text from the Japan
Automobile Federation (JAF) where authoritative-source data has been
captured.

| Term | Romaji | English-equivalent | Authoritative data at 0.1.0 |
|---|---|---|---|
| アイスバーン | aisubaan | icy hardpack | JAF — fully populated |
| ブラックアイスバーン | burakku-aisubaan | black ice | JAF — fully populated |
| 雪道 | yuki-michi | snow road | JAF — fully populated |
| 圧雪 | assetsu | compacted snow | _deferred to 0.2.0_ |
| シャーベット | shabetto | slush | _deferred to 0.2.0_ |
| 凍結 | kettou | frozen surface | _deferred to 0.2.0_ |

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
  japanese_snow_vocabulary: ^0.1.0
```

Then import the barrel:

```dart
import 'package:japanese_snow_vocabulary/japanese_snow_vocabulary.dart';
```

## Example

```dart
import 'package:japanese_snow_vocabulary/japanese_snow_vocabulary.dart';

void main() {
  // Iterate every case — exhaustive switch is forward-compatible
  // across the 0.1.0 -> 0.2.0 boundary because the enum has all six
  // cases today even though only three carry authoritative data.
  for (final surface in JapaneseSnowSurfaceClass.values) {
    final entry = jafAuthoritativeData[surface]!;
    print('${entry.termJa} (${entry.termRomaji}) — ${entry.labelEn}');

    if (entry.isFullyPopulated) {
      print('  source: ${entry.authoritativeSource}');
      print('  ${entry.safeDrivingResponseJa}');
    } else {
      print('  (authoritative safe-driving-response deferred to 0.2.0)');
    }
  }
}
```

## What is "verbatim" here?

Each fully-populated entry's `safeDrivingResponseJa` field is
byte-identical to the corresponding text on the JAF source page at
<https://jaf.or.jp/common/attention/snow> as of 2026-05-07. The
package's `verbatim_citation_test.dart` regression-guards the literal
strings; paraphrasing the JAF advisory text inside this package is
not permitted. If JAF revises the source page, the change should be
relayed through a new package version with a CHANGELOG entry.

## Honest disclosure — 3 of 6 entries

Three of the six enum cases (圧雪 / シャーベット / 凍結) carry only
the taxonomic surface (term + romaji + English label) at 0.1.0. The
five authoritative fields (`authoritativeSource`, `sourceUrl`,
`safeDrivingResponseJa`, `safeDrivingResponseEn`, `regionFrequency`)
are `null` for those entries. Populating them requires deeper review
of additional sources (Hokkaido regional bureau / NEXCO / JARTIC /
prefectural police), which lands at 0.2.0.

The enum exposes all six cases today so that downstream exhaustive
`switch` is forward-compatible across the 0.1.0 → 0.2.0 boundary —
0.2.0 will not break existing consumers.

See [`KNOWN_LIMITATIONS.md`](KNOWN_LIMITATIONS.md) for the full
honest-disclosure scope.

## License

BSD-3-Clause. See `LICENSE`.
