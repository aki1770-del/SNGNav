# DEAD-ZONE SAFETY AUDIO MANIFEST — W1 (voice_guidance + AAA-dignity)

> **This is a CONTRACT, not an implementation.** It freezes *which pre-rendered
> bundled Japanese warning audio must speak* when Google Maps + GPS + the cell
> network have ALL died on a 70-year-old rural-Akita driver's old kei-car phone.
> **No audio asserted here exists yet.** Every phrase below was read from source
> (OPS-062: no phrase asserted without reading its file:line).

**Mission anchor (OPS-060B).** The ONE test: does HER actually HEAR the correct
Japanese winter warning, offline, no config, in the pass — driver in unexpected
snow, ≤4 hops (pre-render → offline clip → HER hears the warning → she acts →
HER survives the whiteout). **A phrase that requires a live network or a live GPS
route is MOOT in the dead-zone and does NOT go in the offline manifest.**

**File location note.** Written to `packages/voice_guidance/DEAD_ZONE_SAFETY_MANIFEST.md`
(the `voice_guidance` package dir exists).

**Sources read (measure-first):**
`sngnav-app/lib/services/drive_hud_localizer.dart` ·
`sngnav-app/lib/services/maneuver_narration.dart` ·
`sngnav-app/lib/services/drive_hud_controller.dart` ·
`sngnav-app/lib/services/turmoil_watch.dart` ·
`sngnav-app/lib/services/invisible_ice_watch.dart` ·
`sngnav-app/lib/actuators/alert_announcer.dart` ·
`sngnav-app/lib/main.dart` ·
`navigation_safety_core/lib/src/alert_explainer.dart` ·
`compound_failure_advisor/lib/src/drive_advice_messages.dart` ·
`condition_aggregator_jma/lib/src/jma_advisory_mapper.dart` ·
`japanese_snow_vocabulary/lib/src/jaf_authoritative_data.dart` ·
`snow_rendering/lib/src/models/road_surface_announcement.dart` ·
`voice_guidance/lib/src/maneuver_speech_formatter.dart`.

**The actual spoken lane (traced, not assumed).** In `sngnav-app`, TTS is reached
ONLY through `AlertAnnouncer.announce()` (`alert_announcer.dart:65 → actuators.speak`).
Its call sites are exactly four:
- `drive_hud_controller.dart:189` — position-confidence caution (`spokenGuidance`)
- `drive_hud_controller.dart:233` — gated maneuver narration
- `main.dart:1115 / :1126` — invisible-ice + turmoil watch transitions
- `main.dart:1281` — surface-state `AlertExplainer.action`

Everything else read below is **screen-only** or **catalog-offered-but-unwired**
and is listed as such — I did not pretend a rendered label is a spoken phrase.

---

## SECTION 1 — THE OFFLINE MANIFEST (pre-render THESE)

The only phrases whose trigger is TRUE in a pure dead-zone (no network, no GPS).
All three are **WHOLE-SLOTLESS** → human-recordable as whole phrases, clean prosody.

| clip-id | ja text (verbatim) | source file:line | shape | channel-origin | in offline manifest? | dignity note (AAA) |
|---|---|---|---|---|---|---|
| `caution_heightened_core` | `速度を落とし、車間を広げて、前方に注意してください。` | drive_hud_localizer.dart:51 | WHOLE-SLOTLESS | **LOCAL/MEASURED** — raised by on-device position mode; GPS-loss → `positionUncertain` raises this with no feed | **YES** — fires when GPS dies, no network needed | 3 imperatives in one breath, but each is a plain driving verb a 70yo knows. Acceptable; borderline-long. |
| `caution_consider_stopping_core` | `安全にできるときは、安全な場所での停車も選べます。` | drive_hud_localizer.dart:55 | WHOLE-SLOTLESS | **LOCAL/MEASURED** — same on-device caution ladder (ceiling rung) | **YES** — fires offline when position degrades to `lost` | **FLAG:** doctrinally soft (invitation, never command — by design). For a 70yo in real danger `停車も選べます` ("you may also choose to stop") may under-register as urgency. Intentional-softness vs comprehension-urgency tension — surface to Chair. |
| `no_data_conditions_unknown` | `路面状況を取得できていません。見える範囲で運転してください。` | snow_rendering/road_surface_announcement.dart:202 | WHOLE-SLOTLESS | **LOCAL/MEASURED** — fires precisely on ABSENCE of a feed (the dead-zone state itself) | **YES (recommended)** — but **CURRENTLY UNWIRED** in sngnav-app (see GAP-2) | The single most dead-zone-shaped line in the whole catalog. `取得できていません` is mildly technical (取得 = a systems verb); the actionable second half `見える範囲で運転してください` (drive within what you can see) is excellent and rescues it. |

