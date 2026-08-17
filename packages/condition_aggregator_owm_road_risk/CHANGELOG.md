# Changelog

## 0.1.5

### If you are on 0.1.4 or earlier, this is what you already have

Three of these are silent. Nothing in 0.1.4 logs, throws, or otherwise tells you
they happened, so please read this section rather than the fix list below.

1. **A response you could not read came back to you as an all-clear.** If the
   publisher answered and *every* alert entry in the answer was malformed — an
   `alerts` value that was not an array, an alert that was not an object — 0.1.4
   discarded them all and returned an empty list. The `AdvisoryProvider`
   contract defines an empty list as *"no advisories are active at this point"*.
   So a read that failed arrived at your code as a measurement that the road was
   clear. If you have been treating an empty result as "nothing to warn about",
   that conclusion was not always earned.

2. **A partial read arrived as a complete one.** With three good alerts and one
   malformed, 0.1.4 returned the three and said nothing about the fourth. There
   was no field to inspect and no exception to catch; the discarded entry may
   have been the severe one.

3. **A publisher `event_level` that was not a plain JSON integer crashed past
   your error handling.** `event_level: 3.0` or `event_level: "3"` threw a
   `TypeError`, which is a Dart `Error` and *not* an `Exception`, so
   `on Exception catch` — and the adapter's own documented exception types —
   did not catch it. If you have a `try`/`catch` around this adapter that
   catches `Exception` or the two `OwmRoadRisk*Exception` types, it has a hole.
   Whether you ever hit it depends on what your issuers emit.

4. **An absent `event_level` and a stated `event_level: 0` were the same
   value.** `OwmRoadRiskAlert.eventLevel` read `0` for both, and the two alerts
   compared equal. Severity was never affected — `severityFromEventLevel` maps
   `<= 0` to `AdvisorySeverity.unknown`, so an unstated level has always reached
   `Advisory.severity` honestly. But if you read `alert.eventLevel` from
   `OwmRoadRiskClient.fetchTrack` and thresholded on it (`>= 2`), an unstated
   level sat at the bottom of the scale and was filtered out as mild.

0.1.5 is a patch and stays inside `^0.1.4`, so upgrading requires no constraint
change. It adds API and removes none; every 0.1.4 call site compiles unchanged.

### What changed

**Read failures no longer arrive as measured emptiness.**

- When the publisher's response contained entries and *none* could be read,
  `fetchTrack` / `fetchPoint` / `fetchActiveAdvisoriesAtPoint` now throw
  `OwmRoadRiskParseException` naming the causes, instead of returning `[]`.
- When *some* entries could be read and some could not,
  `fetchActiveAdvisoriesAtPoint` returns the readable advisories **plus** a
  clearly-marked, `minor`-severity incomplete-read notice
  (`Advisory.eventClass == kOwmRoadRiskIncompleteReadEventClass`) so the partial
  read is never presented as complete. The notice is below `isHighImpact`, so an
  integrator rendering only driver-actionable items can filter it out; it uses
  an identity no publisher emits, so it cannot be mistaken for a hazard or
  deduplicated against one. This follows the `condition_aggregator_jma`
  precedent for partial border reads.
- New `OwmRoadRiskClient.fetchTrackRead` / `fetchPointRead` return
  `OwmRoadRiskRead`, which carries the alerts alongside `unreadableEntries`,
  `unreadableCauses`, and `isComplete`. The existing `fetchTrack` / `fetchPoint`
  keep their signatures and return just the alerts.
- A well-formed response is unaffected: a complete read appends no notice, and
  an empty-but-complete answer stays an empty list. A notice on a clean read
  would train you to ignore notices.

**Nothing escapes this adapter as an `Error` any more.**

- `event_level` is now read without a type cast that can throw. A JSON integer
  is taken as-is; a JSON number with no fractional part (`3.0`) is the same
  integer and is taken too. Anything else — a string, a fractional or non-finite
  number, an object — is treated as *not stated* rather than coerced into a
  level. It is never rounded and never defaulted.
- An alert object that cannot be turned into a record at all is counted as an
  unread entry rather than crashing or vanishing.

**An absent level is now carried as absent, not as a number.**

- New `OwmRoadRiskAlert.eventLevelWasReported` (defaults to `true`, so
  directly-constructed alerts keep their previous meaning) and
  `OwmRoadRiskAlert.reportedEventLevel`, which is `null` when the publisher
  stated no level. `null` is off the scale; `0` is the bottom of it. Prefer
  `reportedEventLevel` for any comparison — the analyzer will stop you where
  `eventLevel` would have silently under-warned.
