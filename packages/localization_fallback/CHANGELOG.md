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
