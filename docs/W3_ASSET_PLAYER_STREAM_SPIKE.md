# W3 Scoping Spike — Bundled Japanese Safety-Audio Lane (player / stream / latency / size)

> **SPIKE only.** Investigate + recommend + cite. No pubspec edit, no code, no commit.
> Authors: AAE (Android app + platform) + FDD (catalog/Dart). Date: 2026-07-12.
> Discipline: OPS-062 (cite version/API for every capability; do not invent a plugin API),
> OPS-066 (anything device-observable is a **device-deferred hypothesis**, not a fact — no device here).

## The ask (restated)

A second, **separate** voice lane: play **pre-rendered, APK-bundled Japanese safety-warning
clips** (short OGG/WAV) with **zero** dependency on the phone's TTS engine or network, on a
70-yo rural-Akita driver's **old low-end Android** phone, **in a dead-zone**, loud enough over
road noise **even if media volume is low or muted**. The existing `flutter_tts ^4.2.5` system-TTS
lane **stays** for open/dynamic text; this bundled-clip lane is additive.

---

## MEASURE FIRST — real state read this turn

| Fact | Evidence (file:line) |
|---|---|
| **No audio-player plugin exists today.** Only `flutter_tts: ^4.2.5` (TTS), `vibration: ^3.2.0` (haptic), `wakelock_plus`. No `just_audio` / `audioplayers` / SoundPool wrapper. | `sngnav-app/pubspec.yaml:13-85` (full dep list read; confirmed absent) |
| **No bundled audio assets today.** Only asset declared is the offline basemap. No `assets/audio/`. | `pubspec.yaml:97-105`; `find assets/` → `assets/tiles/akita_offline.mbtiles` only |
| **A first-party Kotlin MethodChannel already exists in-tree** — `sngnav/audio_readiness`, method `read` → `{mediaVolume, mediaVolumeMax, ttsServiceVisible}`, READ-ONLY, registered in `configureFlutterEngine`. This is the pattern a clip-player would extend. | `MainActivity.kt:27-59` (channel at :30-33; `AudioManager` read at :38-51) |
| **USAGE_ALARM is ALREADY named, in-tree, as a Chair Tier-3 dignity question** — "A volume-raising actuator (USAGE_ALARM critical alert) is Tier-3 — post-beta, evidence-gated, and a dignity question for the Chair, never an engineering default." | `MainActivity.kt:22-26` (verbatim) |
| **The TTS lane already sets `USAGE_ASSISTANCE_NAVIGATION_GUIDANCE + CONTENT_TYPE_SPEECH`** and requests `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK`. So nav-guidance routing is the *incumbent* behaviour; this new lane must do **better than** nav-guidance on audibility-when-muted. | `hardened_tts_engine.dart:57-60` (cites `FlutterTtsPlugin.kt:785-793`, verified against the local clone per `hardened_tts_engine.dart:4-6`), focus at `:264-267` |
| **The announcer is the integration seam** — `AlertAnnouncer.announce()` fires haptic-first (unconditional) then audio-second (guarded), gated `severity >= warning`. The bundled-clip lane slots in behind `actuators.speak(...)` (or beside it) without touching the OPS-059 haptic floor. | `alert_announcer.dart:48-70` (gate :53; haptic :57-58; audio :64-65) |
| **Manifest has NO audio permission today** (INTERNET, FINE/COARSE_LOCATION, WAKE_LOCK only). Plain playback needs none; a real **DND override** would need runtime Notification-Policy special access (not a manifest line). | `AndroidManifest.xml:5-13` |
| **APK-size yardstick:** the app already ships a ~10.1 MB offline `.mbtiles` asset. Audio at a few MB is the same order of magnitude → not a blocker. | `pubspec.yaml:98-105`; MEMORY offline-basemap (965 tiles / 10.1 MB) |
| **minSdk/targetSdk defer to the Flutter SDK** (`flutter.minSdkVersion` / `flutter.targetSdkVersion`), not pinned in-repo. Exact numbers not offline-verifiable here — **flag**. | `android/app/build.gradle.kts:41-42` |

