# EXTRACTING.md — How to Extract a Package from SNGNav

A developer document. Not governance. Based on three real extractions.

## The Pattern

Every extraction follows **G1 → G2 → G3**:

| Gate | What | Pass criteria |
|:----:|-------|---------------|
| **G1** | Package exists, tests pass, pub.dev dry-run clean | `dart pub publish --dry-run` → 0 warnings |
| **G2** | App migrated to use the package, inline copies deleted | `flutter test --exclude-tags=probe` → all pass |
| **G3** | Published to pub.dev | `dart pub publish` → success |

## Before You Start

**Extraction candidates** must be:
- Pure Dart (no Flutter dependency) — maximizes platform reach (all 6)
- Self-contained — no imports from `package:sngnav_snow_scene/`
- Tested — existing tests cover the code being extracted
- Unique on pub.dev — check that no good package already exists for this domain

## G1: Create the Package

### 1. Scaffold

```
packages/
  your_package/
    lib/
      src/
        model.dart
        provider.dart
      your_package.dart    ← barrel export
    test/
    pubspec.yaml
    README.md
    CHANGELOG.md
    LICENSE
    analysis_options.yaml
```

### 2. pubspec.yaml

```yaml
name: your_package
description: >-
  One-line description with search keywords.
  Second line adds context. Pure Dart, no native dependencies.
version: 0.1.0
repository: https://github.com/aki1770-del/sngnav
issue_tracker: https://github.com/aki1770-del/sngnav/issues
topics:
  - topic1
  - topic2
  - topic3

environment:
  sdk: ^3.11.0

dependencies:
  equatable: ^2.0.7    # if using value objects

dev_dependencies:
  test: ^1.25.0
  lints: ^5.1.1
```

**Topics**: max 5. Choose search terms an edge developer would type.

### 3. Copy source files

Copy from `lib/models/` and `lib/providers/` into `lib/src/`. Adjust imports to be package-internal (`import 'model.dart'` not `package:sngnav_snow_scene/...`).

### 4. Barrel export

```dart
// lib/your_package.dart
export 'src/model.dart';
export 'src/provider.dart';
```

### 5. Copy and adapt tests

Copy relevant tests from `test/`. Change imports to `package:your_package/your_package.dart`.

### 6. README.md

Write for a stranger. Include:
- What it does (one paragraph)
- Install (`dart pub add your_package`)
- Quick example (< 20 lines)
- API summary table
- License

### 7. Validate G1

```bash
cd packages/your_package
dart pub get
dart test          # all pass
dart analyze       # no errors
dart pub publish --dry-run   # 0 warnings
```

**G1 passes when**: 0 warnings on dry-run, all tests green.

## G2: Migrate the App

### 1. Add path dependency

In the app's `pubspec.yaml`:

```yaml
dependencies:
  your_package:
    path: packages/your_package
```

### 2. Swap imports

In every file that imports the old inline code, replace:

```dart
// Before
import 'package:sngnav_snow_scene/models/model.dart';
import 'package:sngnav_snow_scene/providers/provider.dart';

// After
import 'package:your_package/your_package.dart';
```

**Find all consumers**:
```bash
grep -rn 'package:sngnav_snow_scene/.*your_file' lib/ test/
```

### 3. Clean barrel files

Remove the old exports from `lib/models/models.dart` and `lib/providers/providers.dart`.

### 4. Delete inline copies

Delete the original files from `lib/models/` and `lib/providers/`.

### 5. Validate G2

```bash
flutter pub get
flutter analyze           # no new errors
flutter test --exclude-tags=probe   # all pass
```

**Also verify zero residue**:
```bash
grep -RInE 'package:sngnav_snow_scene/.*(your_old_file)' lib/ test/
# Must return 0 matches
```

**G2 passes when**: all app tests pass, zero remaining inline imports.

## G3: Publish

```bash
cd packages/your_package
dart pub publish
```

Publisher: aki1770@gmail.com. After publish, update pubspec.yaml to use version constraint instead of path (for CI):

```yaml
# For local development, keep path:
your_package:
  path: packages/your_package

# For pub.dev consumers:
# your_package: ^0.1.0
```

## Extraction History

| # | Package | Sprint | Lines removed | Files deleted | Tests after |
|:-:|---------|:------:|:------------:|:------------:|:-----------:|
| 1 | kalman_dr | 44 | 1,074 | 5 | 908 |
| 2 | routing_engine | 44 | 730 | 4 | 908 |
| 3 | driving_weather | 45 | 535 | 4 | 902 |

**Cumulative**: 2,339 lines of inline duplication removed. 13 files deleted. 3 packages on pub.dev.

## Discovery Checklist (post-publish)

After G3, verify discoverability:

- [ ] Search pub.dev for 3 terms a stranger would use — does your package appear?
- [ ] Description includes search keywords (not just technical terms)
- [ ] Topics are max 5, chosen for search volume
- [ ] README has install command, quick example, API table
- [ ] Cross-link to sibling packages in README (*"See also: kalman_dr, routing_engine, driving_weather"*)
