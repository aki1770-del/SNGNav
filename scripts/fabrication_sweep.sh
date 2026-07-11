#!/usr/bin/env bash
# Fabrication sweep — absence must never become a confident positive.
#
# WHY THIS EXISTS (BOD-19, 2026-07-11)
# -----------------------------------
# driving_weather turned an EMPTY advisory feed into `WeatherCondition.clear()`,
# which hardcoded temperatureCelsius = 5.0 / visibilityMeters = 10000 / iceRisk =
# false. Absence of data became a measurement never taken, published to pub.dev at
# 535 downloads/month, while the package's own SAFETY_BOUNDARY.md certified that it
# "never asserts more than it observes".
#
# We found it by hand. Then an adversarial lens found the SAME CLASS in five more
# packages nobody had scoped — including pretrip_decision_advisor, which speaks to
# HER before she leaves the house and whose `noData` verdict hardcoded its peak
# hazard to `clear`. A no-forecast morning became a clear morning.
#
# That lens was a ONE-OFF AGENT. A defect class whose only detector is "somebody
# remembers to go looking" is not caught by a loom — it is caught by vigilance, and
# vigilance is what Sakichi's loom exists to make unnecessary. This script is the
# machine: it runs, it scans every package, and it EXITS NON-ZERO.
#
# WHAT IT CATCHES — the shape, not the instance:
#   an unmeasured / absent / failed input silently resolving to a SAFE-LOOKING value.
#
# HONEST BOUNDS (a loom sold as more than it is, is false comfort):
#   This is a SOUND PARTIAL. It is a lexical scanner, not a dataflow analysis. It
#   CANNOT know whether a given `?? 0` is safety-relevant. It WILL miss a fabrication
#   expressed in a shape not listed here, and it WILL flag benign code. Every hit is a
#   CANDIDATE requiring human judgement — never an automatic verdict. Its job is to
#   make the class VISIBLE and force a decision, not to decide.
#   Suppress a reviewed, genuinely-benign hit with a trailing:  // fabrication-ok: <why>
#   The suppression is deliberate friction: you must say WHY in the code, where the
#   next reader sees it.
#
# Usage:
#   scripts/fabrication_sweep.sh                 # scan packages/ + lib/ (exit 1 on hits)
#   scripts/fabrication_sweep.sh --self-test     # PROVE the sweep fires on the real defect
#   scripts/fabrication_sweep.sh <path> [...]    # scan specific paths
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Rules are PARALLEL ARRAYS, not a delimited table.
#
# The first draft packed <id>|<regex>|<meaning> into one string — and `|` is also the
# regex ALTERNATION operator, so `${rest%%|*}` truncated every regex at its first
# alternation: `(temperatureCelsius|visibilityMeters|...)` became `(temperatureCelsius`,
# an unclosed group matching nothing. Only the two pipe-free rules survived. The
# scanner silently matched nothing and would have reported PASS over a catalog full of
# fabrications — the exact defect class it exists to catch, inside the detector itself.
# It was caught ONLY because --self-test requires the sweep to FIRE on the real defect.
# That is the whole argument for falsification-proving a loom before trusting it.
RULE_IDS=(FAB-1 FAB-2 FAB-3 FAB-4 FAB-5 FAB-6)
RULE_RES=(
  '\?\?[[:space:]]*(false|0|0\.0|1\.0)\b'
  '\.isEmpty[^;]*\)[[:space:]]*\{[[:space:]]*$'
  '(temperatureCelsius|visibilityMeters|windSpeedKmh|gripFactor|confidence)[[:space:]]*=[[:space:]]*-?[0-9]'
  'LatLng\([[:space:]]*0[[:space:]]*,[[:space:]]*0[[:space:]]*\)'
  'catch[^{]*\{[^}]*return[[:space:]]+(true|0|0\.0|[A-Za-z]+\.(clear|dry|normal|ok|safe|proceed))'
  'kAssumed'
)
RULE_WHY=(
  'an absent value silently becomes a number/flag — is the fallback a MEASUREMENT you did not take?'
  'an empty collection branches — does it resolve to a POSITIVE verdict? (an empty feed is not a clear road)'
  'a measured quantity is assigned a LITERAL in a constructor — a measurement manufactured from nothing'
  'Null Island — a real coordinate in the Gulf of Guinea used as "unknown position"'
  'a CATCH block returns a success/benign value — the failure is swallowed and reported as fine'
  'a constant whose very name assumes an unmeasured condition'
)

