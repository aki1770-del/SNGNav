# Changelog

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
