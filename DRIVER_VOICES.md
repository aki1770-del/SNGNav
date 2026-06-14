# DRIVER_VOICES.md

A listening log for the SNGNav project. Records — anonymized, with source URL — public statements from drivers / app developers serving drivers / domain practitioners that inform what SNGNav builds.

## Why this file exists

The 2026-04-27 target-drivers research synthesis (`UNTITLED/outputs/research/target_drivers_2026_04_27_vaa_synthesis.md` in the development workspace) surfaced one largest-leverage gap: **the unit doesn't actually KNOW drivers; it knows what's published about them.** Three research perspectives (strategic, ADAS, ecosystem) named the gap independently.

This file closes that gap from the LISTENING side. It does not close it by extracting attention from drivers (asking them to share their experiences) — that would be the same V96-violation that today's session ratified rescinding for cold-tooling outreach. Instead, this file records what drivers + their developers ALREADY say in public, so when the unit makes a build decision, the decision is informed by their actual voices rather than only by inferred-from-statistics personas.

## What gets recorded here

Public statements only. Specifically:
- GitHub issues + PRs on Flutter / navigation / driving / weather / mapping / safety repositories
- Public blog posts
- Conference talks (with public recording or transcript)
- Documentation we read in the course of building
- Public chat-channel statements (where the channel itself is public-archive)
- Published papers / industry reports (with proper citation)

