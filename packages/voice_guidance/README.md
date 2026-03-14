# voice_guidance

Engine-agnostic voice guidance foundation for turn announcements and safety
warnings in driver-assisting navigation flows.

`voice_guidance` provides a small abstraction over text-to-speech (TTS) so the
navigation domain can remain independent from platform TTS APIs.

## Features

- `TtsEngine` interface for pluggable speech engines.
- `FlutterTtsEngine` implementation using `flutter_tts`.
- `NoOpTtsEngine` for tests and non-audio environments.
- `VoiceGuidanceConfig` for runtime voice settings.

## Install

```yaml
dependencies:
  voice_guidance: ^0.1.0
```

## Quick Start

```dart
import 'package:voice_guidance/voice_guidance.dart';

final tts = FlutterTtsEngine();
await tts.setLanguage('ja-JP');
await tts.setVolume(1.0);
await tts.speak('300 meters ahead, turn right.');
```

## API Overview

| API | Purpose |
|-----|---------|
| `TtsEngine` | Abstract speech interface |
| `FlutterTtsEngine` | Real platform speech implementation |
| `NoOpTtsEngine` | Silent fallback for CI/tests |
| `VoiceGuidanceConfig` | Runtime voice behavior configuration |

## License

BSD-3-Clause - see [LICENSE](LICENSE).