**Count: 3 phrases in the offline manifest. 3 whole-slotless / 0 templated / 0 fragments.**

---

## SECTION 2 — FULL SPOKEN-PHRASE TABLE (every phrase that reaches, or is built to reach, TTS)

### Group A — Position-confidence caution (drive_hud_localizer, wired `drive_hud_controller.dart:189`)

| clip-id | ja text | src:line | shape | channel-origin | offline? | dignity |
|---|---|---|---|---|---|---|
| `caution_continue_none` | *(empty string — not spoken)* | drive_hud_localizer.dart:48 | — | LOCAL | NO — `continueDriving` returns `''`, info-class, never announced | n/a (correct: absence is not "safe") |
| `caution_heightened_core` | `速度を落とし、車間を広げて、前方に注意してください。` | :51 | WHOLE-SLOTLESS | LOCAL/MEASURED | **YES** (Section 1) | see Section 1 |
| `caution_consider_stopping_core` | `安全にできるときは、安全な場所での停車も選べます。` | :55 | WHOLE-SLOTLESS | LOCAL/MEASURED | **YES** (Section 1) | see Section 1 |

### Group B — Gated maneuver narration (drive_hud_localizer, wired `drive_hud_controller.dart:233` via `narrateNextManeuver`)

All **GPS-BOUND**: `maneuver_narration.dart:257-258` maps `deadReckoning`/`lost` → `suppressed`
→ announcer NOT fired. When GPS is dead, **none of these are ever spoken.** All MOOT offline.

| clip-id | ja text | src:line | shape | channel-origin | offline? | dignity |
|---|---|---|---|---|---|---|
| `mnv_depart` | `ルート案内を開始します。` | drive_hud_localizer.dart:173 | WHOLE-SLOTLESS | GPS-BOUND | NO — needs a live route; suppressed on lost GPS | fine |
| `mnv_arrive` | `まもなく目的地です。` | :175 | WHOLE-SLOTLESS | GPS-BOUND | NO — same | fine |
| `mnv_straight` | `このまま直進します。` | :177 | WHOLE-SLOTLESS | GPS-BOUND | NO — same | fine |
| `mnv_turn_template` | `この先、$noun です。` | :180 | TEMPLATED ($noun) | GPS-BOUND | NO — same | fragment-into-carrier prosody risk (see Summary) — moot offline |
| `mnv_hedged_arrive` | `現在地が不確かですが、まもなく目的地の付近です。位置をご確認ください。` | :191 | WHOLE-SLOTLESS | GPS-BOUND (suspect-GPS branch) | NO | long but the hedge is the point |
| `mnv_hedged_template` | `現在地が不確かです。この先 $noun の可能性がありますが、位置をご確認のうえご判断ください。` | :197 | TEMPLATED ($noun) | GPS-BOUND | NO | long |
| `mnv_icy_coupling_template` | `$maneuverText この曲がり角は路面が凍結している可能性があります。` | :208 | TEMPLATED ($maneuverText) | GPS-BOUND | NO — only couples onto a spoken/hedged maneuver | good hazard-first-then-detail if ever offline |
| `noun_left` | `左折` | :147 | FRAGMENT | GPS-BOUND | NO | — |
| `noun_slight_left` | `斜め左方向` | :148 | FRAGMENT | GPS-BOUND | NO | — |
| `noun_sharp_left` | `左への急カーブ` | :149 | FRAGMENT | GPS-BOUND | NO | — |
| `noun_right` | `右折` | :150 | FRAGMENT | GPS-BOUND | NO | — |
| `noun_slight_right` | `斜め右方向` | :151 | FRAGMENT | GPS-BOUND | NO | — |
| `noun_sharp_right` | `右への急カーブ` | :152 | FRAGMENT | GPS-BOUND | NO | — |
| `noun_straight` | `直進` | :153 | FRAGMENT | GPS-BOUND | NO | — |
| `noun_uturn` | `Uターン` | :154 | FRAGMENT | GPS-BOUND | NO | — |
| `noun_roundabout` | `ロータリー` | :158 | FRAGMENT | GPS-BOUND | NO | — |
| `noun_merge` | `合流` | :159 | FRAGMENT | GPS-BOUND | NO | — |
| `noun_ramp_left` | `左のランプ` | :160 | FRAGMENT | GPS-BOUND | NO | — |
| `noun_ramp_right` | `右のランプ` | :161 | FRAGMENT | GPS-BOUND | NO | — |
| `noun_default` | `次の案内` | :162 | FRAGMENT | GPS-BOUND | NO | — |

