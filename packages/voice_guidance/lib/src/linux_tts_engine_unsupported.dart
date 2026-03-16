library;

import 'noop_tts_engine.dart';

/// Non-IO fallback that keeps the API available on unsupported targets.
class LinuxTtsEngine extends NoOpTtsEngine {}