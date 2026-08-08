# vehicle_condition_fusion — the published 0.3.x maintenance line

This directory is the **exact source of the published `0.3.x` line**, preserved so
the future-We can reproduce and patch what consumers actually hold.

## Why it exists as a separate directory

`packages/vehicle_condition_fusion/` has moved on to a **breaking `0.5.0`**
(nullable `bool? iceRisk`, tri-state absence). Consumers pinned `^0.3.x` will never
receive it — a caret does not admit a new minor on a `0.x` package. The only vehicle
that reaches them is an **in-range patch on the `0.3.x` line**, and that line must
therefore continue to exist somewhere we can build and publish from.

## Why it was reconstructed from the pub.dev archive

`0.3.2` was published on 2026-07-12 **and never committed**: `git log` for this
package goes `0.3.1 → 0.4.0 → 0.5.0`, and the local CHANGELOG still tells consumers
that "0.3.1 is the version currently on pub.dev, and the one you are almost
certainly holding" — which is false. The published record was right; ours was the
one that lied.

So `0.3.3` was built from `pub.dev/api/archives/vehicle_condition_fusion-0.3.2.tar.gz`
— the only honest record of what consumers hold — with the never-clamp fix applied
on top. This directory is that source, committed, so it does not happen a third time.

## What 0.3.3 fixed

`fromVss` clamped the VSS friction percent into `0.0..1.0`, so a finite out-of-spec
value (a broken ESC's `255` sentinel) became `(255/100).clamp(0,1) == 1.0` — a
*positively measured* full grip, manufactured out of a dead sensor and handed to
every caller reading `roadFriction`. Out-of-spec finite values now read as **absent**.

The bug had a **test defending it** (`test('friction clamp: 150% → 1.0, -5% → 0.0')`),
sitting fifteen lines above a test refusing the identical harm for `NaN`. That test is
inverted here.

**Honest bound:** on this line `iceRisk` is a bare `bool` and cannot say "unknown", so
the *ice verdict* is unchanged by 0.3.3. What is fixed is the fabricated public
`roadFriction` field. The tri-state that models "we did not measure the road" is the
breaking change on the `0.5.x` line.

## What 0.3.4 fixed

The residual 0.3.2 wrote down and left open: an **unmeasured** ambient
temperature was substituted with `+5.0 °C` and read downstream as a measurement.
It typed falling snow as `rain` (a −5 °C snowfall → `wet`, grip 0.70, or at
heavy intensity "Standing water — risk of aquaplaning at speed"), and it carried
a no-precipitation frame past the residual-ice `temp <= -3` branch out to `dry`
at gripFactor **1.00**, "Conditions normal" — an affirmative all-clear about a
road whose deciding field nobody read, reachable from a frame as ordinary as
`TCS.IsEngaged: false` with no temperature leaf.

Closed by abstaining instead: `vehicleSignalsToWeatherConditionOrNull` returns
`null` iff no ice hazard is asserted AND the temperature was not measured, and
the fusion emits that through the nullable-`assessment` channel it has carried
since 0.1.0. A non-finite reading now counts as unmeasured in the ice rule too
(`NaN <= 2.0` is `false`, so a corrupt sensor had been behaving exactly like a
warm one — worse than the `null` case 0.3.2 fixed).

**Honest bound:** `WeatherCondition.temperatureCelsius` is still non-nullable on
`driving_weather 0.4.x`, so on a HAZARD emission with no measured temperature
the field still carries `5.0`. The verdict does not depend on it; a caller that
prints it will print a number nobody measured. The type-level fix is `0.5.x`.

**Seed provenance for this patch:** the worktree was branched from `e682a66`
(this directory) and proven byte-identical to
`pub.dev/api/archives/vehicle_condition_fusion-0.3.3.tar.gz` — 18/18 files, only
this `MAINTENANCE.md` extra — before a line was changed. It is now `.pubignore`d
so the published archive stays exactly the package.

## To patch the line again

Work in this directory, bump the patch version, `dart test`, `dart pub publish`.
Keep it in range (`< 0.4.0`) or it reaches nobody.