### Group C — Invisible black-ice announcement (snow_rendering, wired `main.dart:1118`)

| clip-id | ja text | src:line | shape | channel-origin | offline? | dignity |
|---|---|---|---|---|---|---|
| `surface_invisible_black_ice` | `ブラックアイスバーンに注意。路面は濡れて見えても、凍結しているおそれがあります。急ハンドル、急ブレーキは厳禁。速度を落としてください。` | snow_rendering/road_surface_announcement.dart:97-99 | WHOLE-SLOTLESS | **NETWORK-SOURCED** — trigger is a live JMA observation (`invisible_ice_watch.dart` reads temp/humidity/precip; fed at `main.dart:1070`) | NO — moot in pure dead-zone (**GAP-1**) | Leads with the term she KNOWS (ブラックアイスバーン) — right. Possibility-graded (おそれ) — right. But **4 clauses**: long for a single hearing, eyes on ice. Well-ordered though (name → looks-wet → prohibitions → action). |

### Group D — Turmoil (downpour/wind) announcement (turmoil_watch, wired `main.dart:1124-1128`)

| clip-id | ja text | src:line | shape | channel-origin | offline? | dignity |
|---|---|---|---|---|---|---|
| `turmoil_rain_wind` | `強い雨と強めの風を観測しています。視界の悪化と横風のおそれがあります。速度を落とし、車間距離をとって慎重に運転してください。` | turmoil_watch.dart:165-166 | WHOLE-SLOTLESS | **NETWORK-SOURCED** — live JMA observation (`main.dart:1071`) | NO — moot offline | very long (3 sentences); measured-verb `観測しています` is honest but formal |
| `turmoil_rain` | `強い雨を観測しています。視界の悪化や、水たまりによるスリップのおそれがあります。速度を落とし、車間距離をとってください。` | :173-174 | WHOLE-SLOTLESS | NETWORK-SOURCED | NO | long |
| `turmoil_wind` | `強めの風を観測しています。横風に流されるおそれがあります。ハンドルをしっかり握り、速度を落としてください。` | :180-181 | WHOLE-SLOTLESS | NETWORK-SOURCED | NO | clearest of the three; concrete action |

### Group E — Surface-state action (navigation_safety_core AlertExplainer, wired `main.dart:1283`), HER = `ageingRural` profile → `full` verbosity

Condition is derived from live weather → **NETWORK-SOURCED trigger**. The action *text* is a
local lookup table, but HER cannot know the road surface with no feed and no road sensor.

