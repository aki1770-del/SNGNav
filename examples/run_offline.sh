#!/bin/bash
# run_offline.sh — Fully offline configuration (no network required)
#
# Everything runs from local data:
#   Weather:  Simulated 6-phase scenario
#   Location: Simulated drive (Route 153)
#   Routing:  Pre-built demo route
#   Tiles:    MBTiles file (Chubu region, zoom 10-14)
#   DR:       Kalman filter
#
# Before first run, place MBTiles file:
#   cp /path/to/offline_tiles.mbtiles data/offline_tiles.mbtiles
#
# To generate your own tiles:
#   sudo apt install tilemaker
#   wget https://download.geofabrik.de/asia/japan/chubu-latest.osm.pbf
#   tilemaker --input chubu-latest.osm.pbf \
#             --output data/offline_tiles.mbtiles \
#             --config resources/config-openmaptiles.json \
#             --process resources/process-openmaptiles.lua
#
# Usage:
#   ./examples/run_offline.sh
#
# If no MBTiles file is found, the app falls back to online OSM tiles.

set -e
cd "$(dirname "$0")/.."

flutter run -d linux -t lib/snow_scene.dart \
  --dart-define=WEATHER_PROVIDER=simulated \
  --dart-define=LOCATION_PROVIDER=simulated \
  --dart-define=ROUTING_ENGINE=mock \
  --dart-define=TILE_SOURCE=mbtiles \
  --dart-define=MBTILES_PATH=data/offline_tiles.mbtiles \
  --dart-define=DEAD_RECKONING=true \
  --dart-define=DR_MODE=kalman
