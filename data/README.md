# Offline Map Tiles

Place MBTiles files here for offline map rendering.

## The camera follows YOUR archive

The reference entrypoint (`lib/main.dart`) reads the archive's own `metadata`
table and opens the map where the archive says it covers:

| metadata key | what the app does with it |
|---|---|
| `center` (`lon,lat,zoom`) | the view the map opens at |
| `bounds` (`left,bottom,right,top`) | used as the centre when `center` is absent or falls outside them |
| `minzoom` | becomes the map's **minimum** zoom — see below |
| `maxzoom` | raises the map's maximum zoom if it is higher than the default |

**You do not have to configure the camera. Drop in an archive for any region
and the map opens there.** If the archive says nothing, the map falls back to
Nagoya Station at zoom 11 — the documented demo view.

**Why `minzoom` becomes a hard floor.** Tile lookup walks *down* in zoom looking
for a parent tile to crop, never up. One step below the archive's lowest stored
zoom there is nothing to find and the map goes blank. Zooming past the top is
fine — you get a blurry upscale, not an empty screen. So the floor is enforced
and the ceiling is not.

## The badge tells you which of four things is true

| badge | meaning |
|---|---|
| `OFFLINE MAP` (green) | every tile in the current view comes from your archive |
| `MAP: PARTIAL` | some of the view is in the archive and some is not |
| `MAP: NOT HERE` | an archive is open and holds nothing for this view |
| `NO OFFLINE MAP` | no archive was opened |

It is recomputed as you pan and zoom, and it is a query against the archive —
not a check that the file exists.

## The archive that ships in this directory

`offline_tiles.mbtiles` — **1.7 MB, zoom levels 10–12, 43 tiles**, covering
`136.70,35.00` to `137.05,35.32` (Nagoya / Toyota City). It is a small review
bundle, not a production tileset.

*(Measured 2026-08-29. This section previously read "Expected output: ~28 MB,
zoom levels 10-14", which described an archive that is not the one in this
directory.)*

## Generate your own

```bash
sudo apt install tilemaker
wget https://download.geofabrik.de/asia/japan/chubu-latest.osm.pbf
tilemaker --input chubu-latest.osm.pbf \
          --output data/offline_tiles.mbtiles \
          --config resources/config-openmaptiles.json \
          --process resources/process-openmaptiles.lua
```

Set `center`, `bounds`, `minzoom` and `maxzoom` in the output's `metadata`
table — the app reads all four.

## Run with offline tiles

**Reference entrypoint** — reads `data/offline_tiles.mbtiles` by path, no
defines needed:

```bash
flutter run -d linux
```

**Full product demo** (`lib/snow_scene.dart`) — this one is configured by
`--dart-define`:

```bash
flutter run -d linux -t lib/snow_scene.dart \
  --dart-define=TILE_SOURCE=mbtiles \
  --dart-define=MBTILES_PATH=data/offline_tiles.mbtiles
```

⚑ **The two entrypoints do not share this configuration.** `TILE_SOURCE` and
`MBTILES_PATH` are read by `snow_scene.dart` only; `lib/main.dart` uses the
fixed path above and ignores both. Passing them to `flutter run` without `-t`
sets values nothing reads.

Without an MBTiles file, `snow_scene.dart` falls back to online OpenStreetMap
tiles. `lib/main.dart` does the same only when no archive is present; once an
archive opens it stays offline, so a tile the archive lacks stays blank rather
than silently reaching for a network that may not exist.

## Troubleshooting

**`Failed to load dynamic library 'libsqlite3.so'`** — the versioned
`libsqlite3.so.N` is almost certainly present; the *unversioned* symlink the
loader asks for is not. On Debian/Ubuntu it ships in `libsqlite3-dev`, not in
the runtime package:

```bash
sudo apt install libsqlite3-dev     # desktop
```

On a minimal or embedded rootfs, add the symlink (or point
`LD_LIBRARY_PATH` at a directory containing one).