| clip-id | ja text | src:line | shape | channel-origin | offline? | dignity |
|---|---|---|---|---|---|---|
| `surface_unknown_aged` | `路面状況不明。慎重に運転してください` | alert_explainer.dart:189 | WHOLE-SLOTLESS | NETWORK-SOURCED (condition) | NO — but this is the offline-appropriate *shape* (overlaps `no_data_conditions_unknown`) | short, clear, good |
| `surface_dry_aged` | `乾燥路面、通常運転で問題ありません` | :196 | WHOLE-SLOTLESS | NETWORK-SOURCED | NO — non-hazard; not a warning | fine |
| `surface_wet_aged` | `路面が濡れています。ブラックアイスが形成される可能性があるため、橋やトンネル出口で速度を落としてください` | :201-202 | WHOLE-SLOTLESS | NETWORK-SOURCED | NO | long; good bridge/tunnel specificity |
| `surface_snow_aged` | `圧雪路面です。雪は固く凍結に近い状態です。低速ギアを保ち、急ブレーキ・急ハンドルを避けてください` | :218-219 | WHOLE-SLOTLESS | NETWORK-SOURCED | NO | long; explanatory clause delays the action |
| `surface_ice_aged` | `凍結路面です。気温0°C以下で薄氷ができています。時速30km以下に減速し、急ブレーキは避けてください` | :237-238 | WHOLE-SLOTLESS | NETWORK-SOURCED | NO | **FLAG:** `気温0°C以下で薄氷ができています` is explanatory detail *before* the action — for eyes-on-ice single-hearing, lead with the action. |
| `surface_slush_aged` | `シャーベット状の路面です。タイヤが横に滑る危険があるため、車線変更を避け、道路中央寄りを走行してください` | :254-255 | WHOLE-SLOTLESS | NETWORK-SOURCED | NO | long |
| `surface_wet_ice_aged` | `アイスバーンです。最も滑りやすい路面状態です。可能であれば停車できる安全な場所を探してください。走行中は時速20km以下を目安に` | :273-275 | WHOLE-SLOTLESS | NETWORK-SOURCED | NO | **FLAG:** 4 sentences — the longest safety-critical line for the most dangerous surface. Too long to act on by ear in one pass. |
| `surface_gravel_aged` | `砂利が浮いています。急ブレーキで滑る可能性があるため、十分な車間距離をとってください` | :295-296 | WHOLE-SLOTLESS | NETWORK-SOURCED | NO | long |

> **AAA cross-cutting flag (verbosity-profile inversion).** HER's `ageingRural` profile
> maps to `full` verbosity (`alert_explainer.dart:159-161`) — the LONGEST variant. `full`
> optimizes for comprehension-at-leisure; the eyes-on-ice, hear-once dead-zone context wants
> the SHORTEST actionable line. These pull opposite ways. The other 5 profiles' shorter
> variants (e.g. `brief` `凍結路面。30km/h以下に減速`) are not pre-rendered here (HER is
> ageingRural), but the go-live should decide whether HER's *emergency* delivery should
> borrow a shorter register than her *at-leisure* one.

### Group F — Catalog surface announcements, TTS-ready but **NOT wired in sngnav-app**

`snow_rendering` ships these as `jaSpokenText`, but no `.announcement` call exists on the
app's announce path (only `invisibleBlackIceAnnouncement` is referenced). Catalog-ready,
app-silent today.

| clip-id | ja text | src:line | shape | channel-origin | offline? | dignity |
|---|---|---|---|---|---|---|
| `cat_surface_wet` | `路面が濡れています。制動距離が伸びます。速度を控えてください。` | road_surface_announcement.dart:122 | WHOLE-SLOTLESS | NETWORK-SOURCED (condition) + UNWIRED | NO | concise, good |
| `cat_surface_slush` | `シャーベット状の路面です。下が凍結している可能性があります。油断せず、速度を落としてください。` | :129-131 | WHOLE-SLOTLESS | NETWORK-SOURCED + UNWIRED | NO | good |
| `cat_surface_compacted_snow` | `圧雪路面です。急のつく操作を避け、車間距離を多めにとってください。` | :141-142 | WHOLE-SLOTLESS | NETWORK-SOURCED + UNWIRED | NO | concise — better than the `ageingRural` snow line for eyes-off |
| `cat_surface_black_ice` | `ブラックアイスバーンに注意。路面が凍結しているおそれがあります。急ハンドル、急ブレーキは厳禁。速度を落としてください。` | :162-164 | WHOLE-SLOTLESS | NETWORK-SOURCED + UNWIRED | NO | provenance-neutral (no false "looks wet"); good |
| `cat_surface_standing_water` | `路面に水がたまっています。ハイドロプレーニングに注意し、速度を落としてください。` | :173-175 | WHOLE-SLOTLESS | NETWORK-SOURCED + UNWIRED | NO | `ハイドロプレーニング` is a loanword a 70yo may not parse — flag |

