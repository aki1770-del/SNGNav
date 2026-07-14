# W0 — DETECTION-SURVIVAL LAYER — DESIGN + CODE-CHANGE PLAN

> **STATUS: DESIGN ONLY. NOT COMMITTED. NOT BUILT.**
> This is the INPUT to a later adversarial-review build workflow (OPS-068). It
> contains a design + the exact diffs-to-make. No code here is claimed compiled,
> tested, or shipped. Producers: AAE + SDE + AAA-dignity + NDI.

## Mission anchor (OPS-060B)

HER mother, 70+, rural Akita, in a mountain pass where Google Maps + GPS + the
cell network have ALL died. **Today, offline, she hears no ice warning at all** —
on a JMA fetch failure the app throws away the last-known observation
(`main.dart:1072-1075`) and every winter warning goes mute (DEAD_ZONE manifest
GAP-1). This layer is what makes the winter warning survive the network dying:
≤4 hops — retain last-known black-ice reading → speak it honestly time-stamped →
HER hears it and slows → HER survives the whiteout.

## The Chair ruling this implements (policy — not re-litigated here)

On JMA feed loss the app must:
- **SLOW-varying hazards** (invisible black ice / radiative-cooling freeze):
  RETAIN the last observation within a staleness bound and KEEP announcing,
  HONESTLY TIME-STAMPED — never spoken as live/current.
- **FAST-varying hazards** (turmoil: downpour / strong wind): go SILENT once the
  reading is stale (a 20-min-old gust may be gone — no cry-wolf).
- **NO reading at all** (never had one, or past the staleness bound): announce
  the absence-line 「路面状況を取得できていません。見える範囲で運転してください。」

---

## 0. MEASURE FIRST — what the real code does today (OPS-062, every claim cited)

| Fact | Evidence (file:line) |
|---|---|
| `_refreshJma` fetches, and on `JmaSuccess` evaluates both watches; on any non-success it sets ice=`unknown`, turmoil=`null` and **discards last-known** | `sngnav-app/lib/main.dart:1061-1078` (esp. the `else` at 1072-1075) |
| The failure branch overwrites `_jmaResult` with the `JmaFailure`; there is **no separate last-good field** | `main.dart:1066-1067` + state fields `main.dart:360-372` |
| `_announceWatchTransitions` announces each watch ONCE on its rise (`iceRose`/`turmoilRose`), warning tier, ja/en verbatim | `main.dart:1101-1134` |
| Announce gate: `severity.index < AlertSeverity.warning.index → return` (info is NOT spoken, so absence must be ≥ warning to be audible) | `alert_announcer.dart:53`; enum `info(0) < warning(1) < critical(2)` in `navigation_safety_core/lib/src/alert_severity.dart:11-19` |
| Live black-ice line (the one to make a stale variant of) | `snow_rendering/.../road_surface_announcement.dart:94-105` → `ブラックアイスバーンに注意。路面は濡れて見えても、凍結しているおそれがあります。急ハンドル、急ブレーキは厳禁。速度を落としてください。` |
| Absence-line exists but is **UNWIRED** in the app (GAP-2) | `road_surface_announcement.dart:200-205` (`conditionsUnknownAnnouncement`), exported via barrel `snow_rendering.dart:27` |
| `invisibleBlackIceAnnouncement` already imported into main via `show` | `main.dart:75-76`, used at `main.dart:1118-1119` |
| Invisible-ice watch = SLOW hazard evaluator (pure, sync) | `services/invisible_ice_watch.dart:51-79` |
| Turmoil watch = FAST hazard evaluator (rain/wind channels, pure, sync) | `services/turmoil_watch.dart:91-119`; spoken line `:160-186` |

### 0.1 — CRITICAL FINDING: does the JMA observation carry a TRUE observed-at time? **YES.**

`JmaObservation` carries **two** time fields (`jma_fetch.dart:82-88`):

- **`observedAtJstKey`** (`:84`) — *"Observation timestamp in JST as reported by
  JMA (yyyymmddHHMMSS)"*. It is set from JMA's own `latestKey` — the key of the
  latest per-10-minute record in the station bucket file (`jma_fetch.dart:174-177,
  205`). **This is the TRUE observed-at time**, not a receipt stamp. It is a
  14-digit JST string (e.g. `20260115063000`), already parsed as such elsewhere:
  `corridor_row.dart:87-89` slices `substring(8,10):substring(10,12)` → `HH:MM`.
