# Offline-first navigation building blocks for Flutter: dead reckoning, local map tiles, and open road-condition data

> **Honest scope.** This is a how-to about four small, separately usable pub.dev packages and the live open data behind one of them. It is *not* a screen-recording demo: the assembled reference app targets embedded Linux head units (Flutter via [flutter-elinux](https://github.com/sony/flutter-elinux)) and isn't shown running here — that write-up follows when it builds and records on real hardware. Everything I *do* claim below is backed by tests or a live fetch, and I say which is which.

## The problem nobody designs for

Most navigation code quietly assumes three things that fail exactly when a driver needs the map most:

1. **GPS is always there.** It isn't — tunnels, urban canyons, parking structures, dense forest drop the fix for seconds to minutes.
2. **The network is always there.** It isn't — rural roads, mountain passes, and the snowstorm where you most need a map are where cellular dies.
3. **The driver can see.** In a whiteout, they can't.

If you build for embedded automotive Linux (an IVI head unit, a fleet device, a Yocto image on an ARM SBC) you eventually hit a requirement desktop and phone apps get to ignore: *keep navigating when GPS, the network, and visibility all degrade at once.* That compound-failure case is the design target.

What follows is four small packages for that case — `pub add` what you need, ignore the rest — and the verification behind each, so you can trust the building blocks even though the assembled demo isn't on screen yet.

## 1 — Keep moving after the GPS drops: `kalman_dr`

The hard part isn't drawing a map. It's *honestly* continuing to position the vehicle when the fix disappears — and being honest about when you can no longer trust the estimate.

[`kalman_dr`](https://pub.dev/packages/kalman_dr) (v0.4.0) wraps your location stream and, when the GPS fix times out, keeps estimating position from the last known heading and speed with a Kalman filter (a simpler linear mode is also available). Two things make it usable in a safety context rather than a toy:

- It reports **honestly degrading accuracy** while dead-reckoning — uncertainty grows the longer GPS is gone, and your UI can show it.
- It has a **safety cap**: past a configured un-corrected distance it stops claiming a position and surfaces "position unavailable" rather than lying to the driver.

**Verification:** `flutter test` → **68 unit tests pass** (run 2026-05-30), covering tunnel-entry, degradation, recovery, multi-cycle, and the safety-cap cases. It's pure Dart logic over a location stream, so it carries no platform baggage.

```dart
// wrap any Stream<Position> (geolocator, a mock, your own GNSS bridge)
final dr = DeadReckoningProvider(mode: DrMode.kalman);
dr.wrap(rawPositionStream).listen((estimate) {
  // estimate.position keeps advancing through a GPS gap;
  // estimate.accuracy widens honestly; past the cap it reports unavailable.
});
```

## 2 — Render the map with no network: `offline_tiles`

[`offline_tiles`](https://pub.dev/packages/offline_tiles) (v0.5.1) is a `TileProvider` for [`flutter_map`](https://pub.dev/packages/flutter_map) that serves tiles from a local `.mbtiles` file with **zero network**. Its resolver tries, in order: in-memory cache → MBTiles → a lower zoom level (so you always show *something*) → online (if available) → a placeholder. You ship the region you care about alongside the app and the map renders in airplane mode.

```dart
TileLayer(
  tileProvider: MbTilesTileProvider(path: 'data/region.mbtiles'),
  // ... falls back gracefully when a tile is missing; never blanks the map.
)
```

**Verification caveat (honest):** `offline_tiles` is published and in use, but I could not exercise its test suite on the machine I'm writing from — it pulls in Flutter's widget/rendering layer, and the local ARM-patched Flutter SDK here has a `TargetPlatform` enum/switch mismatch (`linux_arm64`) that fails to compile *any* widget-touching code. That's an SDK-fork issue, not an `offline_tiles` one; its tests should be re-run on a stock Flutter SDK. I'm flagging it rather than claiming a green I didn't see.

## 3 — Warn about the road ahead from live open data: `condition_aggregator_digitraffic`

Offline keeps you *oriented*. It doesn't tell you the road 5 km ahead is sheet ice. For that you need live road-condition data — and many countries publish it as open data.

[`condition_aggregator_digitraffic`](https://pub.dev/packages/condition_aggregator_digitraffic) (v0.0.4) reads [Fintraffic's Digitraffic](https://www.digitraffic.fi/) traffic-message API (Finland's open road data, **CC-BY 4.0**) and turns the raw CAP-style messages into a small, typed `Advisory` stream — severity, area, effective/expires, headline.

**Verification (live, not mocked):** one snapshot fetch of the all-Finland feed on 2026-05-30 returned HTTP 200 with a **~16.4 MB** body — **1489 active announcements**, of which **730 severe** — and the package parsed all 1489, mapping a worst-of winter case to `precip=snow, intensity=heavy, visibility=150 m, ice=true, hazardous=true`, with Fintraffic's CC-BY-4.0 attribution carried through every advisory. Treat those figures as a point-in-time reading, not a constant: the live feed's size and severity mix move through the day with the actual road situation (it was ~3.5 MB a few days earlier).

That volatility is exactly why **v0.0.4 exists**. The all-Finland feed isn't a fixed size (it tracks active-announcement count and attached geometries), and the v0.0.2/v0.0.3 adapter applied a *hard* 8 MB cap that **threw** on a perfectly valid large 200 — so on a busy winter day the advisory silently never arrived. v0.0.4 removes the hard throw: it always parses a valid 200 and replaces the cap with a soft 32 MB warn threshold plus an optional `onLargeResponse` diagnostic. **22 unit tests pass**, including the large-response regression cases — a >8 MB body parses without throwing, a >32 MB body additionally fires the soft-warn diagnostic and still parses, and an in-threshold body fires nothing. If you fetch live national road data, this class of size-cap bug is worth checking for in your own adapters.

```dart
final provider = DigitrafficAdvisoryProvider(
  onLargeResponse: (bytes) => log.info('Digitraffic body $bytes B'), // optional
);
final advisories = await provider.fetchActiveAdvisoriesAtPoint(lat, lon);
// typed, severity-ranked, CC-BY-4.0 attributed — feed them to your safety UI.
```

Wiring those advisories into an on-screen safety overlay is the job of a weather/advisory provider in [`driving_weather`](https://pub.dev/packages/driving_weather) (v0.4.0, **45 tests pass**); a Digitraffic-backed provider that bridges section 3's advisories into that overlay is in progress (working tree today, not yet in the published `driving_weather`) — I'll note it here rather than imply it's already a `pub add` away.

## Why these are separate packages

| Package | One job | pub.dev | verified 2026-05-30 |
|---|---|---|---|
| `kalman_dr` | dead-reckon through GPS loss, honestly | 0.4.0 | 68 tests pass |
| `offline_tiles` | render `flutter_map` tiles from local MBTiles, no network | 0.5.1 | published; suite pending stock-SDK re-run |
| `driving_weather` | a weather/advisory `Stream` your UI can react to | 0.4.0 | 45 tests pass |
| `condition_aggregator_digitraffic` | turn Finnish open road data into typed advisories | 0.0.4 | 22 tests pass; live fetch → hazardous=true |

Each does one thing and is independently useful. Take the dead-reckoning provider into your own `flutter_map` app and ignore everything else — that's the point.

## On embedded Linux, and what isn't shown yet

These are written for embedded Linux head units via [flutter-elinux](https://github.com/sony/flutter-elinux); the offline-first design (local tiles, dead reckoning, open-data advisories) exists precisely for the constrained, intermittently-connected automotive context. The assembled reference app and an on-target ARM build are **work in progress and deliberately not claimed here** — the local SDK I'm building on has an enum/switch mismatch that blocks a desktop GUI build, so rather than stage a misleading screenshot, the running demo waits for a build I can stand behind. When it's verified on hardware, that's its own write-up.

## Try it

- Repo: https://github.com/aki1770-del/SNGNav
- Packages on pub.dev: [`kalman_dr`](https://pub.dev/packages/kalman_dr), [`offline_tiles`](https://pub.dev/packages/offline_tiles), [`driving_weather`](https://pub.dev/packages/driving_weather), [`condition_aggregator_digitraffic`](https://pub.dev/packages/condition_aggregator_digitraffic).
- If you're solving the GPS-dropout, offline-map, or live-road-condition problem on embedded Flutter and hit a wall, open an issue — that's the kind of road this is built for.

---

*Built as open-source building blocks for driver-assisting navigation that has to keep working when the infrastructure doesn't. Finnish road data © Fintraffic, [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/).*