- Equality now distinguishes an unstated level from a stated `0`.
- New `OwmRoadRiskMapper.severityFromAlert(alert)` reads the absence from the
  alert instead of inferring it from the number, and returns
  `AdvisorySeverity.unknown` when no level was stated. `severityFromEventLevel`
  is unchanged and still public.

**Honest bound.** The publisher's road-risk response has no way to say "this
point or hour is outside my coverage", so this adapter cannot distinguish a
declared coverage gap from a genuine all-clear. That distinction is absent at
the wire, and this package does not simulate it. See the README.

### Docs: "safe sentinels" was the wrong doctrine, in a published package

`OwmRoadRiskAlert.fromJson`'s dartdoc claimed the parser is *"tolerant of missing
fields; missing values default to safe sentinels rather than throwing."*

**There is no such thing as a safe sentinel.** The severity path here happens to
be honest already (a missing `event_level` parses as `0`, which
`OwmRoadRiskMapper` maps to `AdvisorySeverity.unknown` — never to a LOW
severity), so this was not a live fabrication. But the sentence is the exact
ideology the Measured-or-Absent contract exists to retire, sitting in a published
package, teaching the next author to do it again.

The doc now states what the code actually does. No behaviour change.

## 0.1.4 — Doc honesty

- Docs: refresh stale README install pins (`condition_aggregator: ^0.0.3 → ^0.0.5` to match the pubspec dependency; self-pin `^0.1.0 → ^0.1.4`).
- Docs: correct the unfulfilled `AdvisorySource` promise — README and dartdoc no longer claim a dedicated OpenWeatherMap enum value "will" be added; they now state the adapter reports `AdvisorySource.other` because the umbrella enum has no OWM value (actual behavior; no enum added).
- Docs: remove the inaccurate "caution-add-only rounding"/"rounds to the lower of the two adjacent CAP buckets" claim from README + mapper dartdoc — `severityFromEventLevel` is a fixed integer→bucket lookup with no runtime rounding step. The conservative cut-point choice is documented accurately.
- Docs: add an OpenWeatherMap data-attribution note (data © OpenWeatherMap, provided under the Open Database License (ODbL) per the OWM pricing/licensing pages; attribution required), distinct from the BSD-3-Clause source-code license.

No code change.

## 0.1.3 — 2026-06-14 — Dependency hygiene

- Track latest `condition_aggregator` (`^0.0.4`→`^0.0.5`).
- No source or behaviour change.


## 0.1.2

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.1.1 — 2026-05-10 — Pana score recovery (Theme α P3)

- Trim pubspec `description` to within the pana 60–180 character target.
- Add minimal `example/main.dart` for pana documentation scoring.
- Apply `dart format` to clear any formatter findings.
- No SDK source changes; metadata + format pass only.


## 0.1.0 — 2026-05-10 — Initial OpenWeatherMap Road Risk adapter

- `OwmRoadRiskClient`: lower-level HTTP client around the publisher's
  `POST /data/2.5/roadrisk` endpoint. Single-point or multi-waypoint
  track requests; returns the publisher's `alerts[]` array as
  typed [OwmRoadRiskAlert] records.
- `OwmRoadRiskProvider`: `AdvisoryProvider` implementation; one-shot
  point query mapped to source-neutral `Advisory` typed events.
  Composes through `AdvisoryAggregator` with sibling adapters
  (`condition_aggregator_jma`, `condition_aggregator_nws`).
- `OwmRoadRiskMapper`: caution-add-only severity bucketing from the
  publisher's `event_level` integer to CAP-class
  `AdvisorySeverity`; verbatim relay of `event` and `description`
  strings per Article 17 (β) discipline.
- Tests run against `MockClient` with a golden response fixture; CI
  does not burn publisher quota.
- Phase: explore. Operators supply their own publisher API key
  (`appid`) at `OwmRoadRiskProvider` construction time; this package
  does not bundle one.
- The umbrella `condition_aggregator` 0.0.3 does not yet name
  OpenWeatherMap as a dedicated `AdvisorySource`; 0.1.0 ships using
  `AdvisorySource.other`. A forward-additive enum bump in
  `condition_aggregator` 0.0.4+ will introduce a dedicated value;
  consumers consuming via `AdvisoryAggregator` see no breaking
  change.
