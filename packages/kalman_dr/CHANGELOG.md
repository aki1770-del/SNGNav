# Changelog

## 0.1.3

- Added an explicit install section to README for pub.dev onboarding.
- Added an API overview table to README for core Kalman filter types.

## 0.1.2

- Added `example/main.dart` showing Kalman predict/update flow.
- Added cross-links to sibling packages (routing_engine, driving_weather) in README.
- Expanded README sibling links to the full 10-package SNGNav ecosystem.

## 0.1.1

- Improved package discoverability: added tunnel, urban canyon, and position estimation context to description.
- Added `positioning` topic.

## 0.1.0

- Initial release.
- 4D Extended Kalman Filter: latitude, longitude, speed, heading.
- Covariance-driven accuracy reporting with configurable degradation.
- Linear dead reckoning mode for lightweight fallback.
- DeadReckoningProvider wraps any LocationProvider (decorator pattern).
- Safety cap at 500m accuracy — stops updating when exceeded.
- Pure Dart implementation, no native dependencies.
