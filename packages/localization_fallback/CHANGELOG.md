## 0.1.2

Additive and non-breaking. No existing API changes, no behaviour changes;
English remains the default. If you do not want Japanese, nothing about this
release affects you.

### The trust signal — we pointed you at a package that does not exist

The README and the API docs told you to source your `TrustSignal` from a
`position_integrity` package, and linked to it. **That package is not published.**
The link was a monorepo-relative path that resolves to nothing on pub.dev. If you
went looking for it and found a 404, that was our error, not yours, and we are
sorry for the time it cost you.

This release corrects every one of those references and, in their place, documents
**how to compute the verdict yourself** — a worked assessment using only fields a
platform locator already reports (finite geometry, the receiver's own accuracy
estimate, and an implied-speed jump check that catches multipath teleports). It is
in the README under "Computing the trust signal" and on `TrustSignal` itself.

### The default is `trusted`, and we are saying so plainly rather than changing it

`onFix(fix)` defaults to `TrustSignal.trusted` — **it believes the fix.** With the
verdict package missing, that default is what almost everyone was riding, and a
multipath or teleported fix therefore became a confident dot with guidance spoken
from it.

We considered flipping the default to `suspect` in this patch and **decided not
to**, because it would not be the safety improvement it looks like: `suspect` does
not blend the fix at all, it *degrades*. A caller relying on the default would
never anchor on GPS again — permanently degraded, then lost. That is a functional
break wearing a safety costume, and it would arrive silently in a patch.

So the default stands, and is now documented as the hazard it is — at the call
site, on the enum, and in the README. The honest remedy is the one thing the
missing package prevented: **compute a verdict and pass it.** Three field checks
get you most of the way, and they are written out for you.


### Japanese typography — corrected

Two ja chips carried a spaced ASCII-style em dash (`GPSなし — 推定中`,
`おおまかな推定 — 一度も…`), which is the visible fingerprint of an English
sentence with Japanese words dropped into it. They now read 「GPSなし（推定中）」
and 「おおまかな推定：一度も現在地を確定できていません」.

These chips render next to the dot on the driver's screen at the exact moment the
app is telling her it does not know where she is — the one place the copy must
not look machine-produced. The package's Latin-residue test guard did not catch
it (an em dash is not a Latin letter); the guard now rejects a spaced ASCII dash
inside a ja string too.

- feat: `LocalizationMessages` — driver-facing text for this package's honesty
  states, in **English and Japanese**. `LocalizationMode`, `EstimateBasis`, the
  confidence radius, the seconds-since-a-trusted-fix, and the "no position at
  all" bootstrap state all now have plain-language strings a driver can read.
  Resolve a table with `LocalizationMessages.forLanguage('ja')`; unsupported
  languages fall back to English, never to silence.
- **Why this is a safety change, not a cosmetic one.** `LocalizationMode` is an
  honesty label first and a status second — it exists to tell the driver how
  much to believe the dot. An honesty label the driver cannot read does not
  reach her, and the silence where a caveat should be reads exactly like
  confidence. This package's whole contract is that it never emits a
  confidently-wrong fix; saying `lost` only in English, to a driver who reads
  Japanese, breaks that contract at the last inch. `lost` now says 現在地不明 /
  「現在地が分かりません。表示している地点は推定であり、実際の現在地ではありません。」
- **Claim ceiling (binding).** Every string describes *what we know about the
  position*. Not one makes a claim about the ROAD, the WEATHER, or whether it
  is safe to proceed — this package measures none of those. "We do not know
  where you are" is the strongest thing it may say, and it is never dressed as
  reassurance. Tests forbid a safety assertion in any locale.
- No new i18n mechanism: this is the hand-rolled locale-table idiom already
  used by `pretrip_decision_advisor`'s `PretripMessages` — pure Dart, no
  Flutter, no codegen, no network, so the zero-dependency / 32-bit-ARM contract
  is untouched.
- test: exhaustive coverage guards (every `LocalizationMode` / `EstimateBasis`
  has text in every carried locale, so a future enum value cannot ship as a
  blank label); a Latin-residue guard that fails if untranslated English leaks
  into a Japanese string; a guard that no string claims safety; and a
  rendered-output guard against stray ASCII spacing between Japanese sentences.

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
