# Contributing to SNGNav Snow Scene

Thank you for your interest. This guide explains how to add new providers,
write tests, and submit changes.

If this is your first contribution, start with one of these:

- documentation drift or broken links
- provider or package README examples
- tests for an existing provider edge case
- small integration fixes that preserve the driver-assisting safety boundary

If you are reporting a bug or proposing a feature, use the GitHub issue
templates first so the expected environment, failure mode, and user value are
captured up front.

---

## How the Provider System Works

SNGNav uses four abstract provider interfaces. BLoCs depend on the
interfaces, not the implementations. You can add a new data source
without modifying any BLoC code.

```
--dart-define flag  →  ProviderConfig  →  creates provider  →  injected into BLoC
```

The 4 provider interfaces:

| Interface | Stream type | Implementations |
|-----------|-------------|-----------------|
| `LocationProvider` | `Stream<GeoPosition>` | `SimulatedLocationProvider`, `GeoClueLocationProvider` |
| `WeatherProvider` | `Stream<WeatherCondition>` | `SimulatedWeatherProvider`, `OpenMeteoWeatherProvider` |
| `RoutingEngine` | `Future<RouteResult>` | `OsrmRoutingEngine`, `ValhallaRoutingEngine` |
| `FleetProvider` | `Stream<FleetReport>` | `SimulatedFleetProvider` |

---

## Adding a New Provider (Step by Step)

This example adds a hypothetical `AccuWeatherProvider`.

### 1. Implement the interface

Create `lib/providers/accuweather_provider.dart`:

```dart
import '../models/weather_condition.dart';
import 'weather_provider.dart';

class AccuWeatherProvider implements WeatherProvider {
  final StreamController<WeatherCondition> _controller =
      StreamController<WeatherCondition>.broadcast();

  @override
  Stream<WeatherCondition> get conditions => _controller.stream;

  @override
  Future<void> startMonitoring() async {
    // Start polling AccuWeather API.
    // On HTTP failure, re-emit the last known condition
    // so the driver sees stale-but-present data.
  }

  @override
  Future<void> stopMonitoring() async {
    // Stop polling.
  }

  @override
  void dispose() {
    _controller.close();
  }
}
```

**Offline rule**: when the upstream source is unreachable, re-emit the last
known value rather than letting the stream go silent. The driver should see
stale data, not a blank widget.

### 2. Register in ProviderConfig

Edit `lib/config/provider_config.dart`:

```dart
// Add to the enum:
enum WeatherProviderType {
  simulated,
  openMeteo,
  accuWeather,  // ← new
}

// Add to createWeatherProvider():
case WeatherProviderType.accuWeather:
  return AccuWeatherProvider(apiKey: apiKey);

// Add to _parseWeatherType():
case 'accuweather':
  return WeatherProviderType.accuWeather;
```

### 3. Add a `--dart-define` value

Your provider is now selectable:

```bash
flutter run -d linux -t lib/snow_scene.dart \
  --dart-define=WEATHER_PROVIDER=accuweather
```

### 4. Write tests

Create `test/providers/accuweather_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_snow_scene/providers/accuweather_provider.dart';

void main() {
  group('AccuWeatherProvider', () {
    late AccuWeatherProvider provider;

    setUp(() {
      provider = AccuWeatherProvider(/* test config */);
    });

    tearDown(() {
      provider.dispose();
    });

    test('emits conditions after startMonitoring', () async {
      await provider.startMonitoring();
      expect(provider.conditions, emitsThrough(isA<WeatherCondition>()));
    });

    test('stopMonitoring stops emissions', () async {
      await provider.startMonitoring();
      await provider.stopMonitoring();
      // Verify no further emissions.
    });
  });
}
```

### 5. Run the full test suite

```bash
flutter test
```

Run the root suite plus any affected package suites. Treat the live test run as
authoritative when README or document statistics drift.

---

## Test Conventions

- **File location**: mirrors `lib/` structure under `test/`
  - `lib/providers/foo.dart` → `test/providers/foo_test.dart`
- **Doc header**: every test file starts with a `///` block describing what's
  tested, followed by a `library;` directive. Template:
  ```dart
  /// ClassName unit tests — one-line summary.
  ///
  /// Tests:
  ///   - Group: test name, test name, ...
  ///   - Group: test name, test name, ...
  library;
  ```
- **Group structure**: one top-level `group()` per class
- **setUp/tearDown**: create and dispose the subject in every group
- **No test interdependence**: each test is self-contained
- **Test data**: use factory helpers or `const` fixtures at the top of the
  file. Avoid duplicating setup across unrelated test files.
- **Mock strategy**: use `mocktail` for HTTP clients and D-Bus. Use
  `MockClient` from `package:http/testing.dart` for routing engine tests.
  Prefer constructor injection (`client:` parameter) over global mocking.
- **BLoC tests**: use `bloc_test` package for event → state assertions
- **Golden tests**: widget goldens go in `test/widgets/goldens/`

### Test categories

| Category | Directory | What to test |
|----------|-----------|-------------|
| Unit | `test/providers/`, `test/models/` | Provider contracts, model edge cases |
| BLoC | `test/bloc/` | State transitions, event handling |
| Widget | `test/widgets/` | Rendering, user interaction, golden images |
| Integration | `test/integration/` | Cross-BLoC safety flows |
| Config | `test/config/` | Flag parsing, factory methods |

---

## Project Structure

```
lib/
├── bloc/        BLoCs (do NOT modify for new providers)
├── config/      ProviderConfig (edit here to register new providers)
├── models/      Data classes (extend if your provider needs new fields)
├── providers/   Provider interfaces + implementations (add here)
├── services/    Consent, hazard aggregation
└── widgets/     UI (do NOT modify for new providers)
```

**Key principle**: adding a provider should only touch `lib/providers/`
and `lib/config/provider_config.dart`. If you find yourself editing
a BLoC or widget, the interface may need extending — open an issue first.

---

## Safety

Read [SAFETY.md](SAFETY.md) before contributing. Key rules:

- This is a display-only navigation aid (ASIL-QM). No vehicle control.
- The `SafetyOverlay` widget has 5 non-negotiable rules. Do not bypass them.
- Dead reckoning positions are estimates. Always show accuracy indicators.
- Safety alerts are advisory. Never suppress them.

---

## Submitting Changes

1. Fork the repository
2. Create a feature branch: `git checkout -b add-accuweather-provider`
3. Write your implementation + tests
4. Run `flutter test` — all tests must pass
5. Run `flutter analyze` — zero issues required
6. Open a pull request with:
   - What provider you added and why
   - Which `--dart-define` flag activates it
   - Test count before and after

For documentation-only pull requests, replace the test delta with a short note
describing what reader friction or drift you removed.

---

## Code Style

- Follow `flutter_lints` (already configured in `analysis_options.yaml`)
- Dartdoc comments on all public APIs
- Provider doc comments should describe offline behavior
- Keep provider implementations independent — no provider-to-provider imports

## License

By contributing, you agree that your contributions will be licensed
under the same license as this project.
