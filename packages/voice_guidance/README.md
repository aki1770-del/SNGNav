# voice_guidance

Engine-agnostic voice guidance foundation for turn announcements and safety
warnings in driver-assisting navigation flows.

`voice_guidance` provides a small abstraction over text-to-speech (TTS) so the
navigation domain can remain independent from platform TTS APIs.

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
  voice_guidance: ^0.1.0
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

## License

BSD-3-Clause - see [LICENSE](LICENSE).
