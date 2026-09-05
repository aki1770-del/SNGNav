# Release attestation — `nav2_safety_layer 0.1.4`

A record of exactly what was run before this version was published, and exactly what
the release may and may not be relied on for. This is a release-class attestation, not
a pull-request record.

⚑ **THE SCOPE IS NARROWER THAN "GREEN" AND SAYS SO.** A narrower measurement must never
wear a broader label. The gating suite passes **with four live defects excluded by tag**.
Both results are recorded below. Neither number stands alone.

## (i) Commit
Attested against the commit recorded in the same turn as this file (see `git log` for
`packages/nav2_safety_layer`); tree clean at publish time.

## (ii) Host environment
Ubuntu 24.04.4 LTS · Linux 6.18.5 · Dart SDK **3.11.1 (stable)** · 30 GiB RAM.
Pure-Dart package; no platform channel; no waiver class needed or claimed.

## (iii)–(vi) Commands run verbatim, with exit codes captured directly

| # | command | exit | result |
|---|---|---|---|
| 1 | `dart pub get` | 0 | resolved |
| 2 | `dart analyze` | 0 | **No issues found** |
| 3 | `dart format --set-exit-if-changed .` | 0 | 9 files, **0 changed** |
| 4 | `dart test -x pinned-live` **(GATE)** | 0 | **All tests passed** |
| 5 | `dart test -t pinned-live` **(EXCLUDED)** | 1 | **+0 −4 — four live defects, by design** |
| 6 | `sibling_constraint_check.py` | 0 | 17 constraints judged, pass |
| 7 | `dart pub publish --dry-run` | — | 1 warning (uncommitted tree), cleared by committing first |

⚑ **Row 3 was initially misread.** The first run reported `4 changed` because the shell
captured `sed`'s exit code, not `dart format`'s. Re-run with the exit captured directly:
0 changed, exit 0. Recorded because the near-miss is the same class of error this release
exists to fix.

## What 0.1.4 MAY claim
- The obstacle→ice fabrication is removed; obstacle events map to `RoadSurfaceCondition.unknown`. Guarded by BI-7.
- A `STOP` following a cap-consuming advisory burst reaches the driver. Guarded by BI-9.
- No API changed; `^0.1.3` consumers receive it without editing a line.

## What 0.1.4 MAY NOT claim
- **Not** that unreadable input is detectable (PI-01…PI-04 live).
- **Not** that action severity survives to the HMI (PI-05 live — `STOP` and `LIMIT` remain byte-identical).
- **Not** that `polygon_name` is relayed on the monitor path (D-08 live).
- **Not** that the package is safe as the sole path for a reflexive-stop architecture — it is
  QM, and has no liveness clock (see the assumptions of use, AoU-3 / AoU-7).

**Unverified is never the same as cleared.** The four excluded defects are unfixed, not
unmeasured.
