#!/bin/bash
# run_demo.sh — Full demo with simulated weather scenario
#
# Shows the 6-phase Nagoya mountain pass weather progression:
#   Phase 0: Clear sky
#   Phase 1: Light snow
#   Phase 2: Moderate snow
#   Phase 3: Heavy snow (HAZARD badge)
#   Phase 4: Ice risk (ICE badge + safety alert dialog)
#   Phase 5: Clearing
#
# Location: Simulated drive from Sakae Station to Higashiokazaki Station
# Routing:  Pre-built demo route (8 maneuvers, 38.1 km, 51 min)
# GPS:      Simulated (no hardware required)
# Tiles:    Online OSM (falls back gracefully if offline)
# DR:       Kalman filter (4D EKF)
#
# Usage:
#   ./examples/run_demo.sh
#
# Prerequisites:
#   flutter pub get

set -e
cd "$(dirname "$0")/.."

flutter run -d linux -t lib/snow_scene.dart \
  --dart-define=WEATHER_PROVIDER=simulated \
  --dart-define=LOCATION_PROVIDER=simulated \
  --dart-define=ROUTING_ENGINE=mock \
  --dart-define=DEAD_RECKONING=true \
  --dart-define=DR_MODE=kalman
