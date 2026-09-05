# edge_dev_akita_briefing — full reference integration

> **New here? → [QUICKSTART.md](QUICKSTART.md)** walks you from an empty
> `flutter create` to a working offline winter-safety briefing in **~15 minutes**,
> using the two hosted pub.dev packages. This README is the reference description
> of the finished app.
>
> **Embedded / 32-bit ARM?** → [EMBEDDED_ARMV7.md](EMBEDDED_ARMV7.md) — ship the offline core onto `armv7` car-class hardware (pure-Dart core `armv7`-proven; Flutter render gated on flutter/flutter#188063).

A standalone, **edge-developer-shaped** Flutter app that assembles and RENDERS
the driver's mother's Akita pre-trip winter-safety briefing using **only two
published-shaped packages** and the developer's **own** minimal UI widget —
nothing from the SNGNav app.

It is the worked answer to "what does an edge developer actually write?":

```
JMA AMeDAS visibility sensor (秋田 / Akita, station 32402)
  → JmaVisibilityProvider            (pretrip_source_jma)
  → VisibilityObservation (metres)
  → mergeObservedVisibility into the DEPARTURE-HOUR forecast slot
  → SnowAwarePretripAdvisor.brief()  (pretrip_decision_advisor)
  → PretripBriefing
  → the edge developer's OWN widget (AkitaBriefingView) — no SNGNav app widgets
```

The whole of the edge developer's data logic is three published-package calls
(`lib/akita_data.dart`); the UI is one hand-rolled `StatelessWidget`
(`lib/akita_briefing_view.dart`).

## The two packages it uses (and nothing else from us)

| Package | Role |
|---|---|
| [`pretrip_decision_advisor`](https://pub.dev/packages/pretrip_decision_advisor) | the contract + reference advisor + `VisibilityObservation` / `mergeObservedVisibility` |
| [`pretrip_source_jma`](https://pub.dev/packages/pretrip_source_jma) | `JmaVisibilityProvider` — turns a real JMA AMeDAS reading into a `VisibilityObservation` |

> Swap the region by swapping the source package — they all emit the same typed
> inputs against the same contract:
> [`pretrip_source_digitraffic`](https://pub.dev/packages/pretrip_source_digitraffic)
> (Finland) and
> [`pretrip_source_met_norway`](https://pub.dev/packages/pretrip_source_met_norway)
> (global).

An external edge developer starts their own app with just:

```sh
flutter pub add pretrip_decision_advisor pretrip_source_jma
```

(This in-repo copy uses `path:` dependencies so the example tracks the local
package source inside the monorepo; the imports and the code are identical to
what the two hosted packages give you.)

## Run it

```sh
# The deterministic, offline whiteout demonstration, in a window:
flutter run

# Render the briefing to a PNG a human can eyeball (offline, deterministic):
flutter test test/akita_briefing_capture_test.dart
#   → writes _capture/akita_briefing.png  (gitignored; regenerate locally)
```

The app opens on the offline whiteout demonstration. "Try live JMA (Akita)"
wires the real `JmaVisibilityProvider`; if a fresh AMeDAS reading is in range it
re-briefs on the live value, otherwise it honestly says nothing fresh was found
— it never fabricates a number.

## What the typed result looks like

The pure-Dart core (`assembleAkitaBriefing`) returns this `PretripBriefing` —
the measured 80 m lights the whiteout/severe band a temperature-only forecast
alone could never reach:

```text
Verdict : waitAdvised
Strength: advisoryStrong
Delay   : 1:00:00.000000
Chips   :
  - Visibility may drop to ~80 m around 07:00 — whiteout conditions.
  - Conditions improve by about 08:15.
Measured: 80.0 m at Akita (0.4 km away)
```

## What the rendered card looks like

`AkitaBriefingView` paints, top to bottom:

1. a **verdict headline** in a panel **coloured by severity** (here a deep
   amber/red "Consider waiting about 1 h — conditions are hazardous now", driven
   by `PretripVerdict.waitAdvised` + `RecommendationStrength.advisoryStrong`);
2. the **plain-language hazard chips** as a bullet list (the two lines above);
3. the **departure-hour MEASURED-visibility line** — "Departure-hour visibility
   MEASURED: 80 m at Akita (0.4 km away)";
4. the **attribution** — "Data: Japan Meteorological Agency / AMeDAS (open
   data)." (on-card text is English only — the bundled font carries no CJK
   glyphs, so the agency is named in English).

## Honesty (binding)

This is a driver-safety surface. These rules are binding and are not relaxed by
this example:

- **visibility is NEVER estimated** (a source maps absent data to `null`, never
  a value);
- **a warning never produces a number** (measurement and warning live on
  separate packages);
- **an observation is valid for the departure hour only** (`mergeObservedVisibility`
  sets the covering slot and never projects forward);
- **null = the driver's own judgment**, never a fabricated hazard — and we never
  fabricate an "all clear".

The 80 m value is the **demonstration whiteout case**, labelled as such in the
source and on the rendered card. Verbatim from `lib/akita_data.dart`:

> HONEST: 80 m is the whiteout case (the in-trip turn-back band). Live Akita
> visibility in June reads clear; this labelled value demonstrates the path
> that lights the severe band when the AMeDAS sensor really does read low.

and on the card itself (the non-live banner, `lib/akita_briefing_view.dart`):

> Demonstration value — 80 m is the whiteout case. Live Akita visibility in
> June reads clear; this labelled value shows the path that lights the severe
> band.

The capture test and the offline demo NEVER call the network; the live fetch is
behind the explicit "Try live JMA" button and returns `null` (not a fabricated
value) when no fresh QC-normal reading is in range.

## The `pretrip` package family

- [`pretrip_decision_advisor`](https://pub.dev/packages/pretrip_decision_advisor) — the contract + reference advisor + visibility merge
- [`pretrip_source_jma`](https://pub.dev/packages/pretrip_source_jma) — Japan, JMA / AMeDAS measured visibility
- [`pretrip_source_digitraffic`](https://pub.dev/packages/pretrip_source_digitraffic) — Finland, Fintraffic Digitraffic measured visibility
- [`pretrip_source_met_norway`](https://pub.dev/packages/pretrip_source_met_norway) — global, MET Norway hourly forecast

This example is `publish_to: none` — it is documentation and a runnable
reference, not a published package.