**Honest offline limit:** there is **no local clone and no pub-cache** for `just_audio` / `audioplayers`
/ `audio_session` on this box (checked). Every claim below about *those plugins'* API surface is
**from memory, NOT offline-verified** and is marked `[memory — verify]`. The `flutter_tts`
Kotlin-side facts ARE verified (local clone, cited above). SoundPool/MediaPlayer/AudioAttributes
facts are stable Android-framework APIs but their **runtime audibility behaviour on HER device is
device-deferred** (OPS-066).

---

## Q1 — Player: `just_audio` vs `audioplayers` vs first-party Kotlin SoundPool

| Criterion | `just_audio` (+`audio_session`) | `audioplayers` | **First-party Kotlin SoundPool channel** |
|---|---|---|---|
| Offline from APK assets | Yes (asset source) | Yes (`AssetSource`) | Yes (`AssetFileDescriptor` via `context.assets.openFd`) |
| Control of Android **USAGE / stream** | Session-level `AndroidAudioAttributes(usage,contentType,flags)` via `audio_session` `[memory — verify]`; per-clip granularity limited | `AudioContextAndroid(usageType, audioFocus, contentType)` `[memory — verify]`; enum may not expose every USAGE | **Full, exact** — `AudioAttributes.Builder().setUsage(USAGE_*).setContentType(CONTENT_TYPE_*)` passed to `SoundPool.Builder().setAudioAttributes(...)`. No abstraction between us and the framework. |
| Pre-warm / low latency for **short** clips | ExoPlayer/Media3 engine — heavier; can pre-load a source but first-play latency higher | Similar (ExoPlayer/MediaPlayer backends) | **Best** — `SoundPool.load()` decodes to PCM **in memory once**; `play()` at hazard moment is near-instant. Purpose-built for short cues. |
| Old low-end ARM footprint | Heaviest (ExoPlayer classes/memory) | Medium | **Lightest** for many short clips |
| New pub dependency (resolver risk) | +1 (and `audio_session`) into an **already-capped** graph | +1 | **Zero** — no pub add; matches §12 anti-proliferation |
| Matches in-tree pattern | No | No | **Yes** — extends `MainActivity.kt` `configureFlutterEngine` exactly like `sngnav/audio_readiness` |

**Decisive factors, grounded in measured state:**
1. **Stream control is the whole point of this lane** (requirement b: reach a loud/alarm-priority
   stream that survives media-mute). Only the first-party path gives *unambiguous, exact* AudioAttributes;
   the plugins interpose an enum I cannot offline-verify covers `USAGE_ALARM` / `USAGE_ASSISTANCE_ACCESSIBILITY`.
2. **Resolver cost is real, not theoretical.** `pubspec.yaml:16-22` documents the app is *already*
   frozen out of `core ^0.11.x` by a caret-cap wave; adding another plugin (+ its transitive `audio_session`)
   into that graph is avoidable risk. The Kotlin channel adds **zero** pub deps.
3. **It matches an already-Chair-ratified pattern** (`MainActivity.kt:11-12`, Tier-2 probe). We extend a
   proven first-party surface rather than introduce a new engine.

### Q1 recommendation → **Extend the existing first-party Kotlin MethodChannel with a SoundPool player.**
Add a sibling method (e.g. `sngnav/safety_audio` → `preload` / `play(clipId)` / `release`) in
`MainActivity.kt`, backed by a `SoundPool` built with an explicit `AudioAttributes`. Dart calls it
behind the existing `TtsEngine`/announcer seam (`alert_announcer.dart:64-65`). No pubspec change for
the player itself (asset **declaration** still needs a `pubspec.yaml` `assets:` entry when clips land —
a later, non-spike change).

*Fallback if the team wants cross-platform/iOS parity later:* `just_audio` + `audio_session` for the
non-Android platforms only, with the Kotlin SoundPool remaining the Android safety path. Not needed for
the Akita-beta (Android-only) target.

---

## Q2 — Stream routing: USAGE_ALARM vs USAGE_ASSISTANCE_NAVIGATION_GUIDANCE vs USAGE_ASSISTANCE_ACCESSIBILITY

Framework behaviour (stable Android API knowledge; **runtime mute/DND outcome on HER device is OPS-066 device-deferred**):

