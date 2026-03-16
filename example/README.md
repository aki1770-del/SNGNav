# SNGNav Example

This example app shows the core SNGNav package composition in one runnable
desktop flow:

- `offline_tiles` for MBTiles-or-network map tiles
- `map_viewport_bloc` for follow and overview camera state
- `routing_bloc` for route lifecycle and progress UI
- `navigation_safety` for advisory overlay alerts
- `driving_weather` for simulated weather updates

## Run

```bash
cd example
flutter pub get
flutter run -d linux
```

On Linux, voice guidance uses Speech Dispatcher through `spd-say` when that
command is installed on the system.

Optional offline tiles:

- Place an MBTiles file at `../data/offline_tiles.mbtiles`
- If the file is absent, the example falls back to OpenStreetMap network tiles

## Demo Flow

1. The app requests a mock route from Nagoya Station to Mikawa Highlands.
2. The map fits the route and starts navigation progress.
3. Use `Advance Maneuver` to move through the route.
4. Use `Simulate Deviation` to trigger reroute state.
5. Weather updates rotate through a mountain-pass snow scenario and raise safety alerts when conditions become hazardous.# example

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
