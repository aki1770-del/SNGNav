# Offline Map Tiles

Place MBTiles files here for offline map rendering.

## Generate Chubu Region Tiles

```bash
sudo apt install tilemaker
wget https://download.geofabrik.de/asia/japan/chubu-latest.osm.pbf
tilemaker --input chubu-latest.osm.pbf \
          --output data/offline_tiles.mbtiles \
          --config resources/config-openmaptiles.json \
          --process resources/process-openmaptiles.lua
```

Expected output: ~28 MB, zoom levels 10-14.

## Run with Offline Tiles

```bash
flutter run -d linux -t lib/snow_scene.dart \
  --dart-define=TILE_SOURCE=mbtiles \
  --dart-define=MBTILES_PATH=data/offline_tiles.mbtiles
```

Without an MBTiles file, the app falls back to online OpenStreetMap tiles.