### Group G / H — Catalog absence + unmeasured-advisory announcements (snow_rendering, UNWIRED)

| clip-id | ja text | src:line | shape | channel-origin | offline? | dignity |
|---|---|---|---|---|---|---|
| `no_data_conditions_unknown` | `路面状況を取得できていません。見える範囲で運転してください。` | road_surface_announcement.dart:202 | WHOLE-SLOTLESS | **LOCAL/MEASURED** (fires on feed-absence) + UNWIRED | **YES** (Section 1) | see Section 1 |
| `road_advisory_unmeasured` | `この地域に道路に関する注意報が出ています。路面の実測データはありません。見える範囲で運転してください。` | :216-218 | WHOLE-SLOTLESS | **NETWORK-SOURCED** — needs a road-authority CAP advisory to be received + UNWIRED | NO — the advisory must arrive over network | honest two-part (something in force / nothing measured); `見える範囲で` action is good |

### Group I — voice_guidance `ManeuverSpeechFormatter` — catalog spoken formatter the app DELIBERATELY bypasses for HER

`maneuver_narration.dart:26-34` documents that HER is NOT routed through this formatter
(it returns the OSRM English `instruction` verbatim when present → a D4 breach), so the app
localizes via `DriveHudLocalizer` instead. These are catalog phrases, **off HER's app path**,
and GPS-bound regardless.

| clip-id | ja text | src:line | shape | channel-origin | offline? | dignity |
|---|---|---|---|---|---|---|
| `vg_mnv_left` | `左折です。` | maneuver_speech_formatter.dart:21 | WHOLE-SLOTLESS | GPS-BOUND + off-HER-path | NO | — |
| `vg_mnv_right` | `右折です。` | :22 | WHOLE-SLOTLESS | GPS-BOUND + off-HER-path | NO | — |
| `vg_mnv_arrive` | `目的地に到着します。` | :23 | WHOLE-SLOTLESS | GPS-BOUND + off-HER-path | NO | — |
| `vg_mnv_depart` | `出発します。` | :24 | WHOLE-SLOTLESS | GPS-BOUND + off-HER-path | NO | — |
| `vg_mnv_next` | `次の案内です。` | :25 | WHOLE-SLOTLESS | GPS-BOUND + off-HER-path | NO | — |
| `vg_arrived` | `目的地に到着しました。` | :44 | WHOLE-SLOTLESS | GPS-BOUND + off-HER-path | NO | — |
| `vg_arrived_named` | `$destinationLabel に到着しました。` | :46 | TEMPLATED ($destinationLabel) | GPS-BOUND + off-HER-path | NO | — |
| `vg_reroute` | `ルートを外れました。再検索します。` | :57 | WHOLE-SLOTLESS | GPS-BOUND + off-HER-path | NO | — |
| `vg_prefix_critical` | `危険。$trimmed` | :70 | TEMPLATED ($trimmed) | GPS-BOUND + off-HER-path | NO | — |
| `vg_prefix_warning` | `注意。$trimmed` | :71 | TEMPLATED ($trimmed) | GPS-BOUND + off-HER-path | NO | — |

---

## SECTION 3 — READ BUT NOT ON THE SPOKEN LANE (screen-only / display-verbatim / catalog-offered-unused)

Listed for completeness and honesty (OPS-062 — I read them; they are NOT spoken, so they take
no offline-audio row). None reaches `announce()`/`speak()`.

