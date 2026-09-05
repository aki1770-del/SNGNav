# OSM extract provenance — how someone who is not us rebuilds the tile inputs

## WHY this exists — written before the act

**The reader is a named class of person: a maintainer outside this machine who
must rebuild our map data to accept our work.** That is not hypothetical. On
2026-04-01 `jwinarske` reverted our `meta-flutter#748` the same day it merged,
and our own words in `#751` say why: *"Not build-tested on our end."* His
constraint, verbatim 2026-04-07: ***"The CI runner is my primary workstation,
and I only run it when I'm running a version roll."***

**A maintainer who cannot rebuild our input cannot accept our work.**
Reproducibility is not release hygiene here — it is the precondition for
contributing into the Toyota landscape at all.

## ⚑ What was wrong until now, measured 2026-08-30

Commit `0a79d8d` gitignored 1.6 GB of `.osm.pbf` and committed three `.md5`
files, calling the checksum *"the reproducibility anchor."* **Measured
afterwards, that claim did not hold:**

1. **No source URL was recorded** for any of the three checksummed files. A
   checksum with no source is not an anchor — it verifies a file you already
   have and tells a stranger nothing about where to get it.
2. **Two of the four are `-latest`.** Geofabrik serves different bytes at a
   `-latest` URL every day. **Checksumming a moving target anchors nothing** —
   re-fetching tomorrow yields a different file and a different md5, and the
   mismatch is indistinguishable from corruption.
3. **`chubu-latest` had no `.md5` at all** — it was ignored and left unrecorded.

**Six links resolved and the seventh was never written** — the same shape this
unit measured in AGL's `ondemandnavi` the same day, where a complete Japanese
TTS stack ships and one unwritten line means it never speaks. Yokoten.

## The extracts

All from **Geofabrik**, `https://download.geofabrik.de/asia/japan/<name>.osm.pbf`.

| file we hold | size | md5 | fetched | re-fetchable? |
|---|---|---|---|---|
| `kanto-260801.osm.pbf` | 460M | `7ff182dbcdbe9ba6928f618b300f58a3` | 2026-08-11 | ✅ **YES** — dated URL verified **HTTP 200** on 2026-08-30 |
| `tohoku-260701.osm.pbf` | 290M | `525fa2b8caffdc0fc48218bb55d2f6ef` | 2026-08-11 | ✅ **YES** — dated URL verified **HTTP 200** on 2026-08-30 |
| `kanto-latest.osm.pbf` | 463M | `af79f874a235556e89d8b0b7ebf9bdc6` | 2026-08-11 | ⚑ **NO** — moving target |
| `chubu-latest.osm.pbf` | 425M | `89e0c2a9693805358764791828fdc056` | 2026-08-08 | ⚑ **NO** — moving target |

```sh
# The two that a stranger can actually reproduce:
wget https://download.geofabrik.de/asia/japan/kanto-260801.osm.pbf
wget https://download.geofabrik.de/asia/japan/tohoku-260701.osm.pbf
md5sum -c kanto-260801.osm.pbf.md5 tohoku-260701.osm.pbf.md5
```

⚑ **The two `-latest` md5s describe OUR LOCAL COPY ONLY.** They are useful for
detecting that our own copy changed underneath us. **They are not a fetch
instruction and must never be cited as one.**

## ⚑ Honest bounds

1. **Geofabrik retains dated extracts for a limited window (~90 days).** Both
   URLs answered 200 on 2026-08-30; **that is a measurement with an expiry, not
   a durable guarantee.** When they fall off, these two become unreproducible
   too, and only a mirrored copy would fix that. **No mirror exists.**
2. **`chubu-260801` and `chubu-260701` exist upstream (both HTTP 200) — but we
   do NOT hold them, and it is NOT claimed that either is byte-identical to our
   `chubu-latest` copy** (fetched 2026-08-08, so a `260808`-class snapshot).
   Same for `kanto-latest` vs `kanto-260801`: **measured, they are different
   files** — `af79f874…` vs `7ff182db…`.
3. **Migrating the two `-latest` consumers onto pinned extracts is NOT done
   here.** `packages/condition_aggregator_jma/tool/derive_prefecture_boxes.py`
   takes `--pbf ../../kanto-latest.osm.pbf`. Changing which extract a derived
   artifact was measured from could move that artifact, and that is a data
   decision, not a filing one. **Named, not silently made.**
4. **Nothing here was re-downloaded or re-derived this turn.** The md5s are of
   the files on this disk; the URLs were probed with `curl -I` only.