- **`fetchedAt`** (`:87`) — `DateTime.now()` at fetch (`:206`); wall-clock receipt,
  NOT observation time.

**Therefore the staleness stamp MUST use `observedAtJstKey`, honestly — never
`fetchedAt`.** Note the existing helper `minutesStale(now)` (`jma_fetch.dart:103`)
computes age from **`fetchedAt`** — that is fetch-relative and is NOT what this
layer needs; do not reuse it for the stamp or the bound.

**Two honesty caveats on the observed-at (flagged, not assumed):**
1. `observedAtJstKey` is a **JST wall-clock string with no timezone marker.** To
   compare against `DateTime.now()` it must be parsed as a **local** `DateTime`
   (`DateTime(y,mo,d,h,mi,s)`), which equals JST **only on a device whose clock is
   JST** — true for HER phone in Akita, but NOT on a non-JST test host. This is an
   attack point (§ safety review #3); tests must inject `now` consistent with the
   constructed observedAt.
2. AMeDAS publishes per-10-minute, so even a *fresh successful fetch* has an
   `observedAtJstKey` up to ~10-13 min behind `fetchedAt` (we take the latest
   published record). Measuring the bound from `observedAtJstKey` is the honest
   choice and is what the spoken stamp reports — the two stay consistent.

---

## 1. Last-known cache

**What to retain:** the whole last **successful** `JmaObservation` (it already
carries `observedAtJstKey` + every measured field, so the watch verdicts can be
recomputed deterministically from it — no need to also cache the verdicts).

**Where:** a new field on `_HomePageState`, distinct from `_jmaResult` (which is
overwritten by a `JmaFailure`):

```dart
// main.dart — add near the JMA state block (~ after :361)
// W0 detection-survival: last-known GOOD observation, retained across a feed
// loss so slow-varying winter hazards survive the network dying. Set ONLY on
// JmaSuccess; NEVER cleared on JmaFailure (that is the whole point).
JmaObservation? _lastGoodObservation;
```

**Observed-at vs receipt-time:** we DO have the true observed-at
(`observedAtJstKey`), so we do **not** fall back to receipt-time. The stamp is the
observation time, honestly. (If a future feed lacked an observed-at, receipt-time
would be honest-enough only when fetch latency is small — not our case; noted for
completeness, not used here.)

**Testability seam (optional, recommended):** add an injectable clock so the age
computation is host-deterministic (OPS-066):
```dart
// HomePage widget field (~ near the other injectables, :240-260)
final DateTime Function()? clock; // null -> DateTime.now
// in State:
DateTime _now() => (widget.clock ?? DateTime.now)();
```

---

## 2. Staleness bounds (named tunable constants, AAA-reviewable + device-tunable)

New top-level constants — propose a new file `lib/services/staleness_policy.dart`
(keeps the physics rationale in one auditable place):

```dart
/// SLOW-hazard (radiative-frost black ice) RETAIN-AND-ANNOUNCE window.
///
/// Rationale (meteorological): radiative-cooling / dew-point-driven icing is a
/// quasi-stationary pre-dawn synoptic condition — clear sky, calm air, the road
/// surface radiating heat to space, ambient a few degrees above zero with the
/// dew point at/below 0 °C. These driving forces evolve over HOURS, not minutes,
/// so a reading up to this old remains physically indicative of the SAME
/// black-ice window. 60 min balances "still physically valid" against "old
/// enough that dawn / a wind shift may have ended it". Past this bound we STOP
/// stale-announcing and fall to the honest absence-line — never a stale announce.
/// AAA-reviewable; device-tunable.
const Duration kSlowHazardRetainWindow = Duration(minutes: 60);

/// FAST-hazard (downpour / strong wind) FRESHNESS window.
///
/// Rationale: a convective downpour cell or a gust is transient (minutes); a
/// reading older than this may describe weather that is already gone. Per the
/// Chair's cry-wolf discipline, a fast hazard is NOT announced from a reading
/// older than this — on feed loss the cache is by definition pre-loss, so this
/// makes the fast lane effectively SILENT when the feed is dead. AAA-reviewable.
const Duration kFastHazardFreshWindow = Duration(minutes: 20);
```

- **60 min slow bound** — the recommended value, justified above. It is a
  first-cut; AAA should review against Akita pre-dawn radiative-frost climatology
  and the go-live may device-tune it.
- **20 min fast bound** — matches the Chair's own "a 20-min-old gust may be gone".

---

## 3. Slow vs fast hazard taxonomy (with NDI physics-faithfulness lens)

| Watch | Where evaluated | Class | Feed-loss behavior | Physics faithfulness (NDI) |
|---|---|---|---|---|
| **Invisible ice** (radiative frost) | `invisible_ice_watch.dart:51-79` | **SLOW** | RETAIN + stale-stamped announce within 60 min | **Faithful.** The detector reads temperature + humidity on the no-precip branch (`:60-78`); those + the radiative balance evolve over hours. A black-ice window from an hour ago is still physically indicative. |
| **Turmoil — rain** | `turmoil_watch.dart:91-102` | **FAST** | SILENT when stale | **Faithful.** 10-min precipitation ×6 → hourly-equivalent (`:98`) captures convective downpour cells that come and go in minutes. Stale → gone → silence is correct. |
| **Turmoil — wind** | `turmoil_watch.dart:104-111` | **FAST** (see caveat) | SILENT when stale | **Caveat (NDI + review #2):** a *sustained synoptic gale* (台風-class, 暴風) is slower-varying than a downpour cell — closer to "slow". Lumping wind with rain as uniformly "fast" is a defensible first cut (AMeDAS wind is a 10-min mean, `:107`), but a sustained gale that silently drops on feed loss is a real loss. Flagged for adversarial review; NOT resolved here. Note the 台風/暴風警報 lane is separate (verbatim JMA warnings, `turmoil_watch.dart:33-36`) and is not this watch. |

Taxonomy is encoded structurally: the slow lane recomputes
`evaluateInvisibleIceWatch(cache)`; the fast lane is simply **not invoked** from
the cache on feed loss.

---

## 4. The honest stale-framed spoken line (AAA lens)

**Requirement:** unmistakably past-tense/observed; never fakes liveness;
possibility-graded; carries an explicit "this is not live" clause.

**Time slot decision: round to the NEAREST HOUR, spoken as 「○時頃」.**
- **Why hour, not minute:** (a) AMeDAS observations are already 10-min-quantized —
  minute precision would be false precision; (b) 「頃」("approximately") makes
  hour-rounding honest; (c) a small fragment set (24 hour values) is
  human-recordable as whole clips, honoring the DEAD_ZONE manifest's
  whole-phrase / pitch-accent discipline (§ manifest note below).
- **Round to NEAREST, not floor:** floor (truncate) understates age (06:50 → "6時")
  and could read fresher than reality; nearest-hour errs toward sounding OLDER,
  which is the safe direction for a staleness stamp. The 60-min BOUND is computed
  on the **exact** `observedAtJstKey` DateTime, so rounding affects only the spoken
  word, never the retain/expire decision.

### Recommended ja stale-framed black-ice line

```
○時頃の観測では、ブラックアイスバーンのおそれがあります。最新の情報は取得できていません。急ハンドル・急ブレーキを避け、速度を落としてください。
```

Clause-by-clause (AAA):
- 「○時頃の観測では、ブラックアイスバーンのおそれがあります。」 — **past-framed**
  (観測では + おそれ). Unmistakably an observation from a past hour, possibility-graded.
- 「最新の情報は取得できていません。」 — **explicit not-live** disclaimer; reuses the
  取得できていません verb from the absence-line for vocabulary consistency. **This
  clause is load-bearing and must not be dropped under length pressure** (it is the
  only spoken guarantee HER is not hearing a live reading — review point #1).
- 「急ハンドル・急ブレーキを避け、速度を落としてください。」 — the core black-ice action
  (avoid abrupt input + slow down).

**AAA length trade-off (flagged, not hidden):** to make room for the timestamp +
not-live clause without exceeding the live line's length, the recommended variant
drops 「路面は濡れて見えても…」 (the looks-wet explainer). Defensible because the term
ブラックアイスバーン itself carries invisibility in Japanese lay + JAF understanding.
**Alternative** that keeps looks-wet (longer, 4 clauses):
```
○時頃の観測では、ブラックアイスバーンのおそれがあります。最新の情報は取得できていません。路面は濡れて見えても凍結しているおそれがあります。速度を落としてください。
```
The choice between "keep the prohibition (急ハンドル・急ブレーキ)" vs "keep looks-wet"
is an AAA/adversarial-review decision, surfaced here.

**en parity (for the en locale path):**
```
As observed around ○ o'clock, there may be black ice — this is not a live reading. Avoid abrupt steering or braking, and reduce speed.
```

### DEAD_ZONE_SAFETY_MANIFEST update needed

Add to `packages/voice_guidance/DEAD_ZONE_SAFETY_MANIFEST.md`:
- **Section 1 (offline manifest)** and **Group C**: a new row
  `surface_invisible_black_ice_stale` — ja text = the recommended line above with
  the hour as a slot; shape = **TEMPLATED (○時頃 hour slot)**; channel-origin =
  **LOCAL/CACHED** (fires on feed-loss from the retained observation); offline =
  **YES**. This is the FIRST templated dead-zone phrase, so record the
  **whole-phrase carrier + 24 hour-fragments** — PREFERRED = 24 WHOLE per-hour
  clips (whole-slotless, pitch-accent clean, per the manifest's standing prosody
  caution at its Summary); ACCEPTABLE fallback = one carrier + spliced
  「○時頃」 fragment, carrying the manifest's documented pitch-accent-at-the-seam risk.
- Update **GAP-1** ("signature winter warnings cannot fire in a pure dead-zone")
  and **GAP-2** ("the one perfect dead-zone line is not wired") from OPEN to
  "closed by W0 detection-survival layer" once this design is built.

---

## 5. GAP-2 wiring — fire the absence-line through `AlertAnnouncer.announce()`

**Severity: `AlertSeverity.warning`.** Reasoning (record this): the absence is not
a hazard, so it must NOT be `critical`; but `info` is dropped by the announce gate
(`alert_announcer.dart:53`) and would never speak. `warning` is the **audibility
floor** — it reaches the OPS-059 audio + haptic floor without crying critical.

Import change (`main.dart:75-76`) — extend the existing `show`:
```dart
import 'package:snow_rendering/snow_rendering.dart'
    show invisibleBlackIceAnnouncement, conditionsUnknownAnnouncement;
```
Announce call (inside the new feed-loss branch, § 6):
```dart
await _announcer.announce(
  severity: AlertSeverity.warning,
  text: _spokenJa
      ? conditionsUnknownAnnouncement.jaSpokenText
      : conditionsUnknownAnnouncement.enSpokenText,
  localeTag: ttsTag,
);
```
(The stale black-ice announce also fires at `warning` — it must not be *more*
severe than the LIVE black-ice announce, which is already `warning` at
`main.dart:1116`.)

---

## 6. The precise code-change plan (NOT COMMITTED — diffs to make)

### 6a. `lib/services/staleness_policy.dart` — NEW FILE
The two constants from § 2 (with their rationale doc-comments) + a parse helper:
```dart
/// Parse a 14-digit JMA observedAtJstKey (yyyymmddHHMMSS, JST wall-clock) into a
/// LOCAL DateTime. Returns null if the key is not 14 digits (caller then treats
/// it as no-reading → absence-line). NOTE: parsed as LOCAL time — correct only on
/// a JST-clock device (HER phone in Akita); see safety review #3.
DateTime? observedAtJstAsLocal(String key) {
  if (key.length != 14) return null;
  final y = int.tryParse(key.substring(0, 4));
  final mo = int.tryParse(key.substring(4, 6));
  final d = int.tryParse(key.substring(6, 8));
  final h = int.tryParse(key.substring(8, 10));
  final mi = int.tryParse(key.substring(10, 12));
  final s = int.tryParse(key.substring(12, 14));
  if ([y, mo, d, h, mi, s].contains(null)) return null;
  return DateTime(y!, mo!, d!, h!, mi!, s!);
}

/// Nearest-hour (0-23) for the spoken 「○時頃」 stamp. Nearest, not floor, so the
/// spoken stamp errs toward sounding OLDER (safe direction). Bound is computed on
/// the exact DateTime, not this rounding.
int nearestHourJst(DateTime observedAtLocal) {
  final rounded = observedAtLocal.minute >= 30
      ? observedAtLocal.add(const Duration(hours: 1))
      : observedAtLocal;
  return rounded.hour;
}
```

### 6b. `lib/services/invisible_ice_watch.dart` — the stale spoken line
Add an app/catalog string builder for the stale variant (kept beside the watch it
belongs to; it is app-authored, so NOT a verbatim catalog string — label it):
```dart
/// Honest stale-framed black-ice line (W0 detection-survival). App-authored;
/// NEVER spoken as live. [hourJst] is the nearest-hour of the retained
/// observation's observedAt (JST). See W0_DETECTION_SURVIVAL_DESIGN.md §4.
String staleInvisibleBlackIceSpokenText({required int hourJst, required bool ja}) {
  return ja
      ? '$hourJst時頃の観測では、ブラックアイスバーンのおそれがあります。'
        '最新の情報は取得できていません。'
        '急ハンドル・急ブレーキを避け、速度を落としてください。'
      : 'As observed around $hourJst o\'clock, there may be black ice — this is '
        'not a live reading. Avoid abrupt steering or braking, and reduce speed.';
}
```

### 6c. `lib/main.dart` state — add the cache field (~ after :361)
```dart
JmaObservation? _lastGoodObservation; // W0: last SUCCESS obs; never cleared on failure
```
(Optional testability: `DateTime _now() => (widget.clock ?? DateTime.now)();`.)

### 6d. `lib/main.dart` `_refreshJma` (:1061-1078) — STOP discarding last-known; retain + stamp
Intended new logic (Dart sketch — the `else` no longer wipes state we need):
```dart
Future<void> _refreshJma() async {
  setState(() => _jmaLoading = true);
  final result = await (widget.jmaFetch?.call() ??
      fetchLatestObservation(userAgent: kSngnavAppUserAgent));
  if (!mounted) return;
  setState(() {
    _jmaResult = result;
    _jmaLoading = false;
    if (result is JmaSuccess) {
      _lastGoodObservation = result.observation;              // ← RETAIN (new)
      _invisibleIceResult = evaluateInvisibleIceWatch(result.observation);
      _turmoilState = evaluateTurmoilWatch(result.observation);
    } else {
      // Feed loss: do NOT discard _lastGoodObservation. Live verdicts become
      // unknown/null (the LIVE surfaces should not read a stale reading as live);
      // the stale/absence decision is made in _announceWatchTransitions.
      _invisibleIceResult = InvisibleIceWatchResult.unknown;
      _turmoilState = null;
    }
  });
  _announceWatchTransitions();
}
```

### 6e. `lib/main.dart` `_announceWatchTransitions` (:1101-1134) — staleness-aware rewrite
Intended new logic (Dart sketch):
```dart
void _announceWatchTransitions() {
  final ttsTag = _spokenJa ? 'ja-JP' : 'en-US';
  final result = _jmaResult;

  // FRESH-LIVE path — a successful fetch this cycle. UNCHANGED behavior:
  // rise-gated live ice + turmoil announces (existing :1102-1133 body).
  if (result is JmaSuccess) {
    // ... existing iceRose / turmoilRose rise-gated announces verbatim ...
    // Reset the feed-loss gates so re-entry into a later dead-zone re-announces:
    _staleIceActive = false;
    _absenceActive = false;
    return;
  }

  // FEED-LOSS path — JmaFailure or null. Fall back to the retained observation.
  final cached = _lastGoodObservation;
  final observedAt =
      cached == null ? null : observedAtJstAsLocal(cached.observedAtJstKey);

  // (1) NO reading at all: no cache, unparseable stamp, or PAST the slow bound
  //     → the honest ABSENCE-LINE (GAP-2). Fires ONCE per entry (gate), so a
  //     persistent dead-zone does not spam; re-arms via the JmaSuccess reset.
  if (cached == null ||
      observedAt == null ||
      _now().difference(observedAt) > kSlowHazardRetainWindow) {
    if (!_absenceActive) {
      _absenceActive = true;
      _staleIceActive = false;
      unawaited(_announcer.announce(
        severity: AlertSeverity.warning,
        text: _spokenJa
            ? conditionsUnknownAnnouncement.jaSpokenText
            : conditionsUnknownAnnouncement.enSpokenText,
        localeTag: ttsTag,
      ));
    }
    return;
  }

  // Within the slow bound. SLOW hazard (black ice): recompute from the cache and,
  // if the window was present, KEEP announcing honestly time-stamped (Chair:
  // retain + keep announcing). One announce per _refreshJma cycle → ticker
  // cadence rate-limits it (~10-min AMeDAS cycle). A hazard beats the absence
  // line, so ice takes precedence.
  final iceVerdict = evaluateInvisibleIceWatch(cached);
  if (iceVerdict == InvisibleIceWatchResult.watch) {
    _absenceActive = false;
    _staleIceActive = true;
    final hour = nearestHourJst(observedAt);
    unawaited(_announcer.announce(
      severity: AlertSeverity.warning,
      text: staleInvisibleBlackIceSpokenText(hourJst: hour, ja: _spokenJa),
      localeTag: ttsTag,
    ));
    return;
  }

  // FAST hazard (turmoil): SILENT when stale — never announced from cache
  // (cry-wolf discipline). No-op by construction (the fast watch is not invoked
  // on the cache).
  //
  // Within-bound, non-watch (cached says clear, or ice channel abstained):
  // SILENT. We are NOT in absence (we have a reading ≤60 min old), so firing the
  // absence-line here would be FALSE — honest silence is correct. Absence fires
  // ONLY on true no-reading (handled at (1)).
}
```
New gate fields to add beside the cache (:~361):
```dart
bool _staleIceActive = false;  // stale black-ice announce currently active
bool _absenceActive = false;   // absence-line announce currently active
```

**Announce cadence note (honest, not over-designed):** I did NOT verify that
`AlertAnnouncer` routes through `AlertDensityThrottle`; do not assume it does.
Rate-limiting for the stale/absence lines comes from the JMA ticker cadence
(one `_refreshJma` per tick → one announce). If finer control is wanted, add a
`Duration kStaleReannounceMinInterval` guard — flagged, not built.

---

## 7. Verification map (OPS-066 — what can / cannot be verified without a device)

**Host-verifiable (unit / widget tests — MUST accompany the build):**
- `observedAtJstAsLocal` parses 14-digit keys; returns null on malformed → absence path.
- `nearestHourJst` rounds correctly across the :30 boundary and the 23→0 wrap.
- Cache retained on `JmaSuccess`, NOT cleared on `JmaFailure`.
- Feed-loss decision table (inject `clock` + cached observedAt):
  fresh-live → live announce; cache ≤60 min + ice=watch → **stale-stamped** text
  emitted (assert the ja substring 「時頃の観測では」 AND 「最新の情報は取得できていません」);
  cache >60 min → **absence-line** text; cache ≤60 min + turmoil-only → **silent**;
  no cache → **absence-line**; boundary at exactly 60 min (assert `>` semantics).
- Severity is `warning` on both new announces (so they clear the audibility floor).

**Device-DEFERRED (cannot verify on host — mark honestly):**
- That HER actually HEARS the line (TTS voice installed, media volume, audio focus).
- That the hour number + 「頃」 are pronounced clearly by the device ja TTS voice.
- Real on-device feed-loss timing (airplane-mode drive pass).

---

## 8. OPS-068 — top-3 things a safety reviewer MUST attack

1. **Could a stale black-ice stamp read as LIVE?** Attack the framing: does a
   distracted 70-yo parse 「○時頃の観測では」 as past vs present? Is
   「最新の情報は取得できていません」 load-bearing enough that dropping it under length
   pressure (the AAA trade-off in §4) would remove the ONLY spoken liveness
   disclaimer? Does device TTS pronounce the hour+頃 unambiguously? **Fail toward
   keeping the not-live clause.**
2. **Does the FAST-hazard silence drop a STILL-VALID warning?** On feed loss the
   turmoil lane goes fully silent. A *sustained synoptic gale* (暴風-class) varies
   slower than a downpour cell — lumping wind with rain as uniformly "fast" (§3
   caveat) means a genuine ongoing gale is silently dropped. Attack: should wind
   get its own (longer) bound or a stale-stamped variant, like ice? Is 20 min right?
3. **Staleness-bound off-by-one / timezone at the boundary.** `observedAtJstKey` is
   parsed as LOCAL time (§6a) — correct only on a JST device; a non-JST parse could
   make a hours-old reading look 60-min-fresh and stamp it near-live. Attack the
   `>` vs `>=` at exactly 60 min (stale-announce vs absence-line), and the
   observedAt-vs-fetchedAt gap (AMeDAS observedAt is already ~10 min behind
   fetch — is the 60 min correctly measured from observedAt, not fetch?).

**Secondary flag (worth a fourth look):** the "within-bound but ice=`unknown`"
sub-case is designed to be SILENT (we have a recent reading, just not a conclusive
ice one). A reviewer should confirm this does not SWALLOW a true dead-zone — the
absence-line must still fire on genuine no-reading (no cache / expired), which it
does at branch (1).

---

## 9. Honest-absence discipline (self-check)

- Stale data is NEVER presented as current: every cached announce carries the
  past-framed stamp + the explicit not-live clause (§4).
- The absence-line fires on TRUE absence only (no cache / unparseable / past bound),
  and is NOT swallowed — it is branch (1), reached before any silent path (§6e).
- Within-bound "clear/unknown" is honest SILENCE, not a false absence-line and not
  a false all-clear (we neither claim conditions we lack nor stay mute on a hazard
  we hold).
