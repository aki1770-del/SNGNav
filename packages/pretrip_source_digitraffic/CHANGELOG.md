# Changelog

## 0.2.3

- **Take pretrip_decision_advisor ^0.5.0.** The previous `^0.4.0` pin silently
  excluded the 0.5.x line — hosted consumers of this adapter never received
  the black-ice window and route-corridor bridge-icing pre-trip warnings
  (橋は路面より先に凍結します) shipped there. No behavior change in this
  package itself; the constraint widening is the release.


## 0.2.2 — 2026-06-29 — Docs: remove stray tool-markup lines

- Docs: remove stray tool-markup lines that rendered on the pub.dev page. No source change.

## 0.2.1 — 2026-06-26 — Docs: dev-first on-ramp

- The README now leads with what-it-is, a `dart pub add pretrip_source_digitraffic`
  line, and a run-verified `## Quick start` snippet (byte-identical to
  `example/quickstart.dart`, verified live against the Digitraffic API), followed
  by what the developer gets back. All governance / mission / HER-trace / safety
  / sibling / endpoint prose is preserved verbatim, moved below under
  `## Background & provenance`.
- The prior `## Usage` snippet (which referenced an undeclared `forecast`) is now
  the "Merge onto a forecast" example under Background with a clarifying comment;
  the runnable `example/main.dart` remains the complete merge demo.
- Docs-only change; no public API, behaviour, or dependency change.

## 0.2.0 — 2026-06-24 — Re-pin advisor to ^0.4.0 (catalog resolvability)

- Shifts the `pretrip_decision_advisor` requirement from the 0.2.x range to the
  0.4.x range; advisor 0.2.x/0.3.x are no longer supported by this version. This
  package's own public API is unchanged. Minor bump because the resolution
  requirement is consumer-affecting.
- The published `pretrip_decision_advisor` 0.4.0 is live on pub.dev; the
  original `^0.2.0` constraint was incompatible with it and blocked edge
  developers from `pub add`-ing this source together with the current advisor
  in a single project.
- The `VisibilityObservation` measurement contract this package emits is
  unchanged across advisor 0.2.0 → 0.4.0.

## 0.1.0 — 2026-06-14 — Initial extraction

- Extracted `DigitrafficVisibilityProvider` from the SNGNav app
  (`lib/providers/digitraffic_visibility.dart`) into a standalone pure-Dart
  package under the new `pretrip_source_*` namespace.
- Fetches the nearest fresh measured road-network visibility (`NÄKYVYYS_M`,
  metres; falls back to `NÄKYVYYS_KM` × 1000) from Fintraffic's open
  Digitraffic road-weather network and emits a source-neutral
  `VisibilityObservation` (owned by `pretrip_decision_advisor` ^0.2.0).
- Runtime dependencies: `http` + `pretrip_decision_advisor` only. No Flutter.
- Safety contract preserved verbatim (see README.md): visibility is never
  estimated; an observation is valid for the departure hour only; `null` is the
  driver's own judgment, never a fabricated hazard.
- Sibling package: `condition_aggregator_digitraffic` (same upstream provider,
  emits a WARNING `Advisory`; this package emits a MEASUREMENT).