| family | where | why not spoken |
|---|---|---|
| Drive-HUD labels: `actionHeadline` (dhl:31,33,35), `modeLabel` (:66,68,70,72), `reasonLabel` (:81-95), `unknownLabel` (:105-115), `radiusLabel` (:122,125 — templated), `sightHintLabel` (:133 — templated) | drive_hud_localizer.dart | rendered as on-screen `_kv` rows (main.dart:899-965, 2324); announce path uses only `spokenGuidance` |
| `compound_failure_advisor` JA messages: `actionLabel`/`actionSentence`/`reasonSentence`/`unknownSentence`/`compoundingNote`/`sightStoppingSpeedHint` (drive_advice_messages.dart:201-303) | compound_failure_advisor | catalog-OFFERED defaults; the app renders its OWN `DriveHudLocalizer` strings, not these. Not wired to app screen or voice. |
| 15 JMA warning labels `大雪警報 … 濃霧注意報` (jma_advisory_mapper.dart:149-164); snow subset (:95-100); prefecture names (:286-291) | condition_aggregator_jma | shown verbatim on advisory cards (advisory_cards.dart:216); **NETWORK-SOURCED**. Their *severity* reaches voice only indirectly, as the generic `spokenGuidance` caution — the label itself is never spoken. |
| JMA offline-honesty line `…の気象警報を確認できませんでした（通信不可）。…` (jma_advisory_mapper.dart:595-596) + `データ取得不可` eventClass (:204) | condition_aggregator_jma | `buildIncompleteReadNotice` → advisory list → **screen** (advisory card), not the announcer. Dead-zone-appropriate in content, but not on the voice lane. |
| 7 JAF surface words + verbatim advice: `アイスバーン`/`ブラックアイスバーン`/`雪道`/`圧雪`/`シャーベット`/`凍結` + `safeDrivingResponseJa` (jaf_authoritative_data.dart:27,37-39,51,60-66,79,87-94,108,115-118,132,141-143,155,166-173) | japanese_snow_vocabulary | `safeDrivingResponseJa` is **display-verbatim** by contract ("relayed verbatim for display surfaces", road_surface_announcement.dart:15) — NOT a TTS line. The *terms* (`termJa`) are spoken only as the LEAD of the composed Group C/F lines, not on their own. |
| `turmoilRowText` (turmoil_watch.dart:134-148), watch-row strings `⚠ ブラックアイスバーンのおそれ…` / `荒天ウォッチ` (main.dart:1914-1944), `⚠ 危険が重なっています…` (main.dart:934), voice-lane UI strings (app_localizations.dart:161-249), station/place labels (jma_fetch.dart, akita_map.dart), log-share text (log_share.dart) | sngnav-app | on-screen status / UI chrome / share text — never announced. |

---

## SUMMARY

- **Total spoken / spoken-ready phrases found: 51.**
  - App spoken lane (reaches `announce()` today): **34** — Group A (2, minus the empty
    `continueDriving`), B (7 sentences/templates + 13 noun fragments = 20), C (1), D (3), E (8).
  - Catalog spoken-ready but UNWIRED in the app: **17** — Group F (5), G (1), H (1), I (10).
- **In the offline manifest (fires with NO network + NO GPS): 3.**
  `caution_heightened_core`, `caution_consider_stopping_core`, `no_data_conditions_unknown`.
- **Moot offline: 48** — GPS-bound (all Group B + I = 30; suppressed when the dot is lost) and
  network-triggered condition warnings (Groups C, D, E, F, H = 18).

**Recordable-shape breakdown of the 3 offline phrases:**
- **WHOLE-SLOTLESS (human-recordable core): 3.**
- **TEMPLATED: 0.**
- **FRAGMENTS: 0.**

**Prosody / whole-phrase-recording note.** Good news for HER comprehension: the entire offline
core is whole-slotless, so **record each as a single whole human-voiced phrase** — no
fragment-concatenation, no pitch-accent break. The ONLY fragment-into-carrier constructions in
the codebase (`この先、$noun です。` with nouns like `左への急カーブ`, drive_hud_localizer.dart:180 +
147-162) are ALL **GPS-bound and excluded** from the offline manifest, so the boundary-prosody
risk never touches the dead-zone contract. **Standing caution if that ever changes:** splicing a
separately-recorded `左への急カーブ` into `この先、___ です。` would break Japanese pitch-accent at
the seam and read as robotic — a life-critical turn warning must be recorded whole per maneuver
type, never concatenated. (Not a current dead-zone concern.)