| Usage | Volume stream it rides | Audible when **media** low/muted? | Register / feel | DND |
|---|---|---|---|---|
| `USAGE_ASSISTANCE_NAVIGATION_GUIDANCE` (incumbent TTS lane) | media-class (`STREAM_MUSIC`-like) | **No** — dies with media volume | "nav voice", not jarring | follows media |
| `USAGE_ASSISTANCE_ACCESSIBILITY` | accessibility path (version-dependent; a11y stream on newer APIs, else media) `[verify on device]` | **Partially** — better odds than nav-guidance, **not guaranteed** | semantically = *accessibility safety warning* (matches our OPS-059 floor, `alert_announcer.dart:1-14`) | device-dependent |
| `USAGE_ALARM` | **separate alarm stream** (`STREAM_ALARM`) | **Yes, best odds** — alarm volume is independent of media | alarm-clock register — **loud/jarring**, always-on-loud | alarms are exempt under common DND presets **by default**, but **user-configurable, NOT guaranteed** |

**Do NOT overclaim:** USAGE_ALARM does **not** *force* audibility. It rides the alarm stream (so it
survives a muted **media** stream — the strongest reason to consider it), and alarms are *typically*
allowed through DND **by default** — but the user can silence the alarm stream, and OEM/DND configs vary.
A hard, programmatic DND override needs runtime Notification-Policy access we do not hold
(`AndroidManifest.xml:5-13` — no such grant). **All of this is device-verifiable only (OPS-066), in the
Akita device hour.**

### Q2 recommendation → **Default `USAGE_ASSISTANCE_ACCESSIBILITY`; reserve `USAGE_ALARM` as a Chair-gated escalation for the compound-failure worst case.**
- `USAGE_ASSISTANCE_ACCESSIBILITY` is the **honest** default: this lane literally *is* an accessibility
  safety warning (OPS-059 floor, `alert_announcer.dart:1-14`), it routes better than the incumbent
  nav-guidance for the muted-media case, and it does **not** hijack the alarm register.
- `USAGE_ALARM` is the **only** usage that reliably rides a stream independent of media volume — i.e. the
  one most likely to reach HER when her media is muted. But choosing it is **exactly the Tier-3 dignity
  decision the code already names for the Chair** (`MainActivity.kt:22-26`). It should be an
  **evidence-gated, Chair-ratified escalation** for the D3 worst case (Maps+GPS+disorientation, dead-zone),
  **not** the engineering default — reserving it prevents cry-wolf and register-abuse.

### 🚩 DIGNITY FLAG (safety ⇄ dignity tradeoff — surface to Chair)
The louder we route, the more we override HER own volume/DND choices. `USAGE_ALARM` maximises
"she hears it" and simultaneously maximises "we overrode her phone." This is the **same Tier-3
boundary `MainActivity.kt:22-26` deliberately withheld** (the probe is READ-ONLY by design — it *tells*
her the lane is silent, it does not *seize* her volume). Escalating from ACCESSIBILITY→ALARM for the
worst case is defensible **only** with (a) the driving-context gate (only while actually driving a
surfaced ≥warning hazard), (b) cry-wolf suppression (sub-zero/near-freezing pinning already a live
concern per MEMORY), and (c) a Chair ruling. **This spike does not decide it — it flags it.**

---

## Q3 — Latency / pre-warm

**Approach (SoundPool):**
1. **Pre-load at drive-start**, not at hazard time: `SoundPool.load()` each clip once; it decodes to PCM
   in memory and fires `OnLoadCompleteListener` — **gate the lane "ready" on load-complete** (a `play()`
   before load-complete no-ops silently). Keep the `SoundPool` instance alive for the whole drive session;
   `release()` on drive-end.
2. **Warm the audio HAL** with one near-silent priming `play()` at drive-start: the very first sound after
   a silent audio path can eat ~100–300 ms of cold-start on old hardware — priming moves that cost off the
   hazard moment. *(Latency figure is a device-deferred hypothesis, OPS-066.)*
3. At the hazard moment, `play(clipId)` on the already-decoded sample → near-instant, no decode, no I/O.

**Old-low-end concern (real, cite-worthy):** SoundPool holds **decoded PCM in memory**, and it has a
historical **per-sample size ceiling (~1 MB decoded, recall — verify on target)**. The constraint is
therefore **decoded RAM**, not file size. Mitigation: keep clips **short + mono** (below), and if the full
50–80-clip decoded set is too large for a low-end device, **pre-decode only the safety-critical working set**
(the ≥warning clips that must be instant) and lazy-load the long tail — or fall back to `MediaPlayer`
(prepared-and-parked) for the rare long clip, accepting its higher first-play latency for non-instant cues.

