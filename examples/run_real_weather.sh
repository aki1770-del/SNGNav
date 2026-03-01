#!/bin/bash
# run_real_weather.sh — Real weather data from Open-Meteo
#
# Uses live weather data for Nagoya (35.18°N, 136.91°E):
#   Weather:  Open-Meteo API (no API key required, 5-minute poll)
#   Location: Simulated drive (shows weather on route)
#   Routing:  Pre-built demo route
#   Tiles:    Online OSM
#   DR:       Kalman filter
#
# The weather status bar shows real temperature, precipitation, and
# visibility for the Nagoya region. If conditions are hazardous
# (heavy snow, ice risk, low visibility), the safety overlay activates.
#
# Requires network access to:
#   - api.open-meteo.com (weather data)
#   - tile.openstreetmap.org (map tiles)
#
# Usage:
#   ./examples/run_real_weather.sh

set -e
cd "$(dirname "$0")/.."

flutter run -d linux -t lib/snow_scene.dart \
  --dart-define=WEATHER_PROVIDER=open_meteo \
  --dart-define=LOCATION_PROVIDER=simulated \
  --dart-define=ROUTING_ENGINE=mock \
  --dart-define=DEAD_RECKONING=true \
  --dart-define=DR_MODE=kalman
