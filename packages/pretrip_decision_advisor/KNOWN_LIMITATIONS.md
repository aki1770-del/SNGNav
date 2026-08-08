# Known Limitations

> **0.5.3. Contract + working reference advisor (`SnowAwarePretripAdvisor`).
> Pure Dart — no weather fetching, no route engine; one runtime dependency
> (`navigation_safety_calibration`) since 0.5.0.**

## Scope

This package ships the abstract contract, its data shapes, and a working
pure-Dart reference advisor plus a source-neutral visibility merge. It does
**not** fetch weather data or integrate a route engine; a source-specific
fetcher (which owns any HTTP dependency) produces the typed inputs and stays
outside this package, so the package itself stays pure Dart.

## Specific limitations

- **No data acquisition.** The package ships the advisor logic and its typed
  inputs, not a weather data source or route integration. A consumer (or a
  separate fetcher package) supplies the `WeatherForecast` and `CommuteShape`.
  This keeps the package pure Dart with no `http`/Flutter dependency.
- **API may change.** The shape of the contract, the DTOs, and the
  enums may evolve in a future minor version. Do not pin application
  logic to specific field names or enum cases without reading the
  current CHANGELOG entry.
- **Reference thresholds are the reference advisor's, not the contract's.**
  The abstract contract declares no numerical defaults. `SnowAwarePretripAdvisor`
  declares its own delay durations, visibility/temperature bands, and
  confidence widths; each is documented at its declaration site, and any
  alternative `PretripAdvisor` implementation must justify its own numbers.
- **No taxonomy claims.** `CommuteFlexibility` and the road-condition
  enum are working substrate, not declared-final taxonomies.
- **`VisibilityObservation` does not validate its own numbers.** `meters` and
  `distanceKm` are plain `double`s with no finiteness constraint, so the type
  accepts `NaN` and `±Infinity` — values the domain has no meaning for. This
  matters because the source adapters build the observation from publisher JSON:
  `double.tryParse` returns `Infinity` for the string `"Infinity"` and for an
  overflowing literal such as `"1e400"`. As of 0.5.3 the consuming seams treat a
  non-finite reading as ABSENT rather than crash on it (see CHANGELOG 0.5.3 §1d,
  §1e, and §2c), which upholds *on those seams* the rule stated below — *one
  dirty slot must never crash a briefing* — but each seam has to remember, and
  that is the same shape as the defect. **Check `meters.isFinite` before you
  construct one.** A type that cannot hold a non-number is the real fix and
  belongs on the 0.6.x line: a validating constructor here would break a consumer
  whose debug build passes such a value through today.

  **The rule is not yet upheld package-wide.** See the next entry: an
  out-of-range `TripGeo` still crashes the whole briefing.

