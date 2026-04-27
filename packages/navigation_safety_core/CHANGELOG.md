# Changelog

## 0.1.0 — 2026-04-27

Initial release.

Pure Dart core extracted from `navigation_safety` so non-Flutter
consumers (CLI tools, servers, test fixtures, pure-Dart packages
like `driving_conditions`) can depend on the safety-model vocabulary
without inheriting Flutter + flutter_bloc.

Exports:

- `AlertSeverity` (info / warning / critical; declaration order is load-bearing)
- `NavigationRoute`
- `NavigationSafetyConfig`
- `SafetyScenario`
- `SafetyScore`

The full `navigation_safety` Flutter package re-exports everything
here for back-compatibility.