**Load-bearing GAPS surfaced by measuring (for the go-live decision, not silently resolved):**

- **GAP-1 — the signature winter warnings cannot fire in a pure dead-zone.** Invisible black
  ice (Group C), turmoil (D), and all surface-state warnings (E, F) are triggered ONLY by a
  **live JMA observation** (`invisible_ice_watch.dart` + `turmoil_watch.dart`, fed at
  `main.dart:1070-1071`); on a fetch failure the app sets `unknown`/`null` (`main.dart:1073-1074`)
  and discards last-known. So on the one night the network dies in Akita, HER hears **no
  road-surface voice at all** — only the position-caution. If the go-live wants HER to hear
  "black ice" offline, it needs (a) a last-known-observation cache with an explicit staleness
  bound, and/or (b) an on-board temperature source — **and** the audio pre-rendered. This is a
  design decision above this manifest's pay grade; flagged for the Chair.
  **→ PARTIALLY CLOSED by W0 (commit `e2cd352`, 2026-07-12):** invisible black ice is now
  RETAINED + honestly time-stamped offline within a 60-min bound (Chair ruling: retain-slow /
  silent-fast). STILL OPEN: (i) a sustained 暴風-class gale is dropped silent (recorded KNOWN
  LIMITATION + pinned test; wind-retain fix deferred, needs AAA/NDI); (ii) surface-state library
  (Group E) remains a manual-dropdown + demo-button explorer, not the autonomous loop (GAP-3 →
  W0.1: confirm intent with SDE).
- **GAP-2 — the one perfect dead-zone line is not wired.** `no_data_conditions_unknown`
  (`路面状況を取得できていません。見える範囲で運転してください。`) is exactly the D3 compound-failure
  voice, is LOCAL (fires on absence), yet `snow_rendering`'s `conditionsUnknownAnnouncement` /
  `RecommendedResponseAnnouncement` extension has **no call site in sngnav-app**. It must be
  wired to the announcer AND pre-rendered for W1 to mean anything.
  **→ CLOSED by W0 (commit `e2cd352`, 2026-07-12):** the absence-line is now wired to the
  announcer at `warning` severity (fires on true no-reading — no cache / unparseable / past the
  60-min bound). App-local verbatim mirror `kConditionsUnknownJaSpokenText` used because the
  resolved `snow_rendering 0.2.7` does not yet export the symbol (core ^0.10 cap); replace with
  the catalog import on republish. Pre-render (audio) still pending the W2 audio lane.
- **GAP-3 (AAA) — verbosity-profile inversion.** HER's `ageingRural` → `full` (longest)
  verbosity is optimized for the wrong context; the emergency, eyes-on-ice, hear-once delivery
  wants the shortest actionable line. Worst case: `surface_wet_ice_aged` (4 sentences).
- **Separate axis — offline TTS voice.** "In the offline manifest" above is decided on the
  MISSION RULE (does the *trigger* fire offline). There is a SECOND reason a phrase may need a
  bundled clip: if the device's Japanese TTS voice is not installed, `flutter_tts` may not speak
  offline AT ALL, even for a warning triggered while still online moments before blackout (e.g.
  black ice). Whether to pre-render the network-triggered winter warnings for the *TTS-absent*
  case is a distinct decision from trigger-availability — named here, not resolved.

**Could NOT classify with full confidence (named, not guessed):**
- **`Group E` (AlertExplainer.action) real-drive trigger.** Confirmed it is on an `announce()`
  path (`_announceCurrentAlert`, main.dart:1275-1286). I could NOT confirm from the read whether
  that path runs autonomously in the drive loop or only via a driver-tapped "Announce to driver"
  action (app_localizations.dart:161). I classified it as **spoken + NETWORK-SOURCED (condition)**;
  if it is demo-button-only, it is not on HER's autonomous voice lane at all. Flagged for
  verification, not asserted.