Not recorded:
- Private DMs or emails
- Solicited interviews (we don't solicit)
- Anonymous surveys (we don't conduct)
- Reconstructed-from-memory paraphrases (Verify-First: only what we can cite)

## Format per entry

```markdown
### [YYYY-MM-DD] Brief topic-line

**Source**: <URL>
**Speaker context** (anonymized): <e.g., "Flutter package maintainer in Sapporo region", "snow-zone municipal road-safety researcher", "ageing-driver advocacy group spokesperson">
**Substance** (≤200 words, paraphrased or quoted with attribution):
> ...

**V92 question**: which loom in SNGNav's portfolio (or potential portfolio) is made-absent by this voice? If the absence-of-loom would have caused this voice's experience, the loom is queued for build.

**VAA disposition**: build queue addition / informs existing build / no action / hold for cluster
```

## Listening surfaces — where to look

These are the public places where drivers / developers / domain practitioners speak about navigation + driving + safety + snow-zone realities. We watch passively; we do not post to provoke voices.

- GitHub issues on `flutter_map` and its plugins (`flutter_map_tile_caching`, `flutter_map_pmtiles`, etc.)
- GitHub issues on routing engines (`osrm`, `valhalla`)
- GitHub issues on `flutter_tts`, `flutter_background_geolocation`, `geolocator`
- GitHub issues on Japan-specific nav-related repos (search: `language:dart geo OR navigation OR routing`)
- Flutter community discussions on Discord public channels + r/FlutterDev
- Japan Flutter community gatherings (public meeting notes if available)
- Snow-zone municipal road-safety research published by Hokkaido / Tohoku universities
- JAMA / MLIT public publications on driver behavior + ADAS
- Toyota / Subaru / Honda public engineer blog posts on smartphone-nav HMI

## Cadence

No required cadence. Voices are recorded when encountered in the course of normal work. The watching is opportunistic; the recording is disciplined when the watch surfaces something.

## Cross-references

- Listening discipline doctrine: VAA prompt Listen Frame at `skills/vision-alignment-auditor/prompt.md` (in the masterplan workspace)
- Source synthesis: `UNTITLED/outputs/research/target_drivers_2026_04_27_vaa_synthesis.md`
- Build queue (where loom-additions land): WOW v1 master at `UNTITLED/outputs/governance_transformation/spa_actuator_way_of_working_v1.md`

---

## Recorded voices

### [2024-12] Sapporo driver — whiteout turn-around between Sapporo and Shinshinotsu

**Source**: https://domingo.ne.jp/en/article/44478
**Speaker context** (anonymized): Sapporo-region driver who recorded a whiteout encounter while driving from Sapporo toward Shinshinotsu Village; video viewed ≈200,000 times on social media.
**Substance** (paraphrased + one short attributed quote):
> "I was heading to Shinshinotsu this afternoon, but it looked like I wouldn't be able to get back, so I turned around. There was a car that had gone off the shoulder, and the car in front of me was about to do the same."

A separate user-comment thread on the same article surfaced an anonymized observation often repeated in snow-zone communities: "You don't understand the terror of a whiteout until you experience it."

**Structural takeaway**: This voice represents a snow-zone-experienced driver (local to Sapporo) making a real-time turn-around decision under whiteout, encoding driver-class state {visibility=whiteout, social-cue=preceding-car-failed} together. The decision is not "drive more carefully" but "abandon the trip." Substrate that informs whiteout-tier responses must support trip-abandonment as a first-class response, not only speed reduction.

---

### [2024-2025] Hokkaido rental-car operator — three foreign-tourist TOMARE collisions in one season

**Source**: https://www.explorelifehub.com/en/hokkaido-winter-driving-guide/
**Speaker context** (anonymized): Hokkaido rental-car company operator reporting three separate tourist accidents at TOMARE intersections in a single winter season; all three vehicles totalled, all occupants survived.
**Substance** (paraphrased from operator-reported account):
> "Last winter, rental companies reported three separate tourist accidents at TOMARE intersections, with all three cars being totalled, though fortunately everyone was okay."

The same source records that drivers without winter driving experience are explicitly advised to not begin self-driving in Hokkaido at all.

**Structural takeaway**: Foreign-tourist-snow-zone driver-class encounters concrete failure at the stop-sign primitive — the most basic hazard-perception action — because winter friction makes a simple TOMARE non-trivial. The mismapping risk this voice illustrates: a driver who would manage stop signs perfectly in dry conditions can total a rental car at the same sign on packed snow, with no warning that the failure mode has shifted from "missed sign" to "complete-stop-impossible-with-this-friction." Substrate that maps this driver class to anything other than a dedicated foreign-tourist-snow-zone profile under-serves them.

---

### [2024-12] Foreign-visitor self-driver — first-snow vehicle-response surprise

**Source**: https://www.powderlife.com/blog/driving-surviving-hokkaido-winters/
**Speaker context** (anonymized): Niseko / Hokkaido travel-blog instructional voice addressing first-time snow drivers from non-snow-country backgrounds.
**Substance** (verbatim short quotes from the published guide):
> "If you've never driven in snow before, prepare for a challenge."
> "When you brake or turn you should expect your car will may not be as responsive as if it were driving on clear pavement."
> "If you can't see the next arrow, congratulations: you're in a real whiteout!"

**Structural takeaway**: This voice (an instructional channel addressing the foreign-visitor cohort directly) names two cognitive-handover failures: (1) brake/steering response feels mechanically wrong in snow when the home-country baseline is dry pavement; (2) the visibility regime change to whiteout is identified by negative-evidence (cannot see next reflector arrow) rather than by a positive perceptual cue. Substrate that warns "reduced visibility" without telling the driver what to look for falls short of what a first-time snow driver actually needs.

---

### [2023] JAF Mate driving-instructor first-person account — frozen-rut control loss

**Source**: https://jafmate.jp/safety/drive_nearmiss_20230209.html
**Speaker context** (anonymized): JAF-affiliated driving-safety author recording a personal near-miss on a frozen-rut (轍) road in Japan; published as part of JAF Mate's near-miss editorial series.
**Substance** (verbatim Japanese with English gloss):
> 「ハンドルが利かない。さほどスピードは出ていないのだが、いったん滑り出してしまうと、ABSや横滑り防止装置（ESC）も万能ではなく、コントロールが難しい。」
>
> "The steering wasn't working. I wasn't going very fast, but once the slide started, even ABS and ESC aren't all-powerful — control becomes difficult."

**Structural takeaway**: A documented snow-zone-experienced driver (a JAF-affiliated safety editorialist, not a novice) reports that on a frozen-rut surface, the assistive-system layer (ABS, ESC) does not save the situation. The driver-class state is not "novice fails" — it is "experienced driver, modern car, still loses control on a specific surface micro-feature." Substrate that treats snow-zone-experienced as automatically self-managing under-serves the case where the surface itself defeats the assistive layer. Frozen-rut conditions warrant explicit advisory regardless of driver experience.

---

### [Public guidance, ongoing] JAF — official whiteout response for the general driving public

**Source**: https://english.jaf.or.jp/safe-driving/disaster/snow-covered-and-icy-roads
**Speaker context** (anonymized): Japan Automobile Federation, official safe-driving guidance for snow-covered and icy roads.
**Substance** (verbatim from JAF's published English guidance):
> "It is extremely dangerous to drive on snowy roads with regular tires, so make sure to use snow tires or chains."
> "If you're in a whiteout such as a snowstorm, turn on your hazard lamps and stop at a safe place."
> "Abrupt actions with 'sudden' elements, such as rapid acceleration, sudden stops, and sharp turns, are strictly prohibited."
> "In addition to using your eyes to maneuver on snowy roads, it is especially important to make predictions."

**Structural takeaway**: The official-body voice is explicit that whiteout response is "stop at a safe place" — not "slow down and continue." The advisory hierarchy that JAF expresses is: equipment first (snow tires), then prediction (anticipatory maneuvers), then in-condition response (no abrupt inputs), then whiteout-specific halt. Substrate that compresses these into a single "drive carefully" warning loses the structure JAF treats as load-bearing. Per-condition advisory text grounded in this hierarchy serves drivers more honestly than a single severity-tier collapse.

---

### [Public guidance, ongoing] MLIT / Hokkaido Prefecture — multilingual winter-road advisory for visitors

**Source**: https://hokkaido-safe-travel.mlit.go.jp/images/pdf/winter_drive_eng.pdf (Hokkaido Safe Travel project, MLIT-affiliated multilingual advisory PDF) and https://english.jaf.or.jp/driving-in-japan/driving-tips
**Speaker context** (anonymized): Japanese Ministry of Land, Infrastructure, Transport and Tourism (MLIT) multilingual winter-driving guidance, distributed in English and other languages for foreign visitors driving in Hokkaido and adjacent snow regions.
**Substance**: The MLIT-affiliated Hokkaido Safe Travel project publishes an English-language winter-drive PDF specifically for visitors; JAF's English-language driving-tips page covers parallel guidance. The structural fact recorded by the existence of these resources is that the official position treats foreign visitors driving in snow regions as a distinct class warranting dedicated multilingual advisory, not as a marginal subset of the general driving public.

**Structural takeaway**: When the relevant ministry and the national auto federation both publish dedicated foreign-visitor winter-driving material, the foreign-tourist-snow-zone driver class is officially recognized as a distinct cohort with distinct guidance needs. Any substrate that treats foreign visitors as a fallback case under existing profiles is at variance with the way Japanese road-safety institutions themselves treat the cohort.

---

### [Public corpus] AAA Foundation — cognitive distraction across the general driver population

**Source**: https://aaafoundation.org/wp-content/uploads/2018/01/CognitiveDistractionReport.pdf
**Speaker context** (anonymized): AAA Foundation for Traffic Safety, ongoing cognitive-distraction research program (Strayer et al.); published reports synthesize a multi-year measurement program on cognitive load in real-vehicle driving.
**Substance** (paraphrased structural finding):
> Cognitive load from in-vehicle conversation, hands-free phone use, and complex voice-command interactions produces measurable response-time degradation and a roughly two-fold increase in failure-to-detect events for sudden-onset stimuli, with P300 ERP amplitude reduced by approximately 50% during hands-free conversation.

**Structural takeaway**: Distraction is not only the externally-visible cases (texting, manual phone). Cognitive distraction from voice interaction (including from in-vehicle voice-command systems) measurably degrades hazard response. Substrate that adds voice-guidance verbosity for "engagement" without accounting for the cognitive-load cost is in tension with this body of evidence. The verbosity-by-profile design must continue to lean toward parsimony, not toward more talking.

---

### [Public guidance, ongoing] JAF — pre-trip preparation as the load-bearing safety surface

**Source**: https://english.jaf.or.jp/safe-driving/disaster/snow-covered-and-icy-roads + https://english.jaf.or.jp/driving-in-japan/driving-tips
**Speaker context** (anonymized): Japan Automobile Federation, snow-driving guidance section; pre-trip planning emphasis.
**Substance** (paraphrased structural emphasis):
> JAF's snow-driving guidance places the load-bearing weight on pre-trip preparation: gathering snow-condition information several days before departure (with an explicit JARTIC reference for road conditions), carrying snow chains and a jack even when snow tires are fitted, carrying booster cables, and preparing for whiteout / stranding contingencies before leaving.

**Structural takeaway**: The official-body emphasis is that the most consequential safety surface is pre-trip — not in-trip. Substrate that fires advisory only at the moment of detected hazard misses the upstream surface where JAF puts the most weight. The pre-trip planning surface (route + condition + equipment review before departure) is a first-class component class that this voice argues should exist alongside in-trip alerts.

---

### [Public corpus] Deaf / hard-of-hearing driver — the hazard warning that arrives as sound only

**Source**:
- https://hearinglosshelp.com/blog/driving-safely-with-hearing-loss/ (Neil Bauman, Ph.D., "Driving Safely with Hearing Loss"; first-person account, first published in *Hearing Health*, Spring 2009)
- https://nafath.mada.org.qa/nafath-article/mcn2904/ (Ahmed Zayen & Daniel Groessing, "SafeDrive4Deaf: A Mixed-Methods Study on Emergency Sound Awareness and Assistive Technology Needs Among Deaf and Hard-of-Hearing Drivers," *Nafath* periodical by Mada)
- https://www.frontiersin.org/journals/ict/articles/10.3389/fict.2018.00005/full (Yoren Gaffary & Anatole Lécuyer, "The Use of Haptic and Tactile Information in the Car to Improve Driving Safety: A Review of Current Technologies," 2018)
**Speaker context** (anonymized): A deaf hearing-health author writing first-person about driving entirely by vision; a mixed-methods study of 25 deaf and hard-of-hearing drivers (Tunisia + Germany; ages 25–61; 5–40 years' driving experience); and a peer-reviewed review of in-vehicle haptic/tactile alerting.
**Substance** (paraphrased + verbatim attributed quotes):
> A deaf driver describes navigating entirely by sight: *"I use my eyes when I drive. What do you use?"* and *"It is the rare emergency vehicle that can get close to me without my seeing its flashing lights."* (Bauman, 2009).

This is not anecdotal. In the SafeDrive4Deaf study of 25 deaf and hard-of-hearing drivers, **100% reported difficulty detecting approaching emergency vehicles regardless of 5–40 years' experience, and 100% expressed a need for enhanced alert systems.** Thematic analysis found participants valued *tactile feedback integrated into seats or steering wheels* and *color-coded* urgency (red = immediate threat; yellow = distant siren). A review of in-car haptics (Gaffary & Lécuyer, 2018) reports the tactile channel stays available when visual and auditory channels are overloaded, that haptic cues localize risk far better than sound (one study: spatial localization 32% → 84%), and that **dynamic, patterned vibration — not a single static buzz — differentiates urgency and shortens reaction time.**

*Need-grounded composite (labeled — not a real named testimony):* a deaf driver, or any driver inside a roaring-wind whiteout where speech cannot carry, receives nothing from an audio-only hazard warning.

**Structural takeaway**: The audio channel is not a universal channel. A deaf or hard-of-hearing driver receives nothing from an audio-only alert; neither does a hearing driver in a roaring-wind whiteout. Therefore the haptic (tactile) hazard channel SNGNav builds must carry the **same warning set** as the audio channel, fired off the **same severity gate** — not a reduced subset that silently drops the most serious warnings for the driver who can least afford to miss them (a D4 dignity floor; OPS-RULE-059 accessibility). A single undifferentiated buzz is worse than honest: a deaf driver who feels one generic vibration cannot act on it — they cannot tell *reduce speed* from *consider turning back*. The cited evidence shows differentiated cues are both wanted (SafeDrive4Deaf color-coding) and effective (Gaffary & Lécuyer: dynamic patterns beat a static buzz). So the haptic grammar must distinguish severity, mapping one-for-one onto the existing `RecommendedResponse` tiers (proceed / reduceSpeed / considerTurningBack). **Honesty note on evidence strength**: the deaf-driver visual-reliance and emergency-detection gap is both research-documented (SafeDrive4Deaf, n=25, 100% finding) and first-person-attested (Bauman). First-person *snow-specific* deaf-driver accounts are sparse; the whiteout framing above is therefore a labeled need-grounded composite drawn from the cited deaf-driver evidence plus this file's own whiteout voices (Sapporo turn-around; "if you can't see the next arrow, you're in a real whiteout") — it is not overclaimed as a real named snow testimony.

---

(Future voices recorded as encountered; the corpus grows with what we hear, not with what we hide.)
