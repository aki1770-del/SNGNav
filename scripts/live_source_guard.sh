#!/usr/bin/env bash
# ── live_source_guard.sh ──────────────────────────────────────────────────────
# A live provider must never assert a synthetic observation.
#
# WHY (PHIL-001 / D3 supreme): HER is the driver in unexpected snow. A synthetic
# "clear" emitted by something she believes is measuring the road is not a bug in
# a data type — it is the road telling her it is safe when nobody looked. The
# contract already exists in prose, at driving_weather/lib/src/weather_condition.dart:
#
#     "Nothing was measured. Every measured field is null. This is what an empty
#      feed, a coverage gap, or a source that reports no observation actually
#      means. It is NOT 'the road is clear'."
#     "A live provider must never construct this: an absent measurement is
#      WeatherCondition.unknown."
#
# ⚑ That second sentence is a RULE, and a rule is not a loom. Measured 2026-08-20:
#   it holds — 0 violations across 11 network-bearing packages — and nothing
#   whatsoever made it hold. It held because whoever wrote each adapter remembered.
#   This is the same shape found the same day in nav2_smac_planner, where a
#   safety-critical footprint argument is defaulted to empty and the test suite
#   calls it 5 times without one: correct today, silent when it stops being.
#
# THE RULE, file-level and mechanical:
#   a Dart file under lib/ that reaches the network (package:http, package:dio,
#   HttpClient) must not construct a simulated observation
#   (WeatherCondition.simulatedClear, ObservationSource.simulated).
#
# Package-level would be wrong and was measured to be wrong: driving_weather
# legitimately contains BOTH the simulator and a live fetcher, in different files.
#
# EXIT 0 clean · 1 a live source asserts a synthetic observation
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

NET='package:http|package:dio|HttpClient'
SIM='simulatedClear|ObservationSource\.simulated'

echo "===== live-source guard ====="
fail=0
checked=0
while IFS= read -r f; do
  checked=$((checked + 1))
  if grep -qE "$SIM" "$f"; then
    echo "  FAIL  $f"
    echo "        reaches the network AND constructs a synthetic observation."
    grep -nE "$SIM" "$f" | head -3 | sed 's/^/          /'
    fail=1
  fi
done < <(grep -rlE "$NET" packages/*/lib --include=*.dart 2>/dev/null)

echo "  network-reaching files checked: $checked"
if [ "$fail" -eq 0 ]; then
  echo "  pass  no live source asserts a synthetic observation"
  echo "============================"
  echo "LIVE-SOURCE GUARD: pass"
  exit 0
fi
echo "============================"
cat <<'MSG'
LIVE-SOURCE GUARD: FAIL

A file that fetches from a real feed is constructing a simulated observation.
An absent measurement is WeatherCondition.unknown — every field null — never a
synthetic clear. She cannot tell the difference, and she is the one driving.

Fix the provider, not the guard.
MSG
exit 1
