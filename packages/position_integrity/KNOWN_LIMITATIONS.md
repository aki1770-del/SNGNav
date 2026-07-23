# Known limitations

This package is a **floor**, not a guarantee. It states plainly what it does not
do, because a safety component that overstates itself becomes the false
confidence it exists to prevent.

## 1. `trusted` is not "correct"

A `trusted` verdict means only that none of the plausibility gates fired for
this fix. Measurement plausibility is **not** state correctness. A fix can be
perfectly consistent with recent motion and still be wrong (e.g. a coherent
multipath that mirrors real movement). Never present `trusted` to a driver as
"your position is verified".

**In particular, a MODERATE jump within road-plausible speed is not caught.**
The gates trip on a jump that implies more than `maxPlausibleSpeed` — at a 1 Hz
fix rate that is roughly a **> 50 m** sideways jump. A smaller coherent
multipath offset — measured at ~19–45 m sideways at 1 Hz — implies a legal
speed, so it reads `trusted` (or at most a single `suspect` from the
acceleration gate) with **no source handoff**. That smaller offset is the
*common* urban-canyon multipath the lead describes; this floor catches only the
gross version of it. Catching the moderate case needs the roadmap NIS /
motion-consistency layer, not this floor.

## 2. It is not anti-spoofing

The gates catch **abrupt** faults — teleports, impossible speed, impossible
acceleration. They provably do **not** catch a slow, smooth spoof that walks the
position away a few metres per second within plausible limits. A determined
spoofer can stay under every threshold. Market this as multipath / urban-canyon
/ teleport protection, not as defeating a spoofing attack.

## 3. Thresholds are physical defaults, not tuned to your vehicle

`maxPlausibleSpeed` (50 m/s) and `maxPlausibleAccel` (8 m/s²) are road-vehicle
defaults. A genuine high-speed context (autobahn, rail) will trip
`impossibleSpeed`; raise the threshold. Conversely, a vehicle that legitimately
exceeds them is outside this floor's scope.

## 4. The handoff is only as good as your fallback

On a fault the monitor can recommend `deadReckoning`, but only if you pass a
fresh `deadReckoningAge`. It does **not** know whether your dead-reckoning
estimate is actually any good — it only knows it is recent. Over a long GPS
blackout your DR will itself degrade; condition your own use of the
recommendation on DR quality, and prefer `hold` when in doubt. The monitor
defaults to `hold` whenever it cannot vouch for a fresher source.

## 5. Stationary-jitter is a heuristic

The `stationaryJitter` gate is a coarse "parked but wandering" detector based on
net-vs-step displacement over a short window relative to the reported accuracy.
It is `suspect`-only (it never escalates to `failed` on its own) and can both
miss subtle drift and, with an optimistic accuracy number, fire on legitimate
slow creep. Treat it as a caution hint.

## 6. The NIS / chi-square consistency layer is not in this release

This release is the calibration-free floor only. The statistical layer that
consumes an independent motion prediction (to catch fixes that are *possible*
but inconsistent with how the vehicle is actually moving) is a later slice. Until
then, the floor catches the gross, physically-impossible faults and nothing
finer.

## 7. Recovery has a one-fix transient

After a teleport, the fix that jumps *back* to the true track is itself a large
jump, so the monitor reports `failed` again on that return fix before returning
to `trusted` on the next clean fix. The return fix is genuinely implausible, so
this is expected — but it means recovery lags the real recovery by one fix.

**And if the position does NOT jump back — a sustained jump onto a parallel
street — the monitor re-baselines onto the displaced fix and reads `trusted`
again on the very next fix.** Measured: a 200 m teleport reports `failed` once,
then `trusted`/`gps` for every subsequent fix that continues along the wrong
street. So the floor flags the *transition* onto the wrong position, not the
ongoing wrong position: act on the `failed` when it fires; do not expect a
standing fault while a displaced-but-now-self-consistent track continues.

## 8. The first fix after a long gap is only weakly checked

The `impossibleSpeed` gate allows a jump up to `maxPlausibleSpeed × dt`. After a
long inter-fix gap (a tunnel or GPS blackout — exactly the scenario this package
leads with), `dt` is large, so the first reacquired fix can be far off and still
pass: a 20 s gap permits a ~1000 m jump as `trusted`. The teleport gate does not
cover this (it only runs for sub-`minSpeedDelta` deltas). If your app knows it
just emerged from a blackout, treat the first reacquired fix with extra caution
regardless of this floor's verdict.

## 9. The rate gates warm up

`impossibleAccel` needs two prior motion fixes, so the first moving fix — and the
first fix after any sub-`minSpeedDelta` fix — is checked by the speed/teleport
gates only, not by acceleration. The `gateResults` map omits the gate when it
was not evaluated; do not read an absent gate as a pass.

## 10. Sub-`minSpeedDelta` jumps under the teleport distance are not speed-checked

For deltas below `minSpeedDelta` (default 100 ms, i.e. streams faster than
~10 Hz), only the absolute-jump teleport gate runs. A jump under
`teleportMaxDistanceMetres` (default 30 m) in, say, 20 ms is ~1500 m/s yet passes,
because no reliable speed is computed at that timescale. For typical ≤10 Hz fused
streams this regime is not reached; for faster streams, lower
`teleportMaxDistanceMetres` or down-sample before the monitor.

## 11. An intermittent fault stays `suspect`

Escalation to `failed` requires *consecutive* impossible-acceleration faults; a
clean fix resets the counter. A sensor that faults every *other* fix therefore
stays `suspect` indefinitely and never reaches `failed`. This matches the
documented "sustained" contract, but an every-other-fix fault is a real
condition your app may want to watch for across verdicts.
