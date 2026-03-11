# Demo Screenshot Plan

Round 3 screenshot handoff for Sprint 56.

## Capture Targets

| File | What it should show | How to reach it |
|------|----------------------|-----------------|
| `route-overview.png` | Route overview with maneuver markers visible after auto-fit | Launch the full demo profile and capture immediately after the route enters `NAVIGATING` |
| `snow-zone-active.png` | Snow-zone polygon aligned to the mountain-pass route segment during snow | Let the scenario progress until the phase indicator shows a snow state |
| `safety-alert.png` | Safety overlay visible during hazardous weather or ice risk | Hold on `Heavy Snow — Pass Summit` or `Ice Risk — Pass Descent` |

## Recommended Launch Command

```bash
flutter run -d linux -t lib/snow_scene.dart \
  --dart-define=WEATHER_PROVIDER=simulated \
  --dart-define=LOCATION_PROVIDER=simulated \
  --dart-define=ROUTING_ENGINE=mock \
  --dart-define=TILE_SOURCE=mbtiles \
  --dart-define=MBTILES_PATH=data/offline_tiles.mbtiles \
  --dart-define=DEAD_RECKONING=true \
  --dart-define=DR_MODE=kalman
```

## Operator Notes

- Use the app-bar pause button to freeze the maneuver timer before each shot.
- Use `Fit route` before the overview screenshot if the camera has drifted.
- Keep the navigation status chip visible in the frame when practical.
- Store the final PNG files in this directory using the filenames above.