scan() {
  local -a paths=("$@")
  local hits=0
  local i
  for i in "${!RULE_IDS[@]}"; do
    local id="${RULE_IDS[$i]}"
    local re="${RULE_RES[$i]}"
    local meaning="${RULE_WHY[$i]}"
    local found
    found="$(grep -rInE --include=*.dart "$re" "${paths[@]}" 2>/dev/null \
      | grep -v '/test/' | grep -v '_test\.dart' | grep -v '/example/' \
      | grep -viE 'fabrication-ok:' \
      | grep -viE ':[0-9]+:[[:space:]]*(///|//|\*|/\*)' || true)"
    if [[ -n "$found" ]]; then
      echo ""
      echo "  [$id] $meaning"
      printf '%s\n' "$found" | sed 's/^/      /'
      hits=$((hits + $(printf '%s\n' "$found" | wc -l)))
    fi
  done
  echo "$hits"
}

if [[ "${1:-}" == "--self-test" ]]; then
  # PROVE THE LOOM. A gate never shown to FAIL on the real defect is a green light
  # with no thread behind it — that is the exact failure of 2026-07-11 (a manifest
  # guard scored 10/10 while blessing a dead voice lane).
  #
  # So: reconstruct the REAL defects this sweep exists for, and require it to FIRE.
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/lib"

  # The real driving_weather 0.4.4 fabrication (verbatim shape).
  cat > "$tmp/lib/weather_condition.dart" <<'EOF'
class WeatherCondition {
  const WeatherCondition.clear({required this.timestamp})
      : temperatureCelsius = 5.0,
        visibilityMeters = 10000.0,
        windSpeedKmh = 0.0,
        iceRisk = false;
}
EOF
  # The real routing_engine Null Island.
  cat > "$tmp/lib/routing.dart" <<'EOF'
final pos = shapeIdx < allPoints.length ? allPoints[shapeIdx] : const LatLng(0, 0);
EOF
  # The real vehicle_condition_fusion assumed-above-freezing constant.
  cat > "$tmp/lib/fusion.dart" <<'EOF'
const double kAssumedAboveFreezingCelsius = 5.0;
final temp = s.airTempC ?? 5.0;
EOF
  # A benign file that must NOT fire (false-positive guard).
  cat > "$tmp/lib/benign.dart" <<'EOF'
final label = maybeName ?? 'unknown';
final count = items.length;
EOF

  echo ">> SELF-TEST: does the sweep FIRE on the real defects it exists to catch?"
  pass=0; total=0

  for f in weather_condition routing fusion; do
    total=$((total + 1))
    n="$(scan "$tmp/lib/$f.dart" | tail -1)"
    if [[ "$n" -gt 0 ]]; then
      echo "   PASS  $f.dart -> FIRED ($n hit(s)) — the real defect is caught"
      pass=$((pass + 1))
    else
      echo "   FAIL  $f.dart -> SILENT. The sweep does not catch the defect it was built for."
    fi
  done

  total=$((total + 1))
  n="$(scan "$tmp/lib/benign.dart" | tail -1)"
  if [[ "$n" -eq 0 ]]; then
    echo "   PASS  benign.dart -> silent (no false positive)"
    pass=$((pass + 1))
  else
    echo "   FAIL  benign.dart -> $n false positive(s); the sweep cries wolf and will be ignored"
  fi

  echo ""
  echo ">> SELF-TEST: $pass/$total"
  [[ "$pass" == "$total" ]] || exit 1
  exit 0
fi

if [[ $# -gt 0 ]]; then
  TARGETS=("$@")
else
  TARGETS=("$ROOT/packages" "$ROOT/lib")
fi

echo ">> Fabrication sweep — absence must never become a confident positive"
echo "   (SOUND PARTIAL: every hit is a CANDIDATE for judgement, never a verdict.)"
out="$(scan "${TARGETS[@]}")"
hits="$(printf '%s' "$out" | tail -1)"
printf '%s\n' "$out" | sed '$d'

echo ""
if [[ "${hits:-0}" -gt 0 ]]; then
  echo "FAIL: $hits candidate fabrication site(s). Each one is asking the same question:"
  echo "      does an absent, failed, or unmeasured input here become a SAFE-LOOKING value?"
  echo "      If it is genuinely benign, say why in the code:  // fabrication-ok: <reason>"
  exit 1
fi
echo "PASS: no candidate fabrication sites."
exit 0
