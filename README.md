# sngnav

[![CI](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/badge/coverage-aggregated%20in%20CI-blue)](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/aki1770-del/SNGNav/blob/main/LICENSE)
[![pub package](https://img.shields.io/pub/v/driving_conditions.svg)](https://pub.dev/packages/driving_conditions)
[![pub package](https://img.shields.io/pub/v/kalman_dr.svg)](https://pub.dev/packages/kalman_dr)

**Snow Guard Navigation** — offline-first navigation architecture for Flutter, running
today on Linux desktop and built toward embedded Linux.

Navigation that doesn't abandon you when conditions fail unexpectedly.

Start here: [ARCHITECTURE.md](ARCHITECTURE.md), [CONTRIBUTING.md](CONTRIBUTING.md), [docs/local_routing.md](docs/local_routing.md), [docs/arm_deployment.md](docs/arm_deployment.md), and [ROADMAP.md](ROADMAP.md). Note that ROADMAP.md's "Current State" section is dated April 2026 and describes a 15-package monorepo; the catalog has grown since, and pub.dev is the current state.

Latest article: [Connecting Flutter to Vehicle Signals: Building a Dart SDK for Eclipse KUKSA](https://dev.to/aki1770del/connecting-flutter-to-vehicle-signals-building-a-dart-sdk-for-eclipse-kuksa-121l) · earlier (March 2026, test counts have grown since): [1005 Tests, Zero AI: Building Offline-First Navigation with Flutter on Embedded Linux](https://dev.to/aki1770del/1005-tests-zero-ai-building-offline-first-navigation-with-flutter-on-embedded-linux-43bf).

Questions, bugs, and feature ideas belong in GitHub Issues. Use the built-in templates so reports arrive with enough detail to act on.

The CI badge tracks `main` only — that is a property of the badge, not of the pipeline:
CI runs on a push to **any** branch, and on pull requests to `main`.
Green on `main` at `6acd265`, 2026-08-28. Before that it had last run green on
2026-07-23: work was being committed to feature branches and packages published from
them, so nothing shipped in between passed through CI and the badge meant "main was
green", not "everything shipped was gated".

Both halves of that gap are now closed, and the second was worse than the first. CI
formerly ran only on `main`, so a branch could be pushed and packages published from it
without any pipeline ever claiming the ref — measured on 2026-08-28: eleven packages had
shipped that day from two such branches. Merging to `main` does not fix this in general,
because `backport/**` is a maintenance line that by design never merges — meaning the
branch we cut in-range patches from, for consumers who cannot take a major bump, was the
one branch with no gate at all. **CI now runs on every branch.** And its test job now
runs **every package's suite** (36 with tests), choosing `dart test` or `flutter test` by
package type; it previously covered 12 of 35 across two hardcoded allow-lists, leaving 23
suites that existed and never executed.

```
Status:    packages version independently on pub.dev — the registry is current state.
           Last repo-wide release tag v0.6.0, 2026-03-15 (it describes an 11-package
           ecosystem and is well behind the catalog).
Tests:     3,181 passing on main, re-measured 2026-08-08 (root 1,263 + 1,918 across all
           37 package suites; count drifts as the suite grows). `flutter test` at the repo
           root also runs the live-network probe tests — see Testing for the deterministic
           invocation.
Platform:  Linux desktop, x64 — the only target built and tested in CI (Flutter 3.41.4
           pinned; 3.38.3 on the embedded-target lane; SDK constraint ^3.10.0). The Snow
           Scene also builds and paints on genuine aarch64 — see Platform.
Embedded:  ARM IVI is the design target. THE APP NOW RENDERS on an emulated target
           (qemuarm64, Yocto scarthgap, ivi-homescreen v2.0) — first frame seen
           2026-08-28, under two working configurations: QEMU `-device virtio-gpu-gl-pci`
           (257 fps) or `GALLIUM_DRIVER=softpipe` (0.5 fps). Dart executes; the widget
           tree paints.
           The long-standing black frame is root-caused and it was NOT what the earlier
           notes said: Mesa 24.0.7 llvmpipe on aarch64 SEGVs on the first draw call that
           processes >=1 vertex. Context creation, eglMakeCurrent, glClear, shader compile
           and link all succeed; zero-vertex draws succeed. Not a Flutter defect, and not
           fixed by forcing software GL.
           STILL NOT DONE, and it matters more than the frame: the target ships NO map.
           There are no mbtiles in the image — they live in a separate repository the
           recipe does not fetch — so the app renders a blank map and falls back online.
           REAL HARDWARE IS UNMEASURED: the RPi4-64 image uses Mesa 25.1.6 + v3d, a
           different stack, and no board has been booted. See Platform before planning a
           deployment.
Safety:    ASIL-QM (display-only, no vehicle control) — see SAFETY.md
Ecosystem: 36 packages on pub.dev (+ 1 publish_to:none = 37 monorepo total), versioned
           independently. This tree can run EITHER WAY against the registry — on
           2026-08-28 nine package trees were found BEHIND their own published versions,
           each missing a `latlong2` widen, so committing from the tree would have
           regressed them. Reconciled. Check the package page for what `pub add` actually
           gives you, in both directions.
```

## Why "Snow Guard"?

SNG stands for **Snow Guard** — navigation that guards the driver when conditions fail unexpectedly.

> **[The SNGNav Way](SNGNAV_WAY.md)** — what we build, the five principles,
> and where it goes next.

A driver leaves Nagoya at 6 AM. Clear skies. By 7:15 she's on a mountain pass and the sky turns white. GPS dies in a tunnel. The network dropped two kilometers back. She didn't expect any of this.

SNGNav exists for that moment. Every feature is a guardian against a different unexpected failure:

| Guardian | Protects Against |
|----------|-----------------|
| Dead reckoning | GPS loss (tunnel, canyon, interference) |
| Offline tiles | Network failure (rural, congestion) |
| Self-hosted routing | Cloud unavailability (no signal) — you supply the server |
| Kalman filter | Sensor degradation (cold, old hardware) — also the default dead-reckoning engine |
| Config system | Target variation (different deployments) |

Five guardians, five failure modes. Where we have proven it, one failing does not take
the others down: see `test/integration/provider_chain_integration_test.dart` (routing
engine unavailable → location still works; tunnel → dead reckoning keeps navigation
alive). A full fault-injection matrix across all five is not written yet.

---

## Why This Architecture?

The navigation industry is converging on cloud-powered 3D visualization — AI
models rendering vivid driving scenes from server-side imagery. The results are
impressive in good conditions. In degraded conditions — tunnels, rural dead
zones, unexpected weather that kills connectivity — cloud-dependent navigation
disappears at the moment the driver needs it most.

SNGNav takes the opposite approach:

| Aspect | Cloud-first navigation | SNGNav |
|--------|----------------------|--------|
| Processing | Server-side AI rendering | On-device, embedded Linux |
| Connectivity | Required for full experience | Works fully offline |
| Data model | Proprietary, platform-locked | Open-source, BSD-3-Clause |
| Driver data | Platform-controlled collection | Consent-first, deny-by-default |
| Extensibility | Closed API, vendor decides features | Swappable provider interfaces — weather, location, routing and tiles selected at build time, not hard-wired (`lib/config/provider_config.dart`); 36-package open pub.dev catalog (incl. the `pretrip_*` pre-trip briefing family) |
| Weather awareness | Not a design concern | Origin story — built for unexpected snow |
| Safety boundary | Rich visuals during driving | Display-only, ASIL-QM, advisory alerts |

This is not a competition with commercial navigation services. It is architecture
for the conditions they do not serve: **offline, degraded, extreme.** The driver
in a snowstorm with no cell signal is our customer's customer. The edge developer
building for that driver is our customer.

---

## Why SNGNav, not flutter_map?

This is the right question to ask. The answer is: SNGNav uses flutter_map internally.
If you want a tile renderer, use flutter_map directly. If you want a safety
architecture that happens to render tiles, you are in the right place.

The distinction matters because the problems are different:

| Question | Right tool |
|----------|-----------|
| "How do I show a map in Flutter?" | `flutter_map` |
| "How do I keep showing a map when GPS fails?" | `kalman_dr` + `offline_tiles` |
| "How do I warn the driver before black ice?" | `driving_conditions` + `navigation_safety` |
| "How do I stay navigating when the network drops?" | `routing_engine` (OSRM or Valhalla, pointed at a server you host) |
| "How do I absorb crowd-sourced hazard reports?" | `fleet_hazard` |
| "How do I build all of this without starting from scratch?" | SNGNav |

flutter_map is a vendor-free Flutter map client: a tile layer that accepts any tile
source, plus marker, polyline, polygon, circle, overlay-image and scalebar layers. It
does that job well, and SNGNav builds directly on it — our hazard and fleet overlays
*are* flutter_map `CircleLayer`s and `MarkerLayer`s, and `offline_tiles` ships a
`TileProvider` for it. What SNGNav adds is the layer above and the pipeline behind:
what happens when the driver enters a tunnel, the cell signal dies, the road freezes,
and a blizzard hits simultaneously?

**What SNGNav adds above and behind the map**:

- **Dead reckoning** — when GPS drops (tunnel, canyon, jamming), Kalman-filtered
  inertial estimation keeps the location cursor moving. Accuracy degrades with time
  since the last fix and the estimate reports its own growing uncertainty; we have
  not published a measured drift bound.
- **Safety overlay** — a Z-ordered widget that sits above the map and navigation UI
  in the app's own tree (Z=5, always rendered). When conditions turn dangerous it
  fires unconditionally. Display-only, ASIL-QM boundary enforced in code. An
  integrator who composes their own stack above it can still cover it; the guarantee
  is ours, not the platform's.
- **Offline-capable pipeline** — MBTiles tiles + an OSRM/Valhalla routing target you
  host + simulated weather. Location, weather and routing default to simulated or mock,
  so `flutter run -d linux -t lib/snow_scene.dart` needs no GPS, no routing server and
  no API keys. **Tiles are the exception**: `TILE_SOURCE` defaults to `online`, the
  MBTiles archive is not in the repo ([data/README.md](data/README.md) shows how to
  generate one), and even with it the tile path falls back to the network above zoom 12
  while the map opens at zoom 15. Offline-*capable*, not zero-network.
- **Weather hazard detection** — not a weather widget. A hazard pipeline:
  raw forecast → road surface classification → grip score → safety alert → overlay.
- **Consent-first fleet data** — deny-by-default, per-purpose, revocable. The
  `driving_consent` package defines the contract and ships an in-memory
  implementation; persistence is yours to choose (this app uses SQLite — see
  `lib/services/sqlite_consent_service.dart` for a worked example). Fleet hazard zones
  surface only after explicit driver consent.
- **Scenario coverage matrix** — the architecture is specified as a set of driving
  scenarios, declared per package in `sngnav_coverage.yaml`. Uncovered cells are
  contribution targets. Read the bounds in Scenario Coverage first: the declarations
  are currently stale against the code.

If you are building a general-purpose map app, use flutter_map. If you are building
navigation for a driver in conditions that can kill, SNGNav is the architecture.

---

## Quick Start

```bash
# Prerequisites — the Flutter SDK itself, plus the Linux desktop toolchain
# (install Flutter first: https://docs.flutter.dev/get-started/install/linux)
sudo apt install clang cmake ninja-build libgtk-3-dev libsqlite3-dev pkg-config

# Build and run
flutter pub get
flutter run -d linux -t lib/snow_scene.dart
```

For the automated path, run `./scripts/setup.sh`. It installs the same Linux
packages and requires interactive `sudo` access for Step 1.

First run opens the **Before you drive** briefing — a pre-trip advisory with a planned
departure time, a wait-or-go recommendation, a departure checklist and surface-specific
guidance. There is no map on this screen. Tap **Start drive** in the app bar to begin the
simulated drive from Sakae Station to Higashiokazaki Station with simulated weather,
simulated GPS and mock routing — no GPS hardware and no weather or routing backend. Map
tiles are the exception: they stream from the public OpenStreetMap servers by default.

The simulated weather cycles through six phases every 5 seconds, so the heavy-snow
pass-summit alert first appears about 15 seconds after you tap **Start drive**, and
recurs about every 30 seconds thereafter.

To use real providers: `--dart-define=WEATHER_PROVIDER=open_meteo --dart-define=ROUTING_ENGINE=valhalla`
(read the network note under Configuration first — both reach third-party servers).

**Clone-to-build**: about 30 seconds once the Flutter SDK and pub cache are warm
(measured 2026-08-08). A first-time setup on fresh Ubuntu 24.04 is dominated by
installing the Flutter SDK itself, which this guide does not cover.

For Raspberry Pi and other arm64 Linux targets, see [docs/arm_deployment.md](docs/arm_deployment.md).
That guide is a bring-up path, not a verified target: the app has never run on a physical
board. See Platform for what is and is not proven.

## Running The Demo

Use this launch profile for the full snow-scene demo. It expects an MBTiles archive at
`data/offline_tiles.mbtiles`, which is **not** in the repo (`data/*.mbtiles` is
gitignored) — generate it first, per [`data/README.md`](data/README.md). Without it the
demo still runs, but it is **not** the offline path: the console logs `MBTiles coverage
is incomplete` (it does not say the file is missing) and the map renders online OSM tiles.

```bash
flutter run -d linux -t lib/snow_scene.dart \
  --dart-define=WEATHER_PROVIDER=simulated \
  --dart-define=LOCATION_PROVIDER=simulated \
  --dart-define=ROUTING_ENGINE=mock \
  --dart-define=TILE_SOURCE=mbtiles \
  --dart-define=MBTILES_PATH=data/offline_tiles.mbtiles \
  --dart-define=DEAD_RECKONING=true \
  --dart-define=DR_MODE=kalman
```

This profile uses the scripted weather progression, the simulated vehicle trace,
the mock route, and MBTiles-first rendering with online fallback when coverage
is incomplete.

### Demo Flow

1. Launch the app and tap **Start drive** on the *Before you drive* briefing — the
   drive does not begin until you do. Wait for the route to auto-fit.
2. Confirm the app bar status chip reads `NAVIGATING` once the drive starts.
3. Watch the top bars progress from `Clear — City Departure` into the snow
   phases as the simulated drive approaches the mountain pass.
4. Let the maneuver timer advance automatically every 8 seconds, or pause it
   when you want to hold on a specific state.
5. Observe the snow-zone rectangle appear over the mountain-pass leg of the route
   — a padded bounding box around that segment, not a route-shaped corridor. Its
   shape does not change during the drive; only its colour and label do.
6. When heavy snow or ice risk appears, confirm the safety overlay fires above
   the map instead of being hidden behind navigation UI.

### UI Controls And Signals

| Surface | What to watch |
|---------|---------------|
| App bar `Fit route` button | Re-applies overview framing for the active route |
| App bar pause/play button | Pauses or resumes the 8-second maneuver auto-advance loop |
| App bar navigation chip | Reads `NAVIGATING`, then `ARRIVED`, during the scripted demo (`IDLE` and `DEVIATED` also exist, but the scripted drive does not reach them) |
| Weather status bar | Shows precipitation, temperature, visibility, staleness, and `HAZARD` or `ICE` badges |
| Scenario phase indicator | Names the scripted phase, such as `Heavy Snow — Pass Summit` |
| Route progress card | Shows current maneuver instruction, leg distance, ETA, total distance, and progress bar |
| Speed display | Shows km/h with a GPS-quality dot underneath |
| Consent gate | `Fleet: OFF` by default; tap to switch to `Fleet: ON` and reveal fleet-fed hazards |

### Expected Demo Outcomes

- The route line stays visible with maneuver markers across the full trip.
- The snow-zone rectangle covers the mountain-pass leg of the route (a padded
  bounding box over that segment) and appears when snow is active. The route line
  extends past the box at both ends — expected, not a rendering fault.
- If the MBTiles file does not fully cover the route corridor, or is missing
  entirely, the app logs a startup warning and continues with hybrid online
  fallback instead of failing.
- Hazardous weather raises the safety overlay above the map and route progress
  UI. The alert stays up until dismissed, so it can remain on screen after
  conditions clear — you may see a "visibility 150 m" alert beside a bar reading
  10+ km.
- Granting fleet consent enables fleet markers and fleet-derived hazard zones;
  leaving consent denied keeps those surfaces hidden.

### Screenshot Capture

Screenshot targets and filenames are tracked in
[`docs/screenshots/README.md`](docs/screenshots/README.md).

### Demo Evidence

Captured from live runs of the profile above. Both were taken at v0.3 and predate the
current Japanese maneuver strings, so treat them as indicative rather than current:

- [`safety-alert.png`](docs/screenshots/safety-alert.png) — the `Heavy Snow — Pass Summit`
  phase: `HAZARD` badge, the modal alert above the map, the route line switched to hazard
  styling, and the snow-zone rectangle over the pass leg (note the route exits the box at
  both ends — that is the padded bounding box, working as built).
- [`snow-zone-active.png`](docs/screenshots/snow-zone-active.png) — the earlier
  `Moderate Snow — Pass Approach` phase with the alert modal up. Despite the filename,
  no snow zone is drawn in this one; the zone is visible in `safety-alert.png`.

`route-overview.png` is not published here: the committed file is a capture of an editor
window rather than the demo, and is pending a recapture.

## What You See

A navigation display with three layers:

| Layer | Z | Content |
|-------|:-:|---------|
| Map | 0 | OSM tiles (online or offline MBTiles), route polyline, fleet markers, weather zones |
| Navigation | 1 | Weather bar, speed, maneuver instructions, route progress, consent gate |
| Safety | 2 | Always-on overlay — modal alerts for ice risk, heavy snow, GPS loss |

The safety overlay is designed to five rules: always rendered, always on top,
passthrough when inactive, modal when active, independent state. What you can see
directly in the demo is that it renders above the map and navigation layers and stays
up until dismissed; the passthrough and always-mounted rules are design intent that the
demo does not exercise.

---

## Configuration

Provider selection is controlled via `--dart-define` flags — no code changes needed.

**Scope**: this table is the `lib/snow_scene.dart` reference app's flag set; all eight
apply there. `lib/main.dart` is wired differently — of this table it reads only
`WEATHER_PROVIDER`, does no routing, and auto-detects `data/offline_tiles.mbtiles` at a
fixed path rather than reading `TILE_SOURCE`/`MBTILES_PATH`. Its own flags are the
`PRETRIP_*` set documented below.

| Flag | Default | Options |
|------|---------|---------|
| `WEATHER_PROVIDER` | `simulated` | `simulated`, `open_meteo`, `digitraffic` ¹ |
| `LOCATION_PROVIDER` | `simulated` | `simulated`, `geoclue` |
| `DEAD_RECKONING` | `true` | `true`, `false` |
| `DR_MODE` | `kalman` | `kalman`, `linear` |
| `ROUTING_ENGINE` | `mock` | `mock` (no server), `osrm`, `valhalla` |
| `VALHALLA_BASE_URL` | *(empty → the public `https://valhalla1.openstreetmap.de`)* | any base URL |
| `TILE_SOURCE` | `online` | `online`, `mbtiles` |
| `MBTILES_PATH` | `data/offline_tiles.mbtiles` | any path |

¹ `digitraffic` is a **live network** source (Fintraffic road-hazard advisories, Oulu by
default, 5-minute poll) — it is dark whenever the network is. Data © Fintraffic /
digitraffic.fi, CC BY 4.0; carry that credit in any UI that shows it.

**Where the network goes.** `mock` routing and `simulated` weather reach nothing.
`TILE_SOURCE=online` — the default — fetches from `https://tile.openstreetmap.org`.
`ROUTING_ENGINE=valhalla` uses the public OSM-DE instance unless you set
`VALHALLA_BASE_URL`; `ROUTING_ENGINE=osrm` targets `https://router.project-osrm.org` and
has no override flag today (construct `OsrmRoutingEngine` directly for a private server).

**Unrecognised values do not fall back to the Default column.** `WEATHER_PROVIDER` falls
through to `open_meteo` and `ROUTING_ENGINE` to `valhalla`, both of which reach the
network. Check your spelling before you trust an offline run.

### Example Runs

```bash
# Demo weather scenario (6-phase snow progression)
flutter run -d linux -t lib/snow_scene.dart \
  --dart-define=WEATHER_PROVIDER=simulated

# Real GPS via GeoClue2 D-Bus
flutter run -d linux -t lib/snow_scene.dart \
  --dart-define=LOCATION_PROVIDER=geoclue

# Valhalla routing with linear dead reckoning.
# NOTE: without VALHALLA_BASE_URL this sends route queries to the PUBLIC
# https://valhalla1.openstreetmap.de instance. For your own server, add:
#   --dart-define=VALHALLA_BASE_URL=http://localhost:8002
flutter run -d linux -t lib/snow_scene.dart \
  --dart-define=ROUTING_ENGINE=valhalla \
  --dart-define=DR_MODE=linear

# Fully offline (MBTiles + simulated everything)
flutter run -d linux -t lib/snow_scene.dart \
  --dart-define=TILE_SOURCE=mbtiles \
  --dart-define=WEATHER_PROVIDER=simulated

# Offline-first reference entrypoint (map + pre-trip briefing + forward scene;
# LocationBloc only, no routing). As cloned there is no data/*.mbtiles (gitignored),
# so this runs on online OSM tiles and renders.
# KNOWN DEFECT 2026-08-08 — supply an MBTiles archive and the 2D map view dies: any tile
# outside the archive (the pan-buffer edge, or any tile below the archive's minzoom)
# throws "urlTemplate must be provided", replacing the map with an error box while the
# status bar still reads "Offline — MBTiles loaded". Tracked at lib/main.dart:539-541.
# Do not use this entrypoint to evaluate the offline map until it is fixed.
flutter run -d linux -t lib/main.dart
```

### Pre-trip family-thread destination-area card

The Pre-trip view (hosted by both `lib/main.dart` and the `lib/snow_scene.dart`
reference app via a shared `PretripScreen`) includes an in-app destination
**place entry** (the driver sets/changes the area herself) and a **family-thread**
*"Conditions in the destination area"* card. By design the demo is **offline-first**:
the place-entry tile is always visible, but the area card itself reads a **live**
forecast, so it appears only when the live source is opted in:

The three `PRETRIP_DEST_*` values below are an optional **seed** only. The driver can set
the area herself in-app, and a deliberate in-app clear is durable — it survives a restart,
and this seed does not resurrect it.

```bash
flutter run -d linux -t lib/main.dart \
  --dart-define=PRETRIP_FORECAST=met_norway \
  --dart-define=PRETRIP_DEST_LAT=39.69 \
  --dart-define=PRETRIP_DEST_LON=140.34 \
  --dart-define=PRETRIP_DEST_LABEL=Akita
```

Without `PRETRIP_FORECAST=met_norway` the place-entry tile still works and shows
an honest *"Area conditions need the live forecast enabled for this build."* note;
the area card stays hidden. This is intentional — the live source is **opt-in**,
never a default network dependency in the offline demo build.

### Pre-trip route bridge-icing caution

With a destination set, the pre-trip briefing can additionally count the mapped
bridge sites on the driver's actual route — bridge decks freeze before the road
surface does, so *「この先、秋田県内の経路上に橋が約Nか所あります。橋は路面より先に凍結します。」*
at the kitchen table lets her slow down before the deck, not after the slide.
The route polyline comes from an OSRM server **you supply** — this pre-trip feature ships
**no default server**, so without `PRETRIP_ROUTE_OSRM_URL` it fetches nothing at all
(unlike `ROUTING_ENGINE` and the default online tiles above, which do have public
defaults) — and the bridge sites come from a bundled Akita-prefecture dataset
(© OpenStreetMap contributors, ODbL; see `assets/bridges_akita.ATTRIBUTION.md` —
the caution card carries the attribution):

```bash
flutter run -d linux -t lib/main.dart \
  --dart-define=PRETRIP_FORECAST=met_norway \
  --dart-define=PRETRIP_ROUTE_OSRM_URL=https://your-osrm.example/
```

The resolve is one-shot **per destination**: it fires at pre-trip initialization
and again exactly once when the destination is set or changed in-app; clearing
the destination clears the count and fetches nothing. There is no polling and
no re-fetch on rebuild. Degradation is honest by design: without the define,
without a destination, on any network or asset failure, or for a route that
leaves the bundled data's coverage (today: Akita prefecture), the section is
simply **absent** — no error banner, no substitute claim. The count is
approximate by construction, and a zero count means "nothing to say", never an
all-clear.

---

## Platform

**Runs today: Linux desktop, x64** — the only platform built and tested in CI (Flutter
3.41.4 stable; SDK constraint ^3.10.0). Everything under Quick Start and Example Runs is
this platform.

**Genuine aarch64 Linux — the Snow Scene builds and paints.** A weekly `ARM64 Scene
Render` workflow builds and renders the scene on a real arm64 runner and attaches the
captured PNG to the run. Honest bounds, both of which matter: it is a server CPU with
software GL (llvmpipe / Skia-CPU), not a board with a real GPU; and the job *captures*
the frame without asserting anything about its contents, so open the artifact and look
rather than trusting the green check.

**arm64 boards (Raspberry Pi and similar) — a bring-up guide, not a verified target.**
[docs/arm_deployment.md](docs/arm_deployment.md) documents the path via the standard
Flutter Linux embedder. It has never run on a physical board.

**ARM IVI / embedded compositors — the design target. The app now renders here.** It is
build-verified for Yocto scarthgap and runs under
[ivi-homescreen](https://github.com/toyota-connected/ivi-homescreen) v2.0 on a booted
qemuarm64 target: the AOT library loads, the Dart VM and widget tree come up, and as of
**2026-08-28 a frame is on the screen** — captured under two working configurations,
QEMU `-device virtio-gpu-gl-pci` (257 fps) or `GALLIUM_DRIVER=softpipe` (0.5 fps).

**Correction, recorded rather than quietly replaced.** Until 2026-08-28 this section said
the black frame traced to
[flutter/flutter#183495](https://github.com/flutter/flutter/issues/183495). **That was
wrong, and it was our defect attributed to someone else's tracker.** The real cause:
**Mesa 24.0.7 llvmpipe on aarch64 segfaults on the first draw call that processes at
least one vertex.** It reproduces in a 40-line script with no Flutter, no Wayland and no
compositor. EGL context creation, `eglMakeCurrent`, `glClear`, shader compile and program
link all succeed; a zero-vertex draw succeeds. Mesa's own documentation lists llvmpipe
targets as x86, x86-64 and ppc64le — aarch64 is not among them, and poky's `mesa.inc`
already carries the precedent of disabling swrast on an arch where it crashed. Two
further things the earlier notes blamed were also not the cause: `weston.service` failing
at boot is a property of the QEMU device flag, not of the image, and the
`BUILD_BACKEND_SOFTWARE` drop-in is inert — `/proc/<weston>/maps` shows the hardware
driver mapped despite `LIBGL_ALWAYS_SOFTWARE=1`.

**What is still not done, and it matters more than the frame.** The image ships **no map
tiles** — they live in a separate repository the recipe does not fetch — so the app
renders a blank map and falls back to online tiles. Real hardware remains **unmeasured**:
the RPi4-64 image uses Mesa 25.1.6 with the v3d driver, a different stack, and no
physical board has been booted. Do not plan an IVI deployment from this repo today.

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│ Widgets (Z-layered)                             │
│  SafetyOverlay > NavigationOverlay > MapLayer   │
└──────────────────┬──────────────────────────────┘
                   │ BlocBuilder / BlocListener
┌──────────────────┴──────────────────────────────┐
│ BLoCs (7)                                       │
│  Location · Weather · Routing · Navigation      │
│  Map · Consent · Fleet                          │
└──────────────────┬──────────────────────────────┘
                   │ constructor injection
┌──────────────────┴──────────────────────────────┐
│ Providers (abstract interfaces)                 │
│  LocationProvider · WeatherProvider             │
│  RoutingEngine · ConsentService                 │
└──────────────────┬──────────────────────────────┘
                   │ ProviderConfig.fromEnvironment()
┌──────────────────┴──────────────────────────────┐
│ --dart-define flags (8)                         │
└─────────────────────────────────────────────────┘
```

**Where this runs today (measured 2026-08-08).** `flutter build linux --release`
succeeds and the suites run on Linux desktop x64. The architecture below is
target-neutral; the delivery is not — see Platform.

**Key design decisions**:
- BLoCs never reference each other directly — all coupling is widget-mediated
- Provider interfaces allow swapping implementations without touching BLoC logic
- Dead reckoning wraps any LocationProvider (decorator pattern)
- Consent is deny-by-default, per-purpose, revocable, SQLite-backed

### Directory Layout

```
lib/
├── bloc/        bloc.dart barrel — all 7 BLoCs from one import: location, weather,
│                 consent, fleet (defined here) + routing, navigation, map
│                 (re-exported from packages/)
├── config/      ProviderConfig — reads --dart-define flags, creates providers
├── models/      barrel re-exporting driving_consent + fleet_hazard model types
│                 (GeoPosition/KalmanFilter → packages/kalman_dr,
│                  WeatherCondition → packages/driving_weather,
│                  RouteResult → packages/routing_engine)
├── providers/   Abstract interfaces + simulated/real implementations
├── services/    SqliteConsentService + consent DB, saved places, bridge-corridor
│                 read, snow-aware pre-trip advisor (barrel also re-exports
│                 HazardAggregator from packages/fleet_hazard)
├── adapters/    navigation_route_adapter
├── navigation/  route_follower (snap-to-route)
├── widgets/     Z-layered UI (MapLayer, SafetyOverlay, WeatherStatusBar, etc.)
├── fluorite/    FluoriteView scaffold (3D renderer integration point)
├── demo_*.dart  four standalone demos (map, navigation, routing, weather) —
│                 not shipping entrypoints
├── main.dart    Getting-Started entrypoint — MBTiles map + pre-trip briefing +
│                 forward scene, en/ja
└── snow_scene.dart  Full application entrypoint
```

---

## Testing

```bash
flutter test
```

The root app suite validates the integrated desktop experience. Extracted
packages also carry their own package-local test suites under `packages/` and
should be run from the package directory when you change those domains.

Typical workflow:

```bash
# App-level widgets, blocs, integration
flutter test

# Example package-level validation (subshells, so each starts from the repo root)
(cd packages/offline_tiles && flutter test)
(cd packages/routing_engine && dart test)
```

Coverage areas in the workspace, re-measured 2026-08-08 on main (106 root test files
in total; the table lists the largest directories, and `test/` also holds `benchmark`,
`dignity`, `fluorite`, `navigation`, `quant`, and `tool`):

| Category | Files | Tests | Coverage |
|----------|:-----:|:-----:|----------|
| BLoC | 10 | — | All 7 BLoCs, state transitions, event handling |
| Widget | 38 | — | Golden tests, safety overlay rules, weather bar staleness, ja render, dignity |
| Provider | 20 | — | Simulated + real provider contracts, dead reckoning accuracy |
| Model | 3 | — | Edge cases, Kalman filter convergence |
| Integration | 13 | — | Weather-to-safety bridge, fleet-to-safety bridge, negative safety |
| Service | 6 | — | SQLite consent, in-memory consent, hazard aggregation |
| Config | 2 | 86 | All 8 flags, documented combos, mutual exclusion invariants |
| Entrypoint | 1 | 5 | main.dart widget pump, snow_scene.dart import graph |
| Probe | 2 | 6 | GeoClue2, OSRM — live services, see below |
| Package suites | — | 1,918 | All 37 packages; 0 failing |

**`flutter test` at the repo root runs the probe tests, and they call live third-party
services.** They can fail on network conditions or a remote server's behaviour alone —
today the OSRM public demo returns Japanese maneuver text where the probe expects
English, so a plain `flutter test` reports one failure that says nothing about this
code. For a deterministic run:

```bash
flutter test --exclude-tags=probe   # 1,258 passing, 0 failing (measured 2026-08-08)
```

CI uses exactly that exclusion. When README statistics drift, treat the live test run
as authoritative.

---

## Scenario Coverage

The scenario registry tracks which real-world driving situations the architecture
covers. There is no single registry file: the seven `sngnav_coverage.yaml` files, one
per package root, *are* the registry. They enumerate 66 unique scenario IDs
(`S-001`–`S-066`) while each still declares a total of 62 — the two numbers disagree
and the files need reconciling.

| Package | Covered | Partial | Total contrib | Status |
|---------|:-------:|:-------:|:-------------:|--------|
| `navigation_safety` | 5 | 1 | 0.05 | [![nav](https://img.shields.io/badge/coverage-8%25-yellow)](packages/navigation_safety/sngnav_coverage.yaml) |
| `driving_conditions` | 7 | 1 | 0.11 | [![dc](https://img.shields.io/badge/coverage-13%25-yellow)](packages/driving_conditions/sngnav_coverage.yaml) |
| `driving_weather` | 5 | 2 | 0.08 | [![dw](https://img.shields.io/badge/coverage-11%25-yellow)](packages/driving_weather/sngnav_coverage.yaml) |
| `fleet_hazard` | 4 | 1 | 0.065 | [![fh](https://img.shields.io/badge/coverage-8%25-yellow)](packages/fleet_hazard/sngnav_coverage.yaml) |
| `snow_rendering` | 3 | 1 | 0.048 | [![sr](https://img.shields.io/badge/coverage-6%25-yellow)](packages/snow_rendering/sngnav_coverage.yaml) |
| `route_condition_forecast` | 6 | 0 | 0.097 | [![rcf](https://img.shields.io/badge/coverage-10%25-yellow)](packages/route_condition_forecast/sngnav_coverage.yaml) |
| `adaptive_reroute` | 6 | 0 | 0.097 | [![ar](https://img.shields.io/badge/coverage-10%25-yellow)](packages/adaptive_reroute/sngnav_coverage.yaml) |
| **Total** | **36** | **6** | **~55%** | 24 scenarios open |

**What "covered" means**: the package declares a `covered_by` capability and asserts a
test exercises it. Partial = the signal is ingested but the threshold or subtype logic
is incomplete. Open = no coverage anywhere in the architecture today.

**Bound, measured 2026-08-08 — the `covered_by` fields are stale.** All seven files are
stamped `Updated: 2026-04-05` and each declares a package version behind the registry.
A dozen-plus code symbols named as evidence resolve to zero Dart files anywhere in the
repo — most are pre-rename names whose capability survives under a new one
(`RoadSurface*` → `RoadSurfaceState`, `MonteCarloSafetyScorer` → `SafetyScoreSimulator`,
`GeoClusterer` → `HazardAggregator`). The tests themselves are present and green. Until
the files are re-synced, treat `covered_by` as a pointer to intent, not to code, and
verify against the package's live API.

Two entries deserve naming, because they are not renames:

- **S-011 "Offline fallback"** still advertises `OfflineWeatherProvider (static fallback
  values)`. That behaviour was deliberately **removed**: offline now yields an
  explicitly-absent reading (`WeatherStale` with a real age, or `WeatherUnavailable`),
  never a reassuring default. The scenario is covered; the description is not.
- **S-036 "Stale report expiry"** says expiry is *enforced*. It is available, not
  enforced: `FleetReport.isRecent({maxAge: 15min})` exists and is unit-tested, but
  `HazardAggregator.aggregate` never calls it, so a stale report still clusters into a
  hazard zone unless you filter first.

The open cells are the founding document of the contributor swarm. If you own a
domain (fleet operator, OEM winter testing, V2X, ADAS), one of those open cells
is yours. See [`packages/navigation_safety/CONTRIBUTING.md`](packages/navigation_safety/CONTRIBUTING.md)
for the contribution guide and the `sngnav.[category].[subcategory].[specific].v[N]`
`SafetyScenario` namespace that makes parallel contributions composable.

Machine-readable: each `sngnav_coverage.yaml` is schema version 1.0 — parseable
for dashboards, CI checks, and gap-analysis tooling.

---

## Offline Tiles

The app falls back to online OSM tiles if no MBTiles file is found.
To generate your own offline tiles:

```bash
sudo apt install tilemaker
wget https://download.geofabrik.de/asia/japan/chubu-latest.osm.pbf
# The config and process files ship with tilemaker, not with this repo —
# point these at your tilemaker checkout.
tilemaker --input chubu-latest.osm.pbf \
          --output data/offline_tiles.mbtiles \
          --config /path/to/tilemaker/resources/config-openmaptiles.json \
          --process /path/to/tilemaker/resources/process-openmaptiles.lua
```

The bundled demo archive (`data/offline_tiles.mbtiles`, not committed — see
[data/README.md](data/README.md)) is 1.7 MB: 43 tiles, zoom 10–12, covering a small box
around Nagoya (136.70–137.05 E, 35.00–35.32 N). It is enough to review the offline path,
not a Chubu-region dataset. Note that the map opens at zoom 15 and the tile layer falls
back to the network above zoom 12, so generate your own for real coverage.

## Safety

This is a **display-only navigation aid** classified ASIL-QM under ISO 26262.

- **No vehicle control**: no steering, braking, throttle, or ADAS commands.
- **Advisory alerts only**: weather warnings and hazard zones inform the
  driver — they do not override driver judgment.
- **No AI-generated imagery**: all visual output is deterministic (tile
  rendering, route geometry, declared weather data). No generative model
  produces or modifies what the driver sees.
- **Consent by default**: fleet data sharing is deny-by-default,
  per-purpose, and revocable.
- **Graceful degradation**: each data source has a tested absence path — missing
  MBTiles falls back to online tiles, an unreachable weather API yields an
  explicitly-absent reading rather than a reassuring default, and GPS loss falls
  through to dead reckoning. Absence is represented as absence, never as a
  safe-looking value. Not every combination of simultaneous source loss is covered
  by a test.

The architecture aligns with emerging transport safety regulations
(EU AI Act, UNECE WP.29) through design, not retrofit. See
[SAFETY.md](SAFETY.md) for the full safety model, regulatory awareness
context, and compliance-by-design mapping.

## API Documentation

Generate dartdoc for the full API reference:

```bash
dart doc
```

Output: `doc/api/index.html`. Key entry points:

- **`ProviderConfig`** — configuration system (8 `--dart-define` flags)
- **`KalmanFilter`** — 4D EKF for tunnel dead reckoning
- **`DeadReckoningProvider`** — decorator wrapping any `LocationProvider`
- **`OsrmRoutingEngine`** / **`ValhallaRoutingEngine`** — routing engines
- **`LocationBloc`**, **`WeatherBloc`**, **`RoutingBloc`** — BLoC state machines

`dart doc` at the repo root documents the app only. `KalmanFilter`,
`DeadReckoningProvider`, `OsrmRoutingEngine` and `ValhallaRoutingEngine` live in
`packages/kalman_dr` and `packages/routing_engine` — run `dart doc` inside those
package directories, or read them on pub.dev.

## Dependencies

The app depends on 21 packages from the SNGNav catalog (20 from `packages/` plus
`kuksa_dart_sdk`), out of 37 in the monorepo, together with a small set of Flutter and
runtime libraries under permissive licenses. See `pubspec.yaml` for the complete list.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add new providers and submit changes.

For AI coding agents, see [.github/copilot-instructions.md](.github/copilot-instructions.md).

## License

Code: Same license as the parent project.
Map data: OpenStreetMap contributors (ODbL-1.0).

---

*Re-measured 2026-08-08 on Machine E: Ubuntu 24.04.4 LTS, kernel 6.18.5-1-t2-noble,
Flutter 3.45.0 locally — CI pins Flutter 3.41.4, which is the version to match.*
*Build: `flutter build linux --release` succeeds. For current validation run
`flutter test --exclude-tags=probe` from the repo root plus affected package suites
under `packages/`; a plain `flutter test` also calls live third-party services.*
