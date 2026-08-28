# Short-time tier fixtures — provenance

| file | what it is | retrieved |
|---|---|---|
| `jma_shorttime_VPOA50_130000_single.frozen_2026-08-22.xml` | **REAL event.** Toshima-ku 100mm/h, legacy VPOA50 | 2026-08-23 from `data.jma.go.jp/developer/xml/data/` |
| `jma_shorttime_VPOA50_130000_multiarea.frozen_2026-08-22.xml` | **REAL event.** Kita-ku + Itabashi-ku | 2026-08-23, same source |
| `jma_shorttime_VPOA50_070000_fukushima.frozen_2026-08-20.xml` | **REAL event.** Kitashiobara-mura | 2026-08-23, same source |
| `jma_shorttime_VPBS50_130000_rain.frozen_2026-08-22.xml` | **REAL event.** The VPBS50 twin dual-published at the same second as the VPOA50 single above | 2026-08-23, same source |
| `jma_shorttime_VPBS50_snow.JMA_OFFICIAL_SAMPLE.xml` | ⚑ **NOT a real event.** JMA's own published format sample (`82_01_03_241031_VPBS50.xml`) | 2026-08-23 from `xml.kishou.go.jp/jmaxml_20260723_Samples.zip` |

⚑ **The snow fixture is a specimen, not an observation.** It is JMA's authoritative
statement of the wire format, which is what a parser must be built against — but no
真 短時間大雪 event has been observed by this package. The May 2026 cutover to VPBS50
has not yet been exercised by a snow season: winter 2026-27 will be the first.
Until then, snow support is **format-verified, not event-verified**, and the
distinction is deliberate and load-bearing.
