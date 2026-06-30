## 0.1.1

- fix: `lost` is now TERMINAL until re-acquisition. Previously a time-triggered
  `lost` could be silently un-lost — resurrected to `deadReckoning` or
  `gpsSuspect` — by a backwards / out-of-order / clamped `poll(now)` or a
  `suspect`/`failed` fix, restoring confidence with NO trusted fix. This
  violated the documented contract that a trusted fix is the only way back from
  `lost`. A `_lost` latch now holds the mode at `lost` until a fresh, newer
  trusted fix reconverges (the latch is cleared only by `onFix` with a trusted,
  newer fix).
- fix: a garbage configured `driftRateMetersPerSecond` (NaN / negative /
  infinite) can no longer fabricate precision. `LocalizationConfig`'s asserts
  are stripped in release / `dart run`; with a garbage drift the growth model
  previously produced a radius of `0 m` (a false "exactly here" dot) in
  `deadReckoning`. The radius is now clamped to never fall below the last
  trusted accuracy, and an un-modellable (garbage) drift degrades honestly to
  `lost` instead of inventing certainty.
- test: added a "lost is terminal until reconvergence" suite (backwards-poll,
  suspect-after-lost, failed-after-lost, trusted-re-acquisition) and a
  "garbage configured drift" hardening suite (NaN / -inf / negative → lost,
  radius never below last trusted accuracy, plus a sane-drift regression guard).
- docs: corrected the README and dartdoc — `mode` is not memoryless; the radius
  is monotonic and `lost` is terminal until a trusted fix reconverges.

## 0.1.0

- Initial release.
- `LocalizationController`: a pure-Dart, synchronous state machine that turns
  raw fixes + an optional per-fix trust signal + an optional dead-reckoning
  seam into one honest `LocalizationEstimate`.
- First-class `LocalizationMode`: `gpsTrusted` / `gpsSuspect` / `deadReckoning`
  / `lost`.
- Honesty contract enforced in code and tests: monotonic non-decreasing
  confidence radius while not trusted; `lost` as a first-class honest state;
  every estimate carries its `EstimateBasis`; suspect/failed fixes are never
  blended in as if trusted.
- Zero runtime dependencies; runs on 32-bit ARM.
- Trusted-path honesty horizon: a `trusted` fix whose own reported accuracy
  exceeds `maxTrustworthyRadiusMeters` is adopted as the baseline but presented
  as `lost`, never as a confident dot.
- Timestamp sanity on the trusted path: an out-of-order / stale / duplicate
  "trusted" fix (timestamp not newer than the last) is ignored — it does not
  snap the dot to stale coordinates and does not rewind the elapsed-time clock.
- Frozen-path radius now floored by the last trusted fix's ground speed, so the
  confidence circle still plausibly contains a vehicle that kept moving after
  GPS dropped (no seam wired).
- `LocalizationEstimate.hasPosition` getter so integrators fail safe instead of
  plotting a `NaN` dot in the bootstrap "nothing seen yet" state.
- Removed the unimplemented `fixGapThreshold` config field (it was a no-op);
  drive blackout degradation via `poll(now)` on a tick.