---

## Q4 — Asset size budget

**Stated assumptions:** mono; speech content; ~50–80 clips + short fragments; avg **~3 s** (safety warnings
are terse), worst-case ~5 s.

| Codec (on-disk) | Per 3 s clip | 80 clips | Note |
|---|---|---|---|
| **OGG/Vorbis mono ~64 kbps** | ~24 KB | **~1.9 MB** | Recommended on-disk format; even at 5 s avg → ~3.2 MB |
| WAV/PCM16 mono 22.05 kHz | ~132 KB | ~10.6 MB | Zero decode cost, but large; only if a clip needs SoundPool with no decode |

**On-disk verdict: SANE.** ~2–3 MB of OGG is trivially within budget — the app already ships a **~10.1 MB**
`.mbtiles` asset (`pubspec.yaml:98-105`), so audio is ~20–30 % of an existing single asset. Not a blocker.

**The real budget is decoded RAM, not APK size.** SoundPool decodes OGG→PCM in memory; 80 × ~3 s mono
22 kHz PCM16 ≈ **~10.6 MB RAM** if *all* held decoded — heavy for an old low-end device. So: ship **small OGG**
(APK stays tiny) but **cap the simultaneously-decoded working set** (Q3). Ship OGG for size; the SoundPool
in-RAM footprint is the number to watch on the target, not the download size.

---

## RECOMMENDATION (composite)

- **Player:** **Extend the existing first-party Kotlin MethodChannel (`MainActivity.kt`) with a `SoundPool`
  player** built on an explicit `AudioAttributes`. Reasons: exact stream/USAGE control (the point of the
  lane), **zero** new pub dependency into an already caret-capped resolver (`pubspec.yaml:16-22`), lightest
  on old ARM for many short cues, and it reuses a Chair-ratified in-tree pattern (`MainActivity.kt:11-12`).
  *(Cross-platform later → `just_audio`+`audio_session` for non-Android only; not needed for the Android beta.)*
- **Stream:** **Default `USAGE_ASSISTANCE_ACCESSIBILITY`** (honest = it *is* an OPS-059 accessibility safety
  warning; better-than-nav-guidance audibility; no register-hijack). **Reserve `USAGE_ALARM`** as a
  **Chair-gated, evidence-gated Tier-3 escalation** for the compound-failure worst case — the exact dignity
  boundary `MainActivity.kt:22-26` already reserves for the Chair.
- **Latency:** **Pre-load all (or the safety-critical working set of) clips at drive-start**, gate "ready" on
  `OnLoadCompleteListener`, keep the `SoundPool` alive for the session, **prime the audio HAL** with one
  silent `play()`; `play()` at the hazard moment on the already-decoded sample.
- **Size:** **Ship OGG/Vorbis mono ~64 kbps → ~2–3 MB on disk (sane; ~20–30 % of the existing 10 MB tile
  asset).** Watch **decoded RAM**, not APK size, on the low-end target.

## Honest device-deferred caveats (OPS-066 — resolve only in the Akita device hour)
- Whether `USAGE_ALARM` / `USAGE_ASSISTANCE_ACCESSIBILITY` **actually** plays over media-mute / through
  DND on HER specific old phone — **not confirmable here; device-verifiable only.** No DND *guarantee* is claimed.
- Actual **first-play / cold-start latency** on the low-end target (the ~100–300 ms figure is a hypothesis).
- SoundPool's **per-sample decoded-size ceiling** on the target API (historical ~1 MB — recall, verify).
- Whether the full 50–80-clip decoded set fits low-end RAM, or a working-set cap is required.
- `just_audio` / `audioplayers` / `audio_session` exact API surface — **memory-not-verified offline**
  (no clone, no pub-cache on this box); do not treat their capability rows as confirmed.
- Flutter default `minSdk` / `targetSdk` numbers (`build.gradle.kts:41-42` defers to the SDK) — not read here.

---
*Scope note: this document recommends; it does not modify `pubspec.yaml`, add assets, or write Kotlin/Dart.
Implementation (channel method + asset declaration + clip production) is a later, separately-ratified change.*
