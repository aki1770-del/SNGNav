# Changelog

## 0.0.8

**Documentation only. No code change. Two corrections. The first is about what a driver can be shown: the README said per-provider errors let the integrator surface staleness honestly. They do not. `result.providerErrors` names sources that could not be read, which is an outage; a source that keeps answering with a document that has stopped being updated raises no error at all. The second: earlier versions said a monthly watch tracked JIS / JASO standard updates. No output from that watch has been found, so the safety-boundary record no longer says so.**

A third, smaller correction: the README said this package's runtime dependencies
are wired by path. In the published package they are ordinary pub.dev
dependencies, and have been since 0.0.5. The line now says so. The dependency
constraints themselves are unchanged from 0.0.7.

Documentation and comments that used this project's internal shorthand now say
the same thing in plain words. No fact in them changed.

- `README.md`: the pass-through note above; the dependency-posture line; two
  headings.
- `SAFETY_BOUNDARY.md`: the JIS / JASO sentence corrected; elsewhere the changed
  lines lost internal names and references only. No boundary moved.
- `lib/condition_aggregator_nws.dart`: one doc comment.
- `pubspec.yaml`: the version.
- `CHANGELOG.md`: this entry.

The one changed Dart file was compared with the published 0.0.7 after removing
comments: the token streams are identical. Apart from the files listed above,
the published files are identical to 0.0.7.

## 0.0.7 — 2026-06-30 — Doc honesty

- Docs: library dartdoc no longer claims `Phase: explore` /
  `publish_to: none`; corrected to reflect the published-to-pub.dev state.
  No code change.

## 0.0.6 — 2026-06-14 — Dependency hygiene

- Track latest `condition_aggregator` (`^0.0.4`→`^0.0.5`) + `noaa_nws_adapter` (`^0.0.3`→`^0.0.5`).
- No source or behaviour change.


## 0.0.5

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.0.4 — 2026-05-10 — Pana score recovery (Theme α P3)

- Trim pubspec `description` to within the pana 60–180 character target.
- Add minimal `example/main.dart` for pana documentation scoring.
- Apply `dart format` to clear any formatter findings.
- No SDK source changes; metadata + format pass only.


## 0.0.3 — 2026-05-10 — Refresh stale dependency constraints

- `condition_aggregator: ^0.0.1` → `^0.0.3` (pre-existing 7-day-stale).
- `noaa_nws_adapter: ^0.0.1` → `^0.0.3` (pre-existing 7-day-stale).
- No source changes; pubspec dep-constraint refresh only.

## 0.0.2 — 2026-05-03

- Switch `condition_aggregator` and `noaa_nws_adapter` from path
  dependencies to hosted pub.dev dependencies (`^0.0.1` for each).
  No source change.

## 0.0.1 — 2026-05-03

Initial publish.

- `NwsAdvisoryProvider` implementation of
  `AdvisoryProvider` for the NOAA / NWS active-winter-alerts feed.
- `mapWinterAlertToAdvisory(WinterAlert) → Advisory` field-by-field
  mapping, exposed at top level for direct test invocation.
- 9 tests covering severity gradient, area + verbatim wording
  preservation, effective + expires window mapping (incl. nullable
  semantics), certainty + urgency direct enum mapping, construction
  + init-no-op.
- BSD-3-Clause license (matches the rest of SNGNav).
- Pure Dart, no Flutter dependency.
- Depends on `condition_aggregator` (interface) and
  `noaa_nws_adapter` (raw NWS HTTP+GeoJSON wrapper).
