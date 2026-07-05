# bridges_akita.csv.gz — Attribution / 出典表示

橋の位置データ: © OpenStreetMap contributors (ODbL)

Bridge location data: © OpenStreetMap contributors, licensed under the
[Open Database License (ODbL) 1.0](https://opendatacommons.org/licenses/odbl/1-0/).
https://www.openstreetmap.org/copyright

このファイル（`bridges_akita.csv.gz`）のデータは ODbL ライセンス
（データに対するシェアアライク）に従います。周辺のソースコードは
BSD-3-Clause のままです。ライセンスを分離するために、データは
意図的に独立したアセットファイルとして格納されています。

The DATA in `bridges_akita.csv.gz` is ODbL (share-alike applies to the
data); the surrounding source code stays BSD-3-Clause. The data lives in
this separate file precisely for that license separation — do not inline
it into source.

## Provenance

| Field | Value |
|---|---|
| Retrieved (UTC) | 2026-07-05T13:01:20Z |
| Endpoint | `https://overpass-api.de/api/interpreter` (form-encoded POST) |
| OSM data basis (`osm3s.timestamp_osm_base`) | 2026-07-05T12:59:30Z |
| Raw response size | 3,283,892 bytes |
| Raw response sha256 | `f6515acc10c09d9a989925b5304c6c50ab576af979bfffabad31e7238b4369d0` |
| Raw element count (ways) | 5,931 |
| Emitted CSV rows | 6,813 (0 ways skipped; long ways arc-length sampled ~100 m, so a way can emit several rows sharing its `way_id`; 1,061 rows carry an honest BLANK bearing — closed/near-closed or curved ways whose chord cannot describe the deck) |
| Generator | `tool/generate_bridge_asset.dart` (curvature-aware emission, 2026-07-05) |

Count cross-checks, same endpoint, same day (both HTTP 200): any
`bridge=*` value in the same drivable class → 5,932 ways; `bridge=yes`
with ANY `highway` value (footway/path/service etc. included) → 8,569
ways. A prior "~8,031 bridges" magnitude estimate corresponds to that
broader class, not to this asset's drivable-class filter.

## Query (verbatim)

```
[out:json][timeout:180];
area["ISO3166-2"="JP-05"]->.akita;
way(area.akita)["bridge"="yes"]["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link)$"];
out geom;
```

## Columns

`way_id,lat,lon,bearing_deg` — one row per SAMPLE POINT on the way's
polyline (arc-length sampled every ~100 m; 5 dp), and the great-circle
bearing first→last node folded to [0,180) (undirected road bearing, used to
distinguish a bridge ON the route from an overpass CROSSING it). The
bearing field is BLANK when the chord cannot honestly describe the deck —
a closed/near-closed way (loop/roundabout deck) or a curved way whose local
segment bearings deviate from the chord beyond the matcher's ±30° gate; the
route matcher keeps bearing-less in-corridor sites (fail toward warning).
Sample points lie ON the deck by construction (never the node-mean
centroid, which a curved deck pulls off the deck).