- **`TripGeo` does not validate its own numbers either. An OUT-OF-RANGE one
  CRASHES THE WHOLE BRIEFING — and below the crash it returns a confident WRONG
  clock. This is open in 0.5.3.** `latitude` and `longitude` are plain `double`s
  on a public, exported class — no `assert`, no guard — so a value that names no
  point on Earth reaches the offline daylight clock and
  `Duration(minutes: minutesUTC.round())` throws
  `UnsupportedError: Unsupported operation: Infinity or NaN toInt`. Reproduced
  against the **published 0.5.2 archive** and against the 0.5.3 tree, identically.

  **CORRECTION, and read it before anything else in this entry: this file used
  to tell you to check `geo.latitude.isFinite && geo.longitude.isFinite`. That
  guard passes and the briefing still crashes.** At latitude 39.72, a
  `longitude` of `1e90` is finite, is not `NaN`, is not `Infinity` — `isFinite`
  returns `true` on both fields — and `brief()` throws. If you wrote that check
  on our advice, it does not protect you. **Check the RANGE instead:**

  ```dart
  bool isRealPlace(TripGeo g) =>
      g.latitude  >= -90  && g.latitude  <= 90 &&
      g.longitude >= -180 && g.longitude <= 180;
  // NaN fails both comparisons, so this subsumes the old isFinite check.
  ```

  Or pass `geo: null` — the daylight feature is optional and a null `geo` is
  fully supported. Unlike `VisibilityObservation`, no source adapter in this
  family constructs a `TripGeo`: the value comes from *your* location source,
  which is where the check belongs today.

  Four things make this the sharpest constraint in this file:

  1. **It is untyped.** It is NOT a `PretripDataAbsentException`, so the
     `on PretripDataAbsentException` clause this package asks integrators to
     write does not catch it.
  2. **It is not a chip — it is the briefing, through four doors.** `brief()`,
     `briefOrNull()` and `advise()` all throw, reached from `_selectDaylight`
     whenever `CommuteShape.geo` is non-null — and so does
     **`evaluateDaylight(instant, geo)` called directly**, which is a public
     top-level function exported from the barrel and needs no `CommuteShape` at
     all. (`allClearEarned()` returns normally; it never consults the clock.)
  3. **Most of the door is silent.** Out of range does not mean it throws. A
     `longitude` of `1e20` returns `preDawn` with sunrise `08:59` and sunset
     `08:59`; a `latitude` of `180` returns `daylight`, sunrise `05:52`, sunset
     `17:45`; a `latitude` of `1e300` returns `polarDay`. **Latitude never
     crashed at any magnitude tested** — it only corrupts the answer. Longitude
     crashes only past an overflow point that *moves with latitude*
     (`1.067e+87` at the equator, `5.000038e+89` at 39.72, `1.000e+90` at
     78.2°N) and differs by sign — so there is no threshold worth guarding
     against, only the range. Note too that an absurd latitude **masks** an
     absurd longitude (`lat: 95, lon: 1e300` returns `polarDay`), so vary one
     field at a time when you test this.
  4. **It violates the rule stated in this file — *one dirty slot must never
     crash a briefing* — more directly than the defect 0.5.3 fixed**, because
     there is no slot involved and nothing degrades: the briefing simply stops.

  **One bound on the range check, so this entry does not repeat its own
  mistake:** passing it does not mean the call cannot throw. `TripGeo.utcOffset`
  is an unconstrained public `Duration` and `instant` an unconstrained public
  `DateTime`; neither can be non-finite, so no finiteness or range check looks
  at them, yet an extreme *legal* value of either throws a different untyped
  error — `RangeError (millisecondsSinceEpoch)` — out of the same function
  (measured boundary: `Duration(days: 99979531)` returns, `99979532` throws).
  Not reachable from any real device, and stated anyway.

  A `TripGeo` that cannot hold a value which is not a place is the real fix and
  is the same 0.6.x question as `VisibilityObservation` above. What the advisor
  should *do* when the location is not a location is a safety question and is
  not settled here. Tracked in CHANGELOG 0.5.3 *Honest bounds*, first entry.
- **No driver-profile coupling.** `DriverProfileSpec` is intentionally
  small and decoupled from any other package. A concrete advisor
  needing a richer profile model should adapt at its boundary, not
  push the dependency back into this interface.

- **Humidity-aware black ice (0.5.0) is envelope-bounded and
  UNVERIFIED-conservative.** `hazardOf` flags caution when the Magnus
  effective road-surface estimate (dew point) is at/below 0 °C **and**
  ambient is at/below `+3.0 °C` (`radiativeFrostAmbientCeilingCelsius` —
  the calibration's documented "several degrees above 0 °C" radiative
  envelope). Without the ceiling the dew-point test fires on benign dry
  days (probe-measured: 20 °C at 25% RH) — the bound is load-bearing, not
  cosmetic. The calibration's surface-cooling magnitude is documented
  UNVERIFIED-conservative (early-warning direction). The condition reads
  `HourlyForecast.humidityRH` as PERCENT and silently ignores (never
  throws on) sentinels, sub-1% mis-wired fractions, supersaturation
  beyond 105%, and non-finite values — one dirty slot must never crash a
  briefing. This is the loudest behavior change in the package's history:
  mornings that briefed CLEAR at 0.4.0 can brief caution at 0.5.0.

  *Why +3.0 and not 4–5*: the ceiling reads the calibration's prose at its
  minimum deliberately — at introduction, the false-positive cost (cry-wolf
  eroding trust in every chip) dominates the marginal early-warning shoulder
  (probe-measured shapes like 3.5 °C/70% RH sit inside the calibration's
  prose envelope but outside the ceiling). **Evidence tripwire to widen**: a
  real observed frost/black-ice event at 3–5 °C ambient re-opens the ceiling
  decision with data; homing the envelope constant in
  `navigation_safety_calibration` itself (single source of truth) is the
  recorded follow-up so future consumers don't re-derive divergent ceilings.

  *Saturated-air blind spot (inherent to the ratified dew-point-floor
  model)*: at very high humidity the dew point approaches ambient, so the
  highest-humidity above-zero mornings (e.g. +1 °C at 95–100% RH, classic
  freezing-fog territory) can never fire this condition — the surface
  estimate equals ambient, which is above zero. This is a property of the
  calibration's conservative estimator, not a regression; freezing-fog
  coverage at those shapes needs a visibility/fog signal, not humidity.

## When this file changes

These constraints are current at 0.5.3. Re-evaluate them against the shipped
artifact whenever the contract surface or the reference advisor's behaviour
changes; until then, treat every section here as a binding constraint.
