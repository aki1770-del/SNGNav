# DRIVER_VOICES.md

A listening log for the SNGNav project. Records — anonymized, with source URL — public statements from drivers / app developers serving drivers / domain practitioners that inform what SNGNav builds.

## Why this file exists

The 2026-04-27 target-drivers research synthesis (`UNTITLED/outputs/research/target_drivers_2026_04_27_vaa_synthesis.md` in the development workspace) surfaced one largest-leverage gap: **the unit doesn't actually KNOW drivers; it knows what's published about them.** Three research perspectives (strategic, ADAS, ecosystem) named the gap independently.

This file closes that gap from the LISTENING side. It does not close it by extracting attention from drivers (asking them to share their experiences) — that would be the same V96-violation that today's session ratified rescinding for cold-tooling outreach. Instead, this file records what drivers + their developers ALREADY say in public, so when the unit makes a build decision, the decision is informed by their actual voices rather than only by inferred-from-statistics personas.

## What gets recorded here

Public statements only. Specifically:
- GitHub issues + PRs on Flutter / navigation / driving / weather / mapping / safety repositories
- Public blog posts
- Conference talks (with public recording or transcript)
- Documentation we read in the course of building
- Public chat-channel statements (where the channel itself is public-archive)
- Published papers / industry reports (with proper citation)

Not recorded:
- Private DMs or emails
- Solicited interviews (we don't solicit)
- Anonymous surveys (we don't conduct)
- Reconstructed-from-memory paraphrases (Verify-First: only what we can cite)

## Format per entry

```markdown
### [YYYY-MM-DD] Brief topic-line

**Source**: <URL>
**Speaker context** (anonymized): <e.g., "Flutter package maintainer in Sapporo region", "snow-zone municipal road-safety researcher", "ageing-driver advocacy group spokesperson">
**Substance** (≤200 words, paraphrased or quoted with attribution):
> ...

**V92 question**: which loom in SNGNav's portfolio (or potential portfolio) is made-absent by this voice? If the absence-of-loom would have caused this voice's experience, the loom is queued for build.

**VAA disposition**: build queue addition / informs existing build / no action / hold for cluster
```

## Listening surfaces — where to look

These are the public places where drivers / developers / domain practitioners speak about navigation + driving + safety + snow-zone realities. We watch passively; we do not post to provoke voices.

- GitHub issues on `flutter_map` and its plugins (`flutter_map_tile_caching`, `flutter_map_pmtiles`, etc.)
- GitHub issues on routing engines (`osrm`, `valhalla`)
- GitHub issues on `flutter_tts`, `flutter_background_geolocation`, `geolocator`
- GitHub issues on Japan-specific nav-related repos (search: `language:dart geo OR navigation OR routing`)
- Flutter community discussions on Discord public channels + r/FlutterDev
- Japan Flutter community gatherings (public meeting notes if available)
- Snow-zone municipal road-safety research published by Hokkaido / Tohoku universities
- JAMA / MLIT public publications on driver behavior + ADAS
- Toyota / Subaru / Honda public engineer blog posts on smartphone-nav HMI

## Cadence

No required cadence. Voices are recorded when encountered in the course of normal work. The watching is opportunistic; the recording is disciplined when the watch surfaces something.

## Cross-references

- Listening discipline doctrine: VAA prompt Listen Frame at `skills/vision-alignment-auditor/prompt.md` (in the masterplan workspace)
- Source synthesis: `UNTITLED/outputs/research/target_drivers_2026_04_27_vaa_synthesis.md`
- Build queue (where loom-additions land): WOW v1 master at `UNTITLED/outputs/governance_transformation/spa_actuator_way_of_working_v1.md`

---

## Recorded voices

(empty as of 2026-04-27 — first listening session pending)
