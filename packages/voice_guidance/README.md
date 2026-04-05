# voice_guidance

[![pub package](https://img.shields.io/pub/v/voice_guidance.svg)](https://pub.dev/packages/voice_guidance)
[![CI](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml/badge.svg)](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/aki1770-del/SNGNav/blob/main/LICENSE)

**"300 meters ahead, turn right."** Platform-agnostic voice guidance for
navigation — works on mobile (flutter_tts), Linux (spd-say), and silently in
CI.

`voice_guidance` provides a small TTS abstraction so your navigation domain
stays independent from platform speech APIs.

## Features

- `TtsEngine` interface for pluggable speech engines.
- `FlutterTtsEngine` implementation using `flutter_tts`.
- `LinuxTtsEngine` implementation using `spd-say` on Linux.
- `NoOpTtsEngine` for tests and non-audio environments.
- `createDefaultTtsEngine()` to pick a safe engine per platform.
- `VoiceGuidanceConfig` for runtime voice settings.

## Install

```yaml
dependencies:
  voice_guidance: ^0.3.0
```

## Quick Start

```dart
import 'package:voice_guidance/voice_guidance.dart';

final tts = createDefaultTtsEngine();
await tts.setLanguage('ja-JP');
await tts.setVolume(1.0);
await tts.speak('300 meters ahead, turn right.');
```

On Linux, `createDefaultTtsEngine()` uses `spd-say` when it is available and
degrades silently when it is not installed.

## API Overview

| API | Purpose |
|-----|---------|
| `TtsEngine` | Abstract speech interface |
| `createDefaultTtsEngine()` | Platform-safe default engine selection |
| `FlutterTtsEngine` | Real platform speech implementation |
| `LinuxTtsEngine` | Speech Dispatcher (`spd-say`) backend for Linux |
| `NoOpTtsEngine` | Silent fallback for CI/tests |
| `VoiceGuidanceConfig` | Runtime voice behavior configuration |

## Works With

| Package | How |
|---------|-----|
| [routing_bloc](https://pub.dev/packages/routing_bloc) | Route lifecycle events trigger maneuver announcements |
| [navigation_safety](https://pub.dev/packages/navigation_safety) | Safety alerts trigger spoken hazard warnings |
| [routing_engine](https://pub.dev/packages/routing_engine) | Route maneuver text is the source material for voice announcements |

## See Also

- [kalman_dr](https://pub.dev/packages/kalman_dr) — Dead reckoning through GPS loss
- [driving_weather](https://pub.dev/packages/driving_weather) — Weather conditions that trigger hazard speech
- [offline_tiles](https://pub.dev/packages/offline_tiles) — Offline tile management with MBTiles

Part of [SNGNav](https://github.com/aki1770-del/SNGNav) — 11 packages for
offline-first navigation on Flutter.

## License

BSD-3-Clause — see [LICENSE](LICENSE).